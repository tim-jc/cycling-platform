#' Platform Validation Has Critical Failures
#'
#' @param validation_results Validation result data frame.
#'
#' @return TRUE when any critical check failed.
platform_validation_has_critical_failures <- function(validation_results) {
  any(
    validation_results$severity == "CRITICAL" &
      !validation_results$passed
  )
}

#' Gold Best Effort Duration Table SQL
#'
#' @param durations Integer vector of durations in seconds.
#'
#' @return SQL fragment representing the configured durations.
gold_best_effort_duration_table_sql <- function(durations) {
  durations <- sort(
    unique(
      as.integer(durations)
    )
  )

  stopifnot(length(durations) > 0)
  stopifnot(all(durations > 0))

  paste(
    paste0(
      "SELECT ",
      durations,
      " AS duration_seconds"
    ),
    collapse = "\nUNION ALL\n"
  )
}

validation_table_exists <- function(
  connection,
  table_schema,
  table_name
) {
  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT COUNT(*) AS table_count
      FROM information_schema.tables
      WHERE table_schema = ?
        AND table_name = ?
    ",
    params = list(
      table_schema,
      table_name
    )
  )$table_count[[1]] > 0
}

validation_issue_count <- function(details) {
  if (nrow(details) == 0) {
    return(0L)
  }

  if ("issue_count" %in% names(details)) {
    return(
      as.integer(
        sum(
          details$issue_count,
          na.rm = TRUE
        )
      )
    )
  }

  as.integer(nrow(details))
}

validation_result <- function(
  check_name,
  check_scope,
  severity,
  details,
  query = NA_character_,
  started_at = as.POSIXct(NA),
  completed_at = as.POSIXct(NA),
  elapsed_seconds = NA_real_
) {
  issue_count <- validation_issue_count(details)

  tibble::tibble(
    check_name = check_name,
    check_scope = check_scope,
    severity = severity,
    passed = issue_count == 0L,
    issue_count = issue_count,
    started_at = started_at,
    completed_at = completed_at,
    elapsed_seconds = elapsed_seconds,
    details = list(details),
    query = query
  )
}

validation_timestamp <- function(timestamp = Sys.time()) {
  format(
    timestamp,
    "%Y-%m-%d %H:%M:%S %Z"
  )
}

validation_elapsed_seconds <- function(start_time) {
  round(
    as.numeric(
      difftime(
        Sys.time(),
        start_time,
        units = "secs"
      )
    ),
    1
  )
}

attach_validation_timing <- function(
  result,
  started_at,
  completed_at,
  elapsed_seconds
) {
  if (
    inherits(result, "data.frame") &&
      "check_name" %in% names(result)
  ) {
    result$started_at <- started_at
    result$completed_at <- completed_at
    result$elapsed_seconds <- elapsed_seconds
  }

  result
}

run_validation_check <- function(
  check_name,
  expr,
  source = NA_character_,
  likely_long_running = FALSE
) {
  start_time <- Sys.time()

  message(
    "Validation: starting ",
    check_name,
    " at ",
    validation_timestamp(start_time),
    if (isTRUE(likely_long_running)) {
      " (may scan large stream tables)"
    } else {
      ""
    }
  )

  tryCatch(
    {
      result <- force(expr)
      completed_at <- Sys.time()
      elapsed <- validation_elapsed_seconds(start_time)

      message(
        "Validation: completed ",
        check_name,
        " at ",
        validation_timestamp(completed_at),
        " in ",
        elapsed,
        "s"
      )

      attach_validation_timing(
        result = result,
        started_at = start_time,
        completed_at = completed_at,
        elapsed_seconds = elapsed
      )
    },
    error = function(e) {
      completed_at <- Sys.time()
      elapsed <- validation_elapsed_seconds(start_time)

      message(
        "Validation: failed ",
        check_name,
        " at ",
        validation_timestamp(completed_at),
        " after ",
        elapsed,
        "s"
      )

      if (!is.na(source) && nzchar(source)) {
        message(
          "Validation source: ",
          source
        )
      }

      message(
        "Validation error: ",
        conditionMessage(e)
      )

      stop(e)
    }
  )
}

validation_query_with_timeout <- function(
  query,
  timeout_seconds = NULL
) {
  if (
    is.null(timeout_seconds) ||
      is.na(timeout_seconds) ||
      timeout_seconds <= 0
  ) {
    return(query)
  }

  as.character(
    glue::glue(
      "SET STATEMENT max_statement_time={as.numeric(timeout_seconds)} FOR\n{query}"
    )
  )
}

validation_deadline <- function(overall_timeout_seconds = NULL) {
  if (
    is.null(overall_timeout_seconds) ||
      is.na(overall_timeout_seconds) ||
      overall_timeout_seconds <= 0
  ) {
    return(NULL)
  }

  Sys.time() + overall_timeout_seconds
}

assert_validation_deadline <- function(
  deadline,
  check_name
) {
  if (
    !is.null(deadline) &&
      Sys.time() >= deadline
  ) {
    stop(
      "Validation overall timeout reached before check: ",
      check_name,
      call. = FALSE
    )
  }

  invisible(NULL)
}

is_likely_long_running_validation <- function(check_name) {
  grepl(
    "stream|best_efforts|gold|raw_success",
    check_name
  )
}

