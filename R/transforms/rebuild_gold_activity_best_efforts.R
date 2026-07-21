#' Default Best Effort Durations
#'
#' @return Integer vector of durations in seconds.
default_best_effort_durations <- function() {
  c(
    5L,
    10L,
    20L,
    60L,
    120L,
    300L,
    600L,
    1200L,
    1800L,
    3600L
  )
}

#' Gold Activity Best Efforts Calculation Version
#'
#' @param config Platform configuration.
#'
#' @return Character calculation version.
gold_activity_best_efforts_calculation_version <- function(config = list()) {
  calculation_version <- config$transforms$gold_best_effort_calculation_version

  if (is.null(calculation_version) || !nzchar(calculation_version)) {
    return("activity_best_efforts_v1")
  }

  as.character(calculation_version)
}

#' Best Effort Metric Columns
#'
#' @return Named character vector mapping metric_name to silver stream column.
best_effort_metric_columns <- function() {
  c(
    watts = "watts",
    cadence_rpm = "cadence_rpm",
    heartrate_bpm = "heartrate_bpm"
  )
}

#' Compute Rolling Best Effort
#'
#' Compute the best contiguous rolling mean for one metric and duration.
#'
#' @param activity_streams Activity stream samples for one activity.
#' @param metric_column Column containing metric values.
#' @param metric_name Metric label written to Gold.
#' @param duration_seconds Rolling window duration in seconds.
#'
#' @return One-row data frame, or NULL when no valid window exists.
compute_activity_best_effort <- function(
  activity_streams,
  metric_column,
  metric_name,
  duration_seconds,
  calculation_version = "activity_best_efforts_v1"
) {
  if (!metric_column %in% names(activity_streams)) {
    return(NULL)
  }

  activity_streams <- activity_streams[
    order(activity_streams$sample_index),
    ,
    drop = FALSE
  ]

  metric_values <- activity_streams[[metric_column]]
  valid_metric <- !is.na(metric_values)
  duration_seconds <- as.integer(duration_seconds)

  if (length(metric_values) < duration_seconds) {
    return(NULL)
  }

  metric_sum <- cumsum(
    c(
      0,
      ifelse(
        valid_metric,
        metric_values,
        0
      )
    )
  )

  valid_count <- cumsum(
    c(
      0L,
      as.integer(valid_metric)
    )
  )

  window_starts <- seq_len(
    length(metric_values) - duration_seconds + 1L
  )

  window_ends <- window_starts + duration_seconds - 1L

  window_counts <- valid_count[window_ends + 1L] -
    valid_count[window_starts]

  valid_windows <- window_counts == duration_seconds

  if (!any(valid_windows)) {
    return(NULL)
  }

  window_sums <- metric_sum[window_ends + 1L] -
    metric_sum[window_starts]

  window_means <- window_sums / duration_seconds
  window_means[!valid_windows] <- NA_real_

  best_window <- which.max(window_means)
  peak_value <- window_means[[best_window]]

  if (is.na(peak_value)) {
    return(NULL)
  }

  start_row <- activity_streams[window_starts[[best_window]], , drop = FALSE]
  end_row <- activity_streams[window_ends[[best_window]], , drop = FALSE]

  data.frame(
    activity_id = start_row$activity_id[[1]],
    metric_name = metric_name,
    duration_seconds = duration_seconds,
    peak_value = as.numeric(peak_value),
    start_sample_index = start_row$sample_index[[1]],
    end_sample_index = end_row$sample_index[[1]],
    start_time_seconds = start_row$time_seconds[[1]],
    end_time_seconds = end_row$time_seconds[[1]],
    start_distance_metres = start_row$distance_metres[[1]],
    end_distance_metres = end_row$distance_metres[[1]],
    start_latitude = start_row$latitude[[1]],
    start_longitude = start_row$longitude[[1]],
    end_latitude = end_row$latitude[[1]],
    end_longitude = end_row$longitude[[1]],
    sample_count = duration_seconds,
    calculation_version = calculation_version,
    computed_at = as.POSIXct(
      Sys.time(),
      tz = "UTC"
    )
  )
}

