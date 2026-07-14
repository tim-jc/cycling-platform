gold_validation_sql_values <- function(values) {
  paste(
    values,
    collapse = ", "
  )
}

gold_validation_sql_strings <- function(connection, values) {
  paste(
    DBI::dbQuoteString(
      conn = connection,
      x = as.character(values)
    ),
    collapse = ", "
  )
}

gold_activity_best_efforts_publication_checks <- function(
  connection,
  config = list(),
  check_scope = "gold_publication",
  per_check_timeout_seconds = NULL,
  deadline = NULL
) {
  metrics <- config$transforms$gold_best_effort_metrics

  if (is.null(metrics)) {
    metrics <- c(
      "watts",
      "cadence_rpm",
      "heartrate_bpm"
    )
  }

  durations <- config$transforms$gold_best_effort_durations

  if (is.null(durations)) {
    durations <- default_best_effort_durations()
  }

  calculation_version <- gold_activity_best_efforts_calculation_version(
    config = config
  )

  metrics_sql <- gold_validation_sql_strings(
    connection = connection,
    values = metrics
  )

  durations_sql <- gold_validation_sql_values(
    as.integer(durations)
  )

  calculation_version_sql <- gold_validation_sql_strings(
    connection = connection,
    values = calculation_version
  )

  checks <- list()

  table_exists <- get_gold_activity_best_efforts_table_exists(
    connection = connection
  )

  checks <- append_validation_result(
    checks,
    validation_table_exists_result(
      table_exists = table_exists,
      check_scope = check_scope
    )
  )

  if (!isTRUE(table_exists)) {
    return(dplyr::bind_rows(checks))
  }

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_latest_transform_success",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        WITH latest AS (
          SELECT
            transform_run_id,
            run_status,
            completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_best_efforts'
          ORDER BY transform_run_id DESC
          LIMIT 1
        )
        SELECT
          'missing_or_failed_latest_gold_transform' AS issue_type
        FROM DUAL
        WHERE NOT EXISTS (
            SELECT 1
            FROM latest
            WHERE run_status = 'SUCCESS'
              AND completed_at IS NOT NULL
          )
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_latest_transform_fresh",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        WITH latest AS (
          SELECT
            transform_run_id,
            run_status,
            completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_best_efforts'
            AND run_status = 'SUCCESS'
          ORDER BY transform_run_id DESC
          LIMIT 1
        ),
        latest_silver_stream_transform AS (
          SELECT MAX(completed_at) AS latest_silver_stream_completed_at
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'silver'
            AND entity_name = 'activity_streams'
            AND run_status = 'SUCCESS'
        )
        SELECT
          latest.transform_run_id,
          latest.completed_at,
          latest_silver_stream_transform.latest_silver_stream_completed_at
        FROM latest_silver_stream_transform
        LEFT JOIN latest
          ON 1 = 1
        WHERE latest_silver_stream_transform.latest_silver_stream_completed_at IS NOT NULL
          AND (
            latest.transform_run_id IS NULL
            OR latest.completed_at
              < latest_silver_stream_transform.latest_silver_stream_completed_at
          )
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_latest_batches_success",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        WITH latest AS (
          SELECT transform_run_id
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_best_efforts'
          ORDER BY transform_run_id DESC
          LIMIT 1
        )
        SELECT
          batches.transform_run_batch_id,
          batches.batch_number,
          batches.batch_status
        FROM latest
        INNER JOIN cycling_platform_admin.transform_run_batch batches
          ON batches.transform_run_id = latest.transform_run_id
        WHERE batches.batch_status <> 'SUCCESS'
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_duplicate_primary_key",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          activity_id,
          metric_name,
          duration_seconds,
          COUNT(*) AS issue_count
        FROM cycling_platform_gold.activity_best_efforts
        GROUP BY
          activity_id,
          metric_name,
          duration_seconds
        HAVING COUNT(*) > 1
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_orphaned_activity_ids",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = "
        SELECT
          best_efforts.activity_id
        FROM cycling_platform_gold.activity_best_efforts best_efforts
        LEFT JOIN cycling_platform_silver.activities activities
          ON activities.activity_id = best_efforts.activity_id
        WHERE activities.activity_id IS NULL
        GROUP BY best_efforts.activity_id
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_metric_names_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT DISTINCT metric_name
        FROM cycling_platform_gold.activity_best_efforts
        WHERE metric_name NOT IN ({metrics_sql})
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_durations_valid",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT DISTINCT duration_seconds
        FROM cycling_platform_gold.activity_best_efforts
        WHERE duration_seconds NOT IN ({durations_sql})
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "gold_activity_best_efforts_calculation_version_current",
      check_scope = check_scope,
      severity = "CRITICAL",
      query = glue::glue("
        SELECT
          activity_id,
          metric_name,
          duration_seconds,
          calculation_version
        FROM cycling_platform_gold.activity_best_efforts
        WHERE calculation_version IS NULL
           OR calculation_version = ''
           OR calculation_version <> {calculation_version_sql}
        LIMIT 1000
      "),
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  dplyr::bind_rows(checks)
}