run_validation_query <- function(
  connection,
  check_name,
  check_scope,
  severity,
  query,
  per_check_timeout_seconds = NULL,
  deadline = NULL
) {
  assert_validation_deadline(
    deadline = deadline,
    check_name = check_name
  )

  run_validation_check(
    check_name = check_name,
    source = "R/validation/validate_platform_completeness.R",
    likely_long_running = is_likely_long_running_validation(check_name),
    expr = {
      validation_result(
        check_name = check_name,
        check_scope = check_scope,
        severity = severity,
        details = DBI::dbGetQuery(
          conn = connection,
          statement = validation_query_with_timeout(
            query = query,
            timeout_seconds = per_check_timeout_seconds
          )
        ),
        query = query
      )
    }
  )
}

count_platform_completeness_checks <- function(
  validation_scope,
  include_gold,
  gold_table_exists,
  gold_metrics
) {
  if (identical(validation_scope, "publication")) {
    return(2L)
  }

  check_count <- 27L

  if (isTRUE(include_gold)) {
    check_count <- check_count + 1L

    if (isTRUE(gold_table_exists)) {
      check_count <- check_count +
        9L +
        (length(gold_metrics) * 2L) +
        6L
    }
  }

  check_count
}

append_validation_result <- function(
  checks,
  result
) {
  checks[[length(checks) + 1L]] <- result

  checks
}

log_validation_phase_complete <- function(start_time) {
  message(
    "Validation phase complete in ",
    validation_elapsed_seconds(start_time),
    "s."
  )
}

validation_table_exists_result <- function(
  table_exists,
  check_scope
) {
  run_validation_check(
    check_name = "gold_activity_best_efforts_table_exists",
    source = "information_schema.tables",
    expr = {
      validation_result(
        check_name = "gold_activity_best_efforts_table_exists",
        check_scope = check_scope,
        severity = "CRITICAL",
        details = if (table_exists) {
          data.frame()
        } else {
          data.frame(
            table_schema = "cycling_platform_gold",
            table_name = "activity_best_efforts"
          )
        },
        query = "information_schema.tables"
      )
    }
  )
}

get_gold_activity_best_efforts_table_exists <- function(connection) {
  run_validation_check(
    check_name = "gold_activity_best_efforts_table_metadata_lookup",
    source = "information_schema.tables",
    expr = {
      validation_table_exists(
        connection = connection,
        table_schema = "cycling_platform_gold",
        table_name = "activity_best_efforts"
      )
    },
    likely_long_running = FALSE
  )
}