#' Compute Activity Best Efforts
#'
#' @param activity_streams Activity stream samples for one activity.
#' @param metrics Character vector of metrics.
#' @param durations Integer vector of durations in seconds.
#'
#' @return Data frame of best efforts.
compute_activity_best_efforts <- function(
  activity_streams,
  metrics = "watts",
  durations = default_best_effort_durations(),
  calculation_version = "activity_best_efforts_v1"
) {
  metric_columns <- best_effort_metric_columns()

  unknown_metrics <- setdiff(
    metrics,
    names(metric_columns)
  )

  if (length(unknown_metrics) > 0) {
    stop(
      "Unsupported best effort metric(s): ",
      paste(
        unknown_metrics,
        collapse = ", "
      ),
      call. = FALSE
    )
  }

  results <- list()

  for (metric_name in metrics) {
    for (duration_seconds in durations) {
      result <- compute_activity_best_effort(
        activity_streams = activity_streams,
        metric_column = metric_columns[[metric_name]],
        metric_name = metric_name,
        duration_seconds = duration_seconds,
        calculation_version = calculation_version
      )

      if (!is.null(result)) {
        results[[length(results) + 1L]] <- result
      }
    }
  }

  if (length(results) == 0) {
    return(data.frame())
  }

  do.call(rbind, results)
}

best_effort_placeholders <- function(values) {
  paste(
    rep(
      "?",
      length(values)
    ),
    collapse = ", "
  )
}

db_get_query_optional_params <- function(
  connection,
  statement,
  params = list()
) {
  if (length(params) == 0) {
    return(
      DBI::dbGetQuery(
        conn = connection,
        statement = statement
      )
    )
  }

  DBI::dbGetQuery(
    conn = connection,
    statement = statement,
    params = params
  )
}

get_latest_successful_transform_completed_at <- function(
  connection,
  layer_name,
  entity_name
) {
  result <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT MAX(completed_at) AS completed_at
      FROM cycling_platform_admin.transform_run
      WHERE layer_name = ?
        AND entity_name = ?
        AND run_status = 'SUCCESS'
    ",
    params = list(
      layer_name,
      entity_name
    )
  )

  result$completed_at[[1]]
}

gold_activity_best_efforts_daily_can_skip <- function(connection) {
  latest_gold_completed_at <- get_latest_successful_transform_completed_at(
    connection = connection,
    layer_name = "gold",
    entity_name = "activity_best_efforts"
  )

  if (is.na(latest_gold_completed_at)) {
    return(FALSE)
  }

  latest_silver_stream_completed_at <-
    get_latest_successful_transform_completed_at(
      connection = connection,
      layer_name = "silver",
      entity_name = "activity_streams"
    )

  if (is.na(latest_silver_stream_completed_at)) {
    return(FALSE)
  }

  latest_silver_activity_completed_at <-
    get_latest_successful_transform_completed_at(
      connection = connection,
      layer_name = "silver",
      entity_name = "activities"
    )

  if (is.na(latest_silver_activity_completed_at)) {
    return(FALSE)
  }

  latest_gold_completed_at >= max(
    latest_silver_stream_completed_at,
    latest_silver_activity_completed_at
  )
}

get_best_effort_activity_plan <- function(
  connection,
  mode,
  activity_ids,
  metrics,
  durations,
  calculation_version
) {
  metric_columns <- best_effort_metric_columns()[metrics]

  metric_source_sql <- paste(
    paste0(
      "
      SELECT
        streams.activity_id,
        '",
      names(metric_columns),
      "' AS metric_name,
        COUNT(streams.",
      metric_columns,
      ") AS metric_sample_count,
        GREATEST(
          MAX(streams.transformed_at),
          MAX(activities.transformed_at)
        ) AS latest_silver_transformed_at
      FROM cycling_platform_silver.activity_streams streams
      INNER JOIN cycling_platform_silver.activities activities
        ON activities.activity_id = streams.activity_id
      GROUP BY streams.activity_id
      HAVING COUNT(streams.",
      metric_columns,
      ") > 0
      "
    ),
    collapse = "\nUNION ALL\n"
  )

  activity_filter_sql <- ""
  activity_filter_params <- list()

  if (!is.null(activity_ids)) {
    activity_filter_sql <- paste0(
      " AND streams.activity_id IN (",
      best_effort_placeholders(activity_ids),
      ")"
    )

    activity_filter_params <- as.list(as.character(activity_ids))
  }

  if (identical(mode, "backfill")) {
    sql <- paste0(
      "
      WITH metric_source AS (
      ",
      metric_source_sql,
      "
      ),
      durations AS (
      ",
      gold_best_effort_duration_table_sql(durations),
      "
      ),
      expected AS (
        SELECT
          metric_source.activity_id,
          metric_source.metric_name,
          durations.duration_seconds
        FROM metric_source
        INNER JOIN durations
          ON durations.duration_seconds <= metric_source.metric_sample_count
      )
      SELECT
        metric_source.activity_id,
        MAX(metric_source.metric_sample_count) AS stream_row_count,
        COUNT(expected.duration_seconds) AS expected_best_effort_count,
        'backfill' AS repair_reason
      FROM metric_source
      INNER JOIN expected
        ON expected.activity_id = metric_source.activity_id
       AND expected.metric_name = metric_source.metric_name
      WHERE 1 = 1",
      activity_filter_sql,
      "
      GROUP BY metric_source.activity_id
      ORDER BY metric_source.activity_id
      "
    )

    return(
      db_get_query_optional_params(
        connection = connection,
        statement = sql,
        params = activity_filter_params
      )
    )
  }

  sql <- paste0(
    "
    WITH metric_source AS (
    ",
    metric_source_sql,
    "
    ),
    durations AS (
    ",
    gold_best_effort_duration_table_sql(durations),
    "
    ),
    expected AS (
      SELECT
        metric_source.activity_id,
        metric_source.metric_name,
        durations.duration_seconds,
        metric_source.latest_silver_transformed_at
      FROM metric_source
      INNER JOIN durations
        ON durations.duration_seconds <= metric_source.metric_sample_count
    ),
    source_summary AS (
      SELECT
        expected.activity_id,
        COUNT(*) AS expected_best_effort_count,
        MAX(expected.latest_silver_transformed_at) AS latest_silver_transformed_at
      FROM expected
      GROUP BY expected.activity_id
    ),
    gold_summary AS (
      SELECT
        activity_id,
        COUNT(*) AS best_effort_row_count,
        SUM(CASE
          WHEN calculation_version IS NULL
            OR calculation_version <> ?
          THEN 1
          ELSE 0
        END) AS stale_version_row_count,
        MAX(computed_at) AS latest_gold_computed_at
      FROM cycling_platform_gold.activity_best_efforts
      WHERE metric_name IN (",
    best_effort_placeholders(metrics),
    ")
        AND duration_seconds IN (",
    best_effort_placeholders(durations),
    ")
      GROUP BY activity_id
    )
    SELECT
      source_summary.activity_id,
      source_summary.expected_best_effort_count AS stream_row_count,
      source_summary.expected_best_effort_count,
      COALESCE(gold_summary.best_effort_row_count, 0) AS best_effort_row_count,
      CASE
        WHEN COALESCE(gold_summary.best_effort_row_count, 0) = 0 THEN 'missing'
        WHEN COALESCE(gold_summary.best_effort_row_count, 0)
          < source_summary.expected_best_effort_count THEN 'incomplete'
        WHEN COALESCE(gold_summary.stale_version_row_count, 0) > 0 THEN 'stale_version'
        WHEN gold_summary.latest_gold_computed_at
          < source_summary.latest_silver_transformed_at THEN 'updated_silver'
        ELSE 'current'
      END AS repair_reason
    FROM source_summary
    LEFT JOIN gold_summary
      ON gold_summary.activity_id = source_summary.activity_id
    WHERE 1 = 1",
    activity_filter_sql,
    "
      AND (
        COALESCE(gold_summary.best_effort_row_count, 0)
          < source_summary.expected_best_effort_count
        OR COALESCE(gold_summary.stale_version_row_count, 0) > 0
        OR gold_summary.latest_gold_computed_at
          < source_summary.latest_silver_transformed_at
      )
    GROUP BY
      source_summary.activity_id,
      source_summary.expected_best_effort_count,
      gold_summary.best_effort_row_count,
      gold_summary.stale_version_row_count,
      gold_summary.latest_gold_computed_at,
      source_summary.latest_silver_transformed_at
    ORDER BY source_summary.activity_id
    "
  )

  params <- c(
    list(calculation_version),
    as.list(metrics),
    as.list(as.integer(durations)),
    activity_filter_params
  )

  activity_plan <- db_get_query_optional_params(
    connection = connection,
    statement = sql,
    params = params
  )

  activity_plan
}

fetch_activity_streams_for_best_efforts <- function(
  connection,
  activity_ids,
  metrics
) {
  activity_ids <- as.character(activity_ids)
  metric_columns <- unique(
    unname(
      best_effort_metric_columns()[metrics]
    )
  )

  metric_column_sql <- paste(
    paste0(
      "        ",
      metric_columns
    ),
    collapse = ",\n"
  )

  DBI::dbGetQuery(
    conn = connection,
    statement = paste0(
      "
      SELECT
        activity_id,
        sample_index,
        time_seconds,
        distance_metres,
        latitude,
        longitude,
",
      metric_column_sql,
      "
      FROM cycling_platform_silver.activity_streams
      WHERE activity_id IN (",
      best_effort_placeholders(activity_ids),
      ")
      ORDER BY
        activity_id,
        sample_index
      "
    ),
    params = as.list(activity_ids)
  )
}

fetch_activity_power_classification <- function(
  connection,
  activity_ids
) {
  activity_ids <- as.character(activity_ids)

  DBI::dbGetQuery(
    conn = connection,
    statement = paste0(
      "
      SELECT
        activity_id,
        power_source_type,
        is_power_record_eligible,
        power_record_exclusion_reason,
        power_classification_version
      FROM cycling_platform_silver.activities
      WHERE activity_id IN (",
      best_effort_placeholders(activity_ids),
      ")
      "
    ),
    params = as.list(activity_ids)
  )
}

apply_best_effort_record_eligibility <- function(
  best_efforts,
  power_classification
) {
  if (nrow(best_efforts) == 0) {
    return(best_efforts)
  }

  power_classification$activity_id_chr <- as.character(
    power_classification$activity_id
  )

  best_efforts$activity_id_chr <- as.character(
    best_efforts$activity_id
  )

  best_efforts <- merge(
    best_efforts,
    power_classification[
      ,
      c(
        "activity_id_chr",
        "power_source_type",
        "is_power_record_eligible",
        "power_record_exclusion_reason",
        "power_classification_version"
      ),
      drop = FALSE
    ],
    by = "activity_id_chr",
    all.x = TRUE,
    sort = FALSE
  )

  is_watts <- best_efforts$metric_name == "watts"

  best_efforts$is_record_eligible <- ifelse(
    is_watts,
    as.integer(
      !is.na(best_efforts$is_power_record_eligible) &
        best_efforts$is_power_record_eligible == 1
    ),
    1L
  )

  best_efforts$record_exclusion_reason <- ifelse(
    is_watts & best_efforts$is_record_eligible == 0,
    best_efforts$power_record_exclusion_reason,
    NA_character_
  )

  best_efforts$source_classification <- ifelse(
    is_watts,
    best_efforts$power_source_type,
    NA_character_
  )

  best_efforts$power_classification_version <- ifelse(
    is_watts,
    best_efforts$power_classification_version,
    NA_character_
  )

  best_efforts[
    ,
    setdiff(
      names(best_efforts),
      c(
        "activity_id_chr",
        "power_source_type",
        "is_power_record_eligible",
        "power_record_exclusion_reason"
      )
    ),
    drop = FALSE
  ]
}

delete_gold_activity_best_efforts <- function(
  connection,
  activity_ids,
  metrics,
  durations
) {
  activity_ids <- as.character(activity_ids)

  DBI::dbExecute(
    conn = connection,
    statement = paste0(
      "
      DELETE FROM cycling_platform_gold.activity_best_efforts
      WHERE activity_id IN (",
      best_effort_placeholders(activity_ids),
      ")
        AND metric_name IN (",
      best_effort_placeholders(metrics),
      ")
        AND duration_seconds IN (",
      best_effort_placeholders(durations),
      ")
      "
    ),
    params = c(
      as.list(activity_ids),
      as.list(metrics),
      as.list(as.integer(durations))
    )
  )
}

insert_gold_activity_best_efforts <- function(
  connection,
  best_efforts
) {
  if (nrow(best_efforts) == 0) {
    return(0L)
  }

  DBI::dbAppendTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_gold",
      table = "activity_best_efforts"
    ),
    value = best_efforts
  )
}

validate_gold_activity_best_efforts <- function(
  connection,
  calculation_version = "activity_best_efforts_v1"
) {
  checks <- list(
    list(
      check_name = "gold_best_efforts_primary_key_unique",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM (
          SELECT
            activity_id,
            metric_name,
            duration_seconds
          FROM cycling_platform_gold.activity_best_efforts
          GROUP BY
            activity_id,
            metric_name,
            duration_seconds
          HAVING COUNT(*) > 1
        ) duplicate_keys
      "
    ),
    list(
      check_name = "gold_best_efforts_sample_count_valid",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_best_efforts
        WHERE sample_count < duration_seconds
      "
    ),
    list(
      check_name = "gold_best_efforts_watts_peak_valid",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_best_efforts
        WHERE metric_name = 'watts'
          AND (peak_value IS NULL OR peak_value < 0)
      "
    ),
    list(
      check_name = "gold_best_efforts_window_order_valid",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_best_efforts
        WHERE start_sample_index > end_sample_index
           OR (
             start_time_seconds IS NOT NULL
             AND end_time_seconds IS NOT NULL
             AND start_time_seconds > end_time_seconds
           )
      "
    ),
    list(
      check_name = "gold_best_efforts_calculation_version_current",
      sql = paste0(
        "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_best_efforts
        WHERE calculation_version IS NULL
           OR calculation_version = ''
           OR calculation_version <> ",
        DBI::dbQuoteString(
          connection,
          calculation_version
        ),
        "
      "
      )
    ),
    list(
      check_name = "gold_best_efforts_watts_eligibility_matches_silver",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_best_efforts best_efforts
        INNER JOIN cycling_platform_silver.activities activities
          ON activities.activity_id = best_efforts.activity_id
        WHERE best_efforts.metric_name = 'watts'
          AND best_efforts.is_record_eligible
            <> activities.is_power_record_eligible
      "
    ),
    list(
      check_name = "gold_best_efforts_non_watts_not_excluded",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_best_efforts
        WHERE metric_name <> 'watts'
          AND (
            is_record_eligible <> 1
            OR record_exclusion_reason IS NOT NULL
          )
      "
    ),
    list(
      check_name = "gold_best_efforts_exclusions_have_reason",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_gold.activity_best_efforts
        WHERE is_record_eligible = 0
          AND (
            record_exclusion_reason IS NULL
            OR record_exclusion_reason = ''
          )
      "
    )
  )

  results <- lapply(
    checks,
    \(check) {
      failure_count <- DBI::dbGetQuery(
        conn = connection,
        statement = check$sql
      )$failure_count[[1]]

      data.frame(
        check_name = check$check_name,
        failure_count = as.integer(failure_count),
        check_status = if (failure_count == 0) "PASS" else "FAIL"
      )
    }
  )

  validation_results <- do.call(rbind, results)

  failed_checks <- validation_results[
    validation_results$check_status == "FAIL",
    ,
    drop = FALSE
  ]

  if (nrow(failed_checks) > 0) {
    stop(
      "Gold activity best efforts validation failed: ",
      paste(
        paste0(
          failed_checks$check_name,
          "=",
          failed_checks$failure_count
        ),
        collapse = "; "
      ),
      call. = FALSE
    )
  }

  validation_results
}

#' Rebuild Gold Activity Best Efforts
#'
#' @param connection Database connection.
#' @param config Platform configuration.
#' @param activity_ids Optional activity IDs to process.
#' @param metrics Metrics to calculate.
#' @param durations Durations in seconds.
#' @param batch_size Number of activities per batch.
#' @param max_activities Optional maximum number of activities to process.
#' @param mode `daily`/`repair` for stale or missing rows, or `backfill` for
#'   requested activities.
#' @param sql_dir Directory containing Gold SQL scripts.
#'
#' @return Invisibly returns validation results.
rebuild_gold_activity_best_efforts <- function(
  connection,
  config = list(),
  activity_ids = NULL,
  metrics = NULL,
  durations = NULL,
  batch_size = NULL,
  max_activities = NULL,
  mode = c(
    "daily",
    "repair",
    "backfill"
  ),
  sql_dir = file.path("sql", "gold")
) {
  mode <- match.arg(mode)

  if (is.null(metrics)) {
    metrics <- config$transforms$gold_best_effort_metrics
  }

  if (is.null(metrics)) {
    metrics <- "watts"
  }

  metrics <- as.character(
    unlist(
      metrics,
      use.names = FALSE
    )
  )

  if (is.null(durations)) {
    durations <- config$transforms$gold_best_effort_durations
  }

  if (is.null(durations)) {
    durations <- default_best_effort_durations()
  }

  if (is.null(batch_size)) {
    batch_size <- config$transforms$gold_best_effort_activity_batch_size
  }

  if (is.null(batch_size)) {
    batch_size <- 25L
  }

  durations <- as.integer(
    unlist(
      durations,
      use.names = FALSE
    )
  )
  batch_size <- as.integer(
    unlist(
      batch_size,
      use.names = FALSE
    )[[1]]
  )

  stopifnot(batch_size > 0)
  stopifnot(all(durations > 0))

  calculation_version <- gold_activity_best_efforts_calculation_version(
    config = config
  )

  message(glue::glue(
    "Gold object: activity_best_efforts; mode: {mode}; ",
    "calculation version: {calculation_version}."
  ))

  ensure_power_source_classification_schema(connection)

  execute_sql_file(
    sql_file = file.path(
      sql_dir,
      "010_create_activity_best_efforts.sql"
    ),
    connection = connection
  )

  ensure_transform_logging_tables(
    connection = connection
  )

  if (
    identical(mode, "daily") &&
      is.null(activity_ids) &&
      is.null(max_activities) &&
      gold_activity_best_efforts_daily_can_skip(connection)
  ) {
    message(
      "Skipping gold activity_best_efforts candidate scan: latest Gold ",
      "transform is current with latest successful Silver stream transform."
    )

    transform_run_id <- create_transform_run(
      connection = connection,
      layer_name = "gold",
      entity_name = "activity_best_efforts",
      run_mode = mode,
      total_batches = 0L,
      activities_planned = 0L,
      expected_rows_planned = 0L,
      max_batch_activities = batch_size,
      max_batch_expected_rows = batch_size * length(metrics) * length(durations)
    )

    update_transform_run(
      connection = connection,
      transform_run_id = transform_run_id,
      run_status = "SUCCESS",
      completed_batches = 0L,
      activities_completed = 0L,
      rows_inserted = 0L,
      rows_deleted = 0L
    )

    return(
      invisible(data.frame())
    )
  }

  activity_plan <- get_best_effort_activity_plan(
    connection = connection,
    mode = mode,
    activity_ids = activity_ids,
    metrics = metrics,
    durations = durations,
    calculation_version = calculation_version
  )

  if (!is.null(max_activities)) {
    activity_plan <- head(
      activity_plan,
      as.integer(max_activities)
    )
  }

  candidate_activity_count <- nrow(activity_plan)

  message(glue::glue(
    "Gold activity_best_efforts candidates: {candidate_activity_count} activities."
  ))

  activity_batches <- if (nrow(activity_plan) == 0) {
    list()
  } else {
    split(
      activity_plan$activity_id,
      ceiling(
        seq_len(nrow(activity_plan)) / batch_size
      )
    )
  }

  transform_run_id <- create_transform_run(
    connection = connection,
    layer_name = "gold",
    entity_name = "activity_best_efforts",
    run_mode = mode,
    total_batches = length(activity_batches),
    activities_planned = nrow(activity_plan),
    expected_rows_planned = nrow(activity_plan) * length(metrics) * length(durations),
    max_batch_activities = batch_size,
    max_batch_expected_rows = batch_size * length(metrics) * length(durations)
  )

  completed_batches <- 0L
  activities_completed <- 0L
  total_rows_deleted <- 0L
  total_rows_inserted <- 0L

  if (nrow(activity_plan) == 0) {
    message("No gold activity best efforts require processing.")

    validation_results <- validate_gold_activity_best_efforts(
      connection = connection,
      calculation_version = calculation_version
    )

    update_transform_run(
      connection = connection,
      transform_run_id = transform_run_id,
      run_status = "SUCCESS",
      completed_batches = completed_batches,
      activities_completed = activities_completed,
      rows_inserted = total_rows_inserted,
      rows_deleted = total_rows_deleted
    )

    return(
      invisible(validation_results)
    )
  }

  run_error <- tryCatch(
    {
      purrr::iwalk(
        activity_batches,
        \(activity_ids_batch, batch_index) {
          activity_ids_batch <- as.character(activity_ids_batch)

          message(glue::glue(
            "Processing gold best effort batch {batch_index}/",
            "{length(activity_batches)} ({length(activity_ids_batch)} activities)."
          ))

          transform_run_batch_id <- create_transform_run_batch(
            connection = connection,
            transform_run_id = transform_run_id,
            batch_number = batch_index,
            activity_ids = activity_ids_batch,
            expected_rows = length(activity_ids_batch) * length(metrics) * length(durations)
          )

          rows_deleted <- 0L
          rows_inserted <- 0L

          batch_error <- tryCatch(
            {
              streams <- fetch_activity_streams_for_best_efforts(
                connection = connection,
                activity_ids = activity_ids_batch,
                metrics = metrics
              )

              power_classification <- fetch_activity_power_classification(
                connection = connection,
                activity_ids = activity_ids_batch
              )

              best_efforts <- purrr::map_dfr(
                split(
                  streams,
                  streams$activity_id
                ),
                \(activity_streams) {
                  compute_activity_best_efforts(
                    activity_streams = activity_streams,
                    metrics = metrics,
                    durations = durations,
                    calculation_version = calculation_version
                  )
                }
              )

              best_efforts <- apply_best_effort_record_eligibility(
                best_efforts = best_efforts,
                power_classification = power_classification
              )

              DBI::dbBegin(connection)

              tryCatch(
                {
                  rows_deleted <- delete_gold_activity_best_efforts(
                    connection = connection,
                    activity_ids = activity_ids_batch,
                    metrics = metrics,
                    durations = durations
                  )

                  rows_inserted <- insert_gold_activity_best_efforts(
                    connection = connection,
                    best_efforts = best_efforts
                  )

                  DBI::dbCommit(connection)
                },
                error = function(e) {
                  tryCatch(
                    DBI::dbRollback(connection),
                    error = function(rollback_error) {
                      message(glue::glue(
                        "Gold best effort batch rollback failed: ",
                        "{conditionMessage(rollback_error)}"
                      ))
                    }
                  )

                  stop(e)
                }
              )

              NULL
            },
            error = function(e) {
              e
            }
          )

          if (!is.null(batch_error)) {
            update_transform_run_batch(
              connection = connection,
              transform_run_batch_id = transform_run_batch_id,
              batch_status = "FAILED",
              rows_inserted = rows_inserted,
              rows_deleted = rows_deleted,
              error_message = conditionMessage(batch_error)
            )

            stop(batch_error)
          }

          completed_batches <<- completed_batches + 1L
          activities_completed <<- activities_completed + length(activity_ids_batch)
          total_rows_deleted <<- total_rows_deleted + rows_deleted
          total_rows_inserted <<- total_rows_inserted + rows_inserted

          update_transform_run_batch(
            connection = connection,
            transform_run_batch_id = transform_run_batch_id,
            batch_status = "SUCCESS",
            rows_inserted = rows_inserted,
            rows_deleted = rows_deleted
          )

          update_transform_run(
            connection = connection,
            transform_run_id = transform_run_id,
            run_status = "RUNNING",
            completed_batches = completed_batches,
            activities_completed = activities_completed,
            rows_inserted = total_rows_inserted,
            rows_deleted = total_rows_deleted
          )

          message(glue::glue(
            "Completed gold best effort batch {batch_index}/",
            "{length(activity_batches)}: {rows_deleted} rows deleted, ",
            "{rows_inserted} rows inserted, ",
            "{length(activity_ids_batch)} activities processed."
          ))
        }
      )

      NULL
    },
    error = function(e) {
      e
    }
  )

  if (!is.null(run_error)) {
    update_transform_run(
      connection = connection,
      transform_run_id = transform_run_id,
      run_status = "FAILED",
      completed_batches = completed_batches,
      activities_completed = activities_completed,
      rows_inserted = total_rows_inserted,
      rows_deleted = total_rows_deleted,
      error_message = conditionMessage(run_error)
    )

    stop(run_error)
  }

  validation_results <- validate_gold_activity_best_efforts(
    connection = connection,
    calculation_version = calculation_version
  )

  update_transform_run(
    connection = connection,
    transform_run_id = transform_run_id,
    run_status = "SUCCESS",
    completed_batches = completed_batches,
    activities_completed = activities_completed,
    rows_inserted = total_rows_inserted,
    rows_deleted = total_rows_deleted
  )

  message(glue::glue(
    "Gold activity best efforts rebuild complete: ",
    "{activities_completed} activities processed, ",
    "{total_rows_inserted} rows inserted, ",
    "{total_rows_deleted} rows deleted, ",
    "{candidate_activity_count - activities_completed} activities skipped, ",
    "calculation version {calculation_version}."
  ))

  invisible(validation_results)
}