validate_gold_metric_duration_coverage <- function(
  connection,
  metric_name,
  source_sql,
  durations,
  per_check_timeout_seconds = NULL,
  deadline = NULL
) {
  duration_sql <- gold_best_effort_duration_table_sql(durations)

  query <- glue::glue("
    WITH source_metric AS (
      {source_sql}
    ),
    durations AS (
      {duration_sql}
    ),
    expected AS (
      SELECT
        source_metric.activity_id,
        source_metric.metric_name,
        durations.duration_seconds
      FROM source_metric
      INNER JOIN durations
        ON durations.duration_seconds <= source_metric.metric_sample_count
    )
    SELECT
      expected.activity_id,
      expected.metric_name,
      expected.duration_seconds
    FROM expected
    LEFT JOIN cycling_platform_gold.activity_best_efforts best_efforts
      ON best_efforts.activity_id = expected.activity_id
     AND best_efforts.metric_name = expected.metric_name
     AND best_efforts.duration_seconds = expected.duration_seconds
    WHERE best_efforts.activity_id IS NULL
    ORDER BY
      expected.activity_id,
      expected.duration_seconds
    LIMIT 1000
  ")

  run_validation_query(
    connection = connection,
    check_name = paste0(
      "gold_best_efforts_",
      metric_name,
      "_duration_coverage"
    ),
    check_scope = "deep",
    severity = "CRITICAL",
    query = query,
    per_check_timeout_seconds = per_check_timeout_seconds,
    deadline = deadline
  )
}

validate_gold_metric_presence <- function(
  connection,
  metric_name,
  source_sql,
  per_check_timeout_seconds = NULL,
  deadline = NULL
) {
  query <- glue::glue("
    WITH source_metric AS (
      {source_sql}
    )
    SELECT
      source_metric.activity_id,
      source_metric.metric_name,
      source_metric.metric_sample_count
    FROM source_metric
    LEFT JOIN cycling_platform_gold.activity_best_efforts best_efforts
      ON best_efforts.activity_id = source_metric.activity_id
     AND best_efforts.metric_name = source_metric.metric_name
    WHERE source_metric.metric_sample_count > 0
      AND best_efforts.activity_id IS NULL
    GROUP BY
      source_metric.activity_id,
      source_metric.metric_name,
      source_metric.metric_sample_count
    ORDER BY source_metric.activity_id
    LIMIT 1000
  ")

  run_validation_query(
    connection = connection,
    check_name = paste0(
      "gold_best_efforts_",
      metric_name,
      "_presence"
    ),
    check_scope = "deep",
    severity = "CRITICAL",
    query = query,
    per_check_timeout_seconds = per_check_timeout_seconds,
    deadline = deadline
  )
}

gold_metric_source_sql <- function(metric_name) {
  if (identical(metric_name, "watts")) {
    return("
      SELECT
        activities.activity_id,
        'watts' AS metric_name,
        COUNT(streams.watts) AS metric_sample_count
      FROM cycling_platform_silver.activities activities
      LEFT JOIN cycling_platform_silver.activity_streams streams
        ON streams.activity_id = activities.activity_id
      WHERE activities.is_device_watts = 1
      GROUP BY activities.activity_id
    ")
  }

  metric_column <- switch(
    metric_name,
    cadence_rpm = "cadence_rpm",
    heartrate_bpm = "heartrate_bpm",
    stop(
      "Unsupported Gold best effort validation metric: ",
      metric_name,
      call. = FALSE
    )
  )

  glue::glue("
    SELECT
      streams.activity_id,
      '{metric_name}' AS metric_name,
      COUNT(streams.{metric_column}) AS metric_sample_count
    FROM cycling_platform_silver.activity_streams streams
    GROUP BY streams.activity_id
    HAVING COUNT(streams.{metric_column}) > 0
  ")
}

#' Validate Platform Completeness
#'
#' Validate that records do not disappear unexpectedly across Raw, Silver, and
#' Gold transformations.
#'
#' @param connection DBI connection.
#' @param config Platform configuration.
#' @param include_gold Whether to include Gold checks.
#' @param gold_metrics Metrics expected in gold.activity_best_efforts.
#' @param gold_durations Durations expected in gold.activity_best_efforts.
#' @param validation_scope `publication` for fast blocking checks, or `deep`
#'   for the full validation suite.
#' @param per_check_timeout_seconds Optional MariaDB statement timeout per
#'   validation query.
#' @param overall_timeout_seconds Optional overall timeout checked between
#'   validation checks.
#'
#' @return Tibble with check_name, severity, passed, issue_count, details, query.
validate_platform_completeness <- function(
  connection,
  config = list(),
  include_gold = TRUE,
  gold_metrics = NULL,
  gold_durations = NULL,
  validation_scope = c(
    "deep",
    "publication"
  ),
  per_check_timeout_seconds = NULL,
  overall_timeout_seconds = NULL
) {
  validation_scope <- match.arg(validation_scope)

  if (is.null(gold_metrics)) {
    gold_metrics <- config$transforms$gold_best_effort_metrics
  }

  if (is.null(gold_metrics)) {
    gold_metrics <- c(
      "watts",
      "cadence_rpm",
      "heartrate_bpm"
    )
  }

  gold_metrics <- as.character(
    unlist(
      gold_metrics,
      use.names = FALSE
    )
  )

  if (is.null(gold_durations)) {
    gold_durations <- config$transforms$gold_best_effort_durations
  }

  if (is.null(gold_durations)) {
    gold_durations <- default_best_effort_durations()
  }

  gold_durations <- as.integer(
    unlist(
      gold_durations,
      use.names = FALSE
    )
  )

  validation_started_at <- Sys.time()
  deadline <- validation_deadline(
    overall_timeout_seconds = overall_timeout_seconds
  )

  gold_table_exists <- FALSE

  if (
    identical(validation_scope, "deep") &&
      isTRUE(include_gold)
  ) {
    gold_table_exists <- get_gold_activity_best_efforts_table_exists(
      connection = connection
    )
  }

  check_count <- count_platform_completeness_checks(
    validation_scope = validation_scope,
    include_gold = include_gold,
    gold_table_exists = gold_table_exists,
    gold_metrics = gold_metrics
  )

  message(
    "Validation phase: running ",
    check_count,
    " checks."
  )

  checks <- list()

  checks <- append_validation_result(
    checks,
    run_validation_query(
      connection = connection,
      check_name = "raw_activities_missing_from_silver",
      check_scope = "publication",
      severity = "CRITICAL",
      query = "
        SELECT
          raw.activity_id
        FROM cycling_platform_raw.activities raw
        LEFT JOIN cycling_platform_silver.activities silver
          ON silver.activity_id = raw.activity_id
        WHERE silver.activity_id IS NULL
        ORDER BY raw.activity_id
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
      check_name = "silver_activities_has_streams_without_stream_rows",
      check_scope = "publication",
      severity = "CRITICAL",
      query = "
        SELECT
          activities.activity_id
        FROM cycling_platform_silver.activities activities
        WHERE activities.has_streams = 1
          AND NOT EXISTS (
            SELECT 1
            FROM cycling_platform_silver.activity_streams streams
            WHERE streams.activity_id = activities.activity_id
            LIMIT 1
          )
        ORDER BY activities.activity_id
        LIMIT 1000
      ",
      per_check_timeout_seconds = per_check_timeout_seconds,
      deadline = deadline
    )
  )

  if (identical(validation_scope, "deep")) {
    checks <- append_validation_result(
      checks,
      run_validation_query(
        connection = connection,
        check_name = "silver_activity_has_streams_status_mismatch",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            activities.activity_id,
            activities.has_streams
          FROM cycling_platform_silver.activities activities
          WHERE activities.has_streams <> EXISTS (
            SELECT 1
            FROM cycling_platform_silver.activity_streams streams
            WHERE streams.activity_id = activities.activity_id
            LIMIT 1
          )
          ORDER BY activities.activity_id
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
        check_name = "silver_streams_without_silver_activities",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            streams.activity_id,
            COUNT(*) AS issue_count
          FROM cycling_platform_silver.activity_streams streams
          LEFT JOIN cycling_platform_silver.activities activities
            ON activities.activity_id = streams.activity_id
          WHERE activities.activity_id IS NULL
          GROUP BY streams.activity_id
          ORDER BY streams.activity_id
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
        check_name = "silver_stream_duplicate_activity_sample",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            activity_id,
            sample_index,
            COUNT(*) AS issue_count
          FROM cycling_platform_silver.activity_streams
          GROUP BY
            activity_id,
            sample_index
          HAVING COUNT(*) > 1
          ORDER BY activity_id, sample_index
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
        check_name = "raw_and_silver_activity_counts_match",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            CASE
              WHEN raw_counts.row_count = silver_counts.row_count THEN 0
              ELSE 1
            END AS issue_count,
            raw_counts.row_count AS raw_activity_count,
            silver_counts.row_count AS silver_activity_count
          FROM (
            SELECT COUNT(*) AS row_count
            FROM cycling_platform_raw.activities
          ) raw_counts
          CROSS JOIN (
            SELECT COUNT(*) AS row_count
            FROM cycling_platform_silver.activities
          ) silver_counts
          WHERE raw_counts.row_count <> silver_counts.row_count
        ",
        per_check_timeout_seconds = per_check_timeout_seconds,
        deadline = deadline
      )
    )

    checks <- append_validation_result(
      checks,
      run_validation_query(
        connection = connection,
        check_name = "raw_success_streams_missing_from_silver",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          WITH raw_success AS (
            SELECT activity_id
            FROM cycling_platform_raw.activities
            WHERE stream_status = 'SUCCESS'
          ),
          raw_streams AS (
            SELECT
              activity_id,
              COUNT(*) AS raw_stream_count
            FROM cycling_platform_raw.activity_streams
            GROUP BY activity_id
          ),
          silver_streams AS (
            SELECT
              activity_id,
              COUNT(*) AS silver_row_count
            FROM cycling_platform_silver.activity_streams
            GROUP BY activity_id
          )
          SELECT
            raw_success.activity_id,
            COALESCE(raw_streams.raw_stream_count, 0) AS raw_stream_count
          FROM raw_success
          INNER JOIN raw_streams
            ON raw_streams.activity_id = raw_success.activity_id
          LEFT JOIN silver_streams
            ON silver_streams.activity_id = raw_success.activity_id
          WHERE COALESCE(silver_streams.silver_row_count, 0) = 0
          ORDER BY raw_success.activity_id
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
        check_name = "raw_success_stream_expected_count_mismatch",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          WITH raw_summary AS (
            SELECT
              activities.activity_id,
              MAX(raw_streams.original_size) AS expected_sample_count
            FROM cycling_platform_raw.activities activities
            INNER JOIN cycling_platform_raw.activity_streams raw_streams
              ON raw_streams.activity_id = activities.activity_id
            WHERE activities.stream_status = 'SUCCESS'
            GROUP BY activities.activity_id
          ),
          silver_summary AS (
            SELECT
              activity_id,
              COUNT(*) AS silver_row_count
            FROM cycling_platform_silver.activity_streams
            GROUP BY activity_id
          )
          SELECT
            raw_summary.activity_id,
            raw_summary.expected_sample_count,
            COALESCE(silver_summary.silver_row_count, 0) AS silver_row_count
          FROM raw_summary
          LEFT JOIN silver_summary
            ON silver_summary.activity_id = raw_summary.activity_id
          WHERE raw_summary.expected_sample_count
            <> COALESCE(silver_summary.silver_row_count, 0)
          ORDER BY raw_summary.activity_id
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
        check_name = "raw_google_health_rhr_duplicate_keys",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            daily_resting_heart_rate_key,
            COUNT(*) AS issue_count
          FROM cycling_platform_raw.google_health_daily_resting_heart_rate
          GROUP BY daily_resting_heart_rate_key
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
        check_name = "raw_google_health_rhr_required_fields_valid",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            daily_resting_heart_rate_key,
            google_health_user_id,
            activity_date,
            resting_heart_rate_bpm,
            run_id,
            retrieved_at
          FROM cycling_platform_raw.google_health_daily_resting_heart_rate
          WHERE google_health_user_id IS NULL
             OR google_health_user_id = ''
             OR activity_date IS NULL
             OR resting_heart_rate_bpm IS NULL
             OR resting_heart_rate_bpm <= 0
             OR run_id IS NULL
             OR retrieved_at IS NULL
             OR daily_resting_heart_rate_payload IS NULL
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
        check_name = "raw_google_health_rhr_duplicate_source_grain",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            google_health_user_id,
            activity_date,
            COALESCE(source_data_point_id, '') AS source_data_point_id,
            COALESCE(source_ecosystem, '') AS source_ecosystem,
            COALESCE(source_platform, '') AS source_platform,
            COALESCE(source_recording_method, '') AS source_recording_method,
            COALESCE(source_device_manufacturer, '') AS source_device_manufacturer,
            COALESCE(source_device_model, '') AS source_device_model,
            SHA2(CAST(daily_resting_heart_rate_payload AS CHAR), 256)
              AS payload_hash,
            COUNT(*) AS issue_count
          FROM cycling_platform_raw.google_health_daily_resting_heart_rate
          GROUP BY
            google_health_user_id,
            activity_date,
            COALESCE(source_data_point_id, ''),
            COALESCE(source_ecosystem, ''),
            COALESCE(source_platform, ''),
            COALESCE(source_recording_method, ''),
            COALESCE(source_device_manufacturer, ''),
            COALESCE(source_device_model, ''),
            SHA2(CAST(daily_resting_heart_rate_payload AS CHAR), 256)
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
        check_name = "raw_google_health_hrv_duplicate_keys",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            daily_heart_rate_variability_key,
            COUNT(*) AS issue_count
          FROM cycling_platform_raw.google_health_daily_heart_rate_variability
          GROUP BY daily_heart_rate_variability_key
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
        check_name = "raw_google_health_hrv_duplicate_source_grain",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            google_health_user_id,
            activity_date,
            COALESCE(source_data_point_id, '') AS source_data_point_id,
            COALESCE(source_ecosystem, '') AS source_ecosystem,
            COALESCE(source_platform, '') AS source_platform,
            COALESCE(source_recording_method, '') AS source_recording_method,
            COALESCE(source_device_manufacturer, '') AS source_device_manufacturer,
            COALESCE(source_device_model, '') AS source_device_model,
            SHA2(CAST(daily_heart_rate_variability_payload AS CHAR), 256)
              AS payload_hash,
            COUNT(*) AS issue_count
          FROM cycling_platform_raw.google_health_daily_heart_rate_variability
          GROUP BY
            google_health_user_id,
            activity_date,
            COALESCE(source_data_point_id, ''),
            COALESCE(source_ecosystem, ''),
            COALESCE(source_platform, ''),
            COALESCE(source_recording_method, ''),
            COALESCE(source_device_manufacturer, ''),
            COALESCE(source_device_model, ''),
            SHA2(CAST(daily_heart_rate_variability_payload AS CHAR), 256)
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
        check_name = "raw_google_health_hrv_required_fields_valid",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            daily_heart_rate_variability_key,
            google_health_user_id,
            activity_date,
            average_hrv_milliseconds,
            deep_sleep_rmssd_milliseconds,
            non_rem_heart_rate_bpm,
            entropy,
            run_id,
            retrieved_at
          FROM cycling_platform_raw.google_health_daily_heart_rate_variability
          WHERE google_health_user_id IS NULL
             OR google_health_user_id = ''
             OR activity_date IS NULL
             OR run_id IS NULL
             OR retrieved_at IS NULL
             OR daily_heart_rate_variability_payload IS NULL
             OR average_hrv_milliseconds < 0
             OR deep_sleep_rmssd_milliseconds < 0
             OR non_rem_heart_rate_bpm < 0
             OR entropy < 0
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
        check_name = "raw_google_health_respiratory_rate_duplicate_keys",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            daily_respiratory_rate_key,
            COUNT(*) AS issue_count
          FROM cycling_platform_raw.google_health_daily_respiratory_rate
          GROUP BY daily_respiratory_rate_key
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
        check_name = "raw_google_health_respiratory_rate_required_fields_valid",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            daily_respiratory_rate_key,
            google_health_user_id,
            activity_date,
            respiratory_rate_brpm,
            run_id,
            retrieved_at
          FROM cycling_platform_raw.google_health_daily_respiratory_rate
          WHERE google_health_user_id IS NULL
             OR google_health_user_id = ''
             OR activity_date IS NULL
             OR respiratory_rate_brpm IS NULL
             OR respiratory_rate_brpm <= 0
             OR run_id IS NULL
             OR retrieved_at IS NULL
             OR daily_respiratory_rate_payload IS NULL
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
        check_name = "raw_google_health_respiratory_rate_duplicate_source_grain",
        check_scope = "deep",
        severity = "CRITICAL",
        query = "
          SELECT
            google_health_user_id,
            activity_date,
            COALESCE(source_data_point_id, '') AS source_data_point_id,
            COALESCE(source_ecosystem, '') AS source_ecosystem,
            COALESCE(source_platform, '') AS source_platform,
            COALESCE(source_recording_method, '') AS source_recording_method,
            COALESCE(source_device_manufacturer, '') AS source_device_manufacturer,
            COALESCE(source_device_model, '') AS source_device_model,
            SHA2(CAST(daily_respiratory_rate_payload AS CHAR), 256)
              AS payload_hash,
            COUNT(*) AS issue_count
          FROM cycling_platform_raw.google_health_daily_respiratory_rate
          GROUP BY
            google_health_user_id,
            activity_date,
            COALESCE(source_data_point_id, ''),
            COALESCE(source_ecosystem, ''),
            COALESCE(source_platform, ''),
            COALESCE(source_recording_method, ''),
            COALESCE(source_device_manufacturer, ''),
            COALESCE(source_device_model, ''),
            SHA2(CAST(daily_respiratory_rate_payload AS CHAR), 256)
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
        check_name = "raw_google_health_rhr_source_provenance_missing",
        check_scope = "deep",
        severity = "WARNING",
        query = "
          SELECT
            daily_resting_heart_rate_key,
            google_health_user_id,
            activity_date,
            source_ecosystem,
            source_platform,
            source_recording_method
          FROM cycling_platform_raw.google_health_daily_resting_heart_rate
          WHERE source_ecosystem IS NULL
             OR source_ecosystem = ''
             OR source_ecosystem = 'unknown'
             OR source_platform IS NULL
             OR source_platform = ''
             OR source_recording_method IS NULL
             OR source_recording_method = ''
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
        check_name = "raw_google_health_hrv_source_provenance_missing",
        check_scope = "deep",
        severity = "WARNING",
        query = "
          SELECT
            daily_heart_rate_variability_key,
            google_health_user_id,
            activity_date,
            source_ecosystem,
            source_platform,
            source_recording_method
          FROM cycling_platform_raw.google_health_daily_heart_rate_variability
          WHERE source_ecosystem IS NULL
             OR source_ecosystem = ''
             OR source_ecosystem = 'unknown'
             OR source_platform IS NULL
             OR source_platform = ''
             OR source_recording_method IS NULL
             OR source_recording_method = ''
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
        check_name = "raw_google_health_respiratory_rate_source_provenance_missing",
        check_scope = "deep",
        severity = "WARNING",
        query = "
          SELECT
            daily_respiratory_rate_key,
            google_health_user_id,
            activity_date,
            source_ecosystem,
            source_platform,
            source_recording_method
          FROM cycling_platform_raw.google_health_daily_respiratory_rate
          WHERE source_ecosystem IS NULL
             OR source_ecosystem = ''
             OR source_ecosystem = 'unknown'
             OR source_platform IS NULL
             OR source_platform = ''
             OR source_recording_method IS NULL
             OR source_recording_method = ''
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
        check_name = "raw_google_health_rhr_multiple_ecosystems_per_date",
        check_scope = "deep",
        severity = "INFO",
        query = "
          SELECT
            google_health_user_id,
            activity_date,
            COUNT(DISTINCT source_ecosystem) AS source_ecosystem_count,
            GROUP_CONCAT(DISTINCT source_ecosystem ORDER BY source_ecosystem)
              AS source_ecosystems
          FROM cycling_platform_raw.google_health_daily_resting_heart_rate
          WHERE source_ecosystem IS NOT NULL
            AND source_ecosystem <> ''
            AND source_ecosystem <> 'unknown'
          GROUP BY
            google_health_user_id,
            activity_date
          HAVING COUNT(DISTINCT source_ecosystem) > 1
          ORDER BY activity_date DESC
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
        check_name = "raw_google_health_hrv_multiple_ecosystems_per_date",
        check_scope = "deep",
        severity = "INFO",
        query = "
          SELECT
            google_health_user_id,
            activity_date,
            COUNT(DISTINCT source_ecosystem) AS source_ecosystem_count,
            GROUP_CONCAT(DISTINCT source_ecosystem ORDER BY source_ecosystem)
              AS source_ecosystems
          FROM cycling_platform_raw.google_health_daily_heart_rate_variability
          WHERE source_ecosystem IS NOT NULL
            AND source_ecosystem <> ''
            AND source_ecosystem <> 'unknown'
          GROUP BY
            google_health_user_id,
            activity_date
          HAVING COUNT(DISTINCT source_ecosystem) > 1
          ORDER BY activity_date DESC
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
        check_name = "raw_google_health_respiratory_rate_multiple_ecosystems_per_date",
        check_scope = "deep",
        severity = "INFO",
        query = "
          SELECT
            google_health_user_id,
            activity_date,
            COUNT(DISTINCT source_ecosystem) AS source_ecosystem_count,
            GROUP_CONCAT(DISTINCT source_ecosystem ORDER BY source_ecosystem)
              AS source_ecosystems
          FROM cycling_platform_raw.google_health_daily_respiratory_rate
          WHERE source_ecosystem IS NOT NULL
            AND source_ecosystem <> ''
            AND source_ecosystem <> 'unknown'
          GROUP BY
            google_health_user_id,
            activity_date
          HAVING COUNT(DISTINCT source_ecosystem) > 1
          ORDER BY activity_date DESC
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
        check_name = "raw_google_health_respiratory_rate_recent_coverage",
        check_scope = "deep",
        severity = "WARNING",
        query = "
          SELECT
            1 AS issue_count,
            'No successful daily respiratory-rate request in the last 2 days'
              AS issue
          WHERE NOT EXISTS (
            SELECT 1
            FROM cycling_platform_admin.etl_request_log
            WHERE entity_name = 'google_health_daily_respiratory_rate'
              AND request_status = 'SUCCESS'
              AND requested_start_date >= UTC_DATE() - INTERVAL 2 DAY
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
        check_name = "raw_google_health_rhr_hrv_sleep_date_overlap",
        check_scope = "deep",
        severity = "WARNING",
        query = "
          WITH dates AS (
            SELECT activity_date
            FROM cycling_platform_raw.google_health_daily_resting_heart_rate
            UNION
            SELECT activity_date
            FROM cycling_platform_raw.google_health_daily_heart_rate_variability
            UNION
            SELECT start_civil_date AS activity_date
            FROM cycling_platform_raw.google_health_sleep_logs
            WHERE start_civil_date IS NOT NULL
            UNION
            SELECT end_civil_date AS activity_date
            FROM cycling_platform_raw.google_health_sleep_logs
            WHERE end_civil_date IS NOT NULL
          )
          SELECT
            dates.activity_date,
            rhr.activity_date IS NOT NULL AS has_rhr,
            hrv.activity_date IS NOT NULL AS has_hrv,
            sleep_start.activity_date IS NOT NULL AS has_sleep_by_start_date,
            sleep_end.activity_date IS NOT NULL AS has_sleep_by_end_date
          FROM dates
          LEFT JOIN (
            SELECT DISTINCT activity_date
            FROM cycling_platform_raw.google_health_daily_resting_heart_rate
          ) rhr
            ON rhr.activity_date = dates.activity_date
          LEFT JOIN (
            SELECT DISTINCT activity_date
            FROM cycling_platform_raw.google_health_daily_heart_rate_variability
          ) hrv
            ON hrv.activity_date = dates.activity_date
          LEFT JOIN (
            SELECT DISTINCT start_civil_date AS activity_date
            FROM cycling_platform_raw.google_health_sleep_logs
            WHERE start_civil_date IS NOT NULL
          ) sleep_start
            ON sleep_start.activity_date = dates.activity_date
          LEFT JOIN (
            SELECT DISTINCT end_civil_date AS activity_date
            FROM cycling_platform_raw.google_health_sleep_logs
            WHERE end_civil_date IS NOT NULL
          ) sleep_end
            ON sleep_end.activity_date = dates.activity_date
          WHERE rhr.activity_date IS NULL
             OR hrv.activity_date IS NULL
             OR (
               sleep_start.activity_date IS NULL
               AND sleep_end.activity_date IS NULL
             )
          ORDER BY dates.activity_date DESC
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
        check_name = "raw_google_health_sleep_stage_metadata_valid",
        check_scope = "deep",
        severity = "WARNING",
        query = "
          SELECT
            sleep_log_key,
            sleep_type,
            stages_status,
            has_sleep_stages,
            sleep_stage_count,
            has_sleep_summary
          FROM cycling_platform_raw.google_health_sleep_logs
          WHERE (sleep_type = 'STAGES' AND COALESCE(has_sleep_stages, 0) = 0)
             OR (COALESCE(has_sleep_stages, 0) = 1 AND COALESCE(sleep_stage_count, 0) = 0)
             OR (stages_status = 'SUCCEEDED' AND COALESCE(has_sleep_summary, 0) = 0)
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
        check_name = "raw_google_health_daily_entities_recent_failures",
        check_scope = "deep",
        severity = "WARNING",
        query = "
          SELECT
            run_entity_id,
            run_id,
            entity_name,
            entity_status,
            error_message
          FROM cycling_platform_admin.etl_run_entity
          WHERE entity_name IN (
              'google_health_daily_resting_heart_rate',
              'google_health_daily_heart_rate_variability',
              'google_health_daily_respiratory_rate'
            )
            AND entity_status = 'FAILED'
            AND started_at >= UTC_TIMESTAMP() - INTERVAL 14 DAY
          ORDER BY started_at DESC
          LIMIT 1000
        ",
        per_check_timeout_seconds = per_check_timeout_seconds,
        deadline = deadline
      )
    )

    if (isTRUE(include_gold)) {
      gold_publication_results <- gold_activity_best_efforts_publication_checks(
        connection = connection,
        config = config,
        check_scope = "deep",
        per_check_timeout_seconds = per_check_timeout_seconds,
        deadline = deadline
      )

      checks <- append_validation_result(
        checks,
        gold_publication_results
      )

      gold_publication_failed <- platform_validation_has_critical_failures(
        gold_publication_results
      )

      if (gold_publication_failed) {
        message(
          "Skipping downstream Gold completeness checks because required ",
          "Gold publication checks failed."
        )
      }

      if (gold_table_exists && !gold_publication_failed) {
        for (metric_name in gold_metrics) {
          source_sql <- gold_metric_source_sql(metric_name)

          checks <- append_validation_result(
            checks,
            validate_gold_metric_presence(
              connection = connection,
              metric_name = metric_name,
              source_sql = source_sql,
              per_check_timeout_seconds = per_check_timeout_seconds,
              deadline = deadline
            )
          )

          checks <- append_validation_result(
            checks,
            validate_gold_metric_duration_coverage(
              connection = connection,
              metric_name = metric_name,
              source_sql = source_sql,
              durations = gold_durations,
              per_check_timeout_seconds = per_check_timeout_seconds,
              deadline = deadline
            )
          )
        }

        gold_internal_checks <- list(
          run_validation_query(
            connection = connection,
            check_name = "gold_best_efforts_duplicate_primary_key",
            check_scope = "deep",
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
              ORDER BY activity_id, metric_name, duration_seconds
              LIMIT 1000
            ",
            per_check_timeout_seconds = per_check_timeout_seconds,
            deadline = deadline
          ),
          run_validation_query(
            connection = connection,
            check_name = "gold_best_efforts_peak_value_valid",
            check_scope = "deep",
            severity = "CRITICAL",
            query = "
              SELECT
                activity_id,
                metric_name,
                duration_seconds,
                peak_value
              FROM cycling_platform_gold.activity_best_efforts
              WHERE peak_value IS NULL
                 OR peak_value < 0
              ORDER BY activity_id, metric_name, duration_seconds
              LIMIT 1000
            ",
            per_check_timeout_seconds = per_check_timeout_seconds,
            deadline = deadline
          ),
          run_validation_query(
            connection = connection,
            check_name = "gold_best_efforts_window_indexes_valid",
            check_scope = "deep",
            severity = "CRITICAL",
            query = "
              SELECT
                activity_id,
                metric_name,
                duration_seconds,
                start_sample_index,
                end_sample_index
              FROM cycling_platform_gold.activity_best_efforts
              WHERE start_sample_index > end_sample_index
              ORDER BY activity_id, metric_name, duration_seconds
              LIMIT 1000
            ",
            per_check_timeout_seconds = per_check_timeout_seconds,
            deadline = deadline
          ),
          run_validation_query(
            connection = connection,
            check_name = "gold_best_efforts_window_times_valid",
            check_scope = "deep",
            severity = "CRITICAL",
            query = "
              SELECT
                activity_id,
                metric_name,
                duration_seconds,
                start_time_seconds,
                end_time_seconds
              FROM cycling_platform_gold.activity_best_efforts
              WHERE start_time_seconds IS NOT NULL
                AND end_time_seconds IS NOT NULL
                AND start_time_seconds > end_time_seconds
              ORDER BY activity_id, metric_name, duration_seconds
              LIMIT 1000
            ",
            per_check_timeout_seconds = per_check_timeout_seconds,
            deadline = deadline
          ),
          run_validation_query(
            connection = connection,
            check_name = "gold_best_efforts_sample_count_valid",
            check_scope = "deep",
            severity = "CRITICAL",
            query = "
              SELECT
                activity_id,
                metric_name,
                duration_seconds,
                sample_count
              FROM cycling_platform_gold.activity_best_efforts
              WHERE sample_count < duration_seconds
                 OR sample_count <= 0
              ORDER BY activity_id, metric_name, duration_seconds
              LIMIT 1000
            ",
            per_check_timeout_seconds = per_check_timeout_seconds,
            deadline = deadline
          ),
          run_validation_query(
            connection = connection,
            check_name = "gold_best_efforts_gps_provenance_present",
            check_scope = "deep",
            severity = "CRITICAL",
            query = "
              WITH gps_activities AS (
                SELECT activity_id
                FROM cycling_platform_silver.activity_streams
                WHERE latitude IS NOT NULL
                  AND longitude IS NOT NULL
                GROUP BY activity_id
              )
              SELECT
                best_efforts.activity_id,
                best_efforts.metric_name,
                best_efforts.duration_seconds
              FROM cycling_platform_gold.activity_best_efforts best_efforts
              INNER JOIN gps_activities
                ON gps_activities.activity_id = best_efforts.activity_id
              WHERE best_efforts.start_latitude IS NULL
                 OR best_efforts.start_longitude IS NULL
                 OR best_efforts.end_latitude IS NULL
                 OR best_efforts.end_longitude IS NULL
              ORDER BY
                best_efforts.activity_id,
                best_efforts.metric_name,
                best_efforts.duration_seconds
              LIMIT 1000
            ",
            per_check_timeout_seconds = per_check_timeout_seconds,
            deadline = deadline
          )
        )

        checks <- c(
          checks,
          gold_internal_checks
        )
      }
    }
  }

  validation_results <- dplyr::bind_rows(checks)

  log_validation_phase_complete(validation_started_at)

  validation_results
}

get_slowest_platform_validation_checks <- function(
  validation_results,
  n = 5L
) {
  if (!"elapsed_seconds" %in% names(validation_results)) {
    return(data.frame())
  }

  timed_results <- validation_results[
    !is.na(validation_results$elapsed_seconds),
    ,
    drop = FALSE
  ]

  if (nrow(timed_results) == 0) {
    return(data.frame())
  }

  timed_results <- timed_results[
    order(
      timed_results$elapsed_seconds,
      decreasing = TRUE
    ),
    ,
    drop = FALSE
  ]

  utils::head(
    timed_results[
      intersect(
        c(
          "check_name",
          "check_scope",
          "severity",
          "passed",
          "issue_count",
          "elapsed_seconds"
        ),
        names(timed_results)
      )
    ],
    n
  )
}

validation_summary_columns <- function(validation_results) {
  intersect(
    c(
      "check_name",
      "check_scope",
      "severity",
      "passed",
      "issue_count",
      "elapsed_seconds"
    ),
    names(validation_results)
  )
}

print_slowest_platform_validation_checks <- function(
  validation_results,
  n = 5L
) {
  slowest <- get_slowest_platform_validation_checks(
    validation_results = validation_results,
    n = n
  )

  if (nrow(slowest) == 0) {
    return(invisible(validation_results))
  }

  message("Slowest validation checks:")
  print(slowest)

  invisible(validation_results)
}

#' Print Platform Completeness Validation
#'
#' @param validation_results Result returned by validate_platform_completeness().
#'
#' @return Invisibly returns validation_results.
print_platform_completeness_validation <- function(validation_results) {
  summary <- validation_results[
    validation_summary_columns(validation_results)
  ]

  print(summary)

  print_slowest_platform_validation_checks(validation_results)

  failed <- validation_results[
    !validation_results$passed,
    ,
    drop = FALSE
  ]

  if (nrow(failed) > 0) {
    message("Validation failures:")

    for (i in seq_len(nrow(failed))) {
      message(glue::glue(
        "- {failed$severity[[i]]} {failed$check_name[[i]]}: ",
        "{failed$issue_count[[i]]} issue(s)"
      ))

      print(utils::head(failed$details[[i]], 20))
    }
  }

  invisible(validation_results)
}
