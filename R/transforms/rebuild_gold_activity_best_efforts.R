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
  duration_seconds
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
  durations = default_best_effort_durations()
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
        duration_seconds = duration_seconds
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

get_best_effort_activity_plan <- function(
  connection,
  mode,
  activity_ids,
  metrics,
  durations
) {
  metric_columns <- best_effort_metric_columns()[metrics]
  metric_presence_sql <- paste(
    paste0(
      "streams.",
      metric_columns,
      " IS NOT NULL"
    ),
    collapse = " OR "
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
      SELECT
        streams.activity_id,
        COUNT(*) AS stream_row_count
      FROM cycling_platform_silver.activity_streams streams
      WHERE ",
      metric_presence_sql,
      activity_filter_sql,
      "
      GROUP BY streams.activity_id
      ORDER BY streams.activity_id
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
    SELECT
      streams.activity_id,
      COUNT(*) AS stream_row_count,
      COALESCE(existing.best_effort_row_count, 0) AS best_effort_row_count
    FROM cycling_platform_silver.activity_streams streams
    LEFT JOIN (
      SELECT
        activity_id,
        COUNT(*) AS best_effort_row_count
      FROM cycling_platform_gold.activity_best_efforts
      WHERE metric_name IN (",
    best_effort_placeholders(metrics),
    ")
        AND duration_seconds IN (",
    best_effort_placeholders(durations),
    ")
      GROUP BY activity_id
    ) existing
      ON existing.activity_id = streams.activity_id
    WHERE ",
    metric_presence_sql,
    activity_filter_sql,
    "
    GROUP BY
      streams.activity_id,
      existing.best_effort_row_count
    ORDER BY streams.activity_id
    "
  )

  params <- c(
    as.list(metrics),
    as.list(as.integer(durations)),
    activity_filter_params
  )

  activity_plan <- db_get_query_optional_params(
    connection = connection,
    statement = sql,
    params = params
  )

  if (nrow(activity_plan) == 0) {
    return(activity_plan)
  }

  activity_plan$expected_best_effort_count <- vapply(
    activity_plan$stream_row_count,
    \(stream_row_count) {
      length(metrics) * sum(as.integer(durations) <= as.integer(stream_row_count))
    },
    integer(1)
  )

  activity_plan[
    activity_plan$best_effort_row_count <
      activity_plan$expected_best_effort_count,
    c(
      "activity_id",
      "stream_row_count"
    ),
    drop = FALSE
  ]
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

validate_gold_activity_best_efforts <- function(connection) {
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
#' @param mode `repair` for missing rows or `backfill` for requested activities.
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

  execute_sql_file(
    sql_file = file.path(
      sql_dir,
      "010_create_activity_best_efforts.sql"
    ),
    connection = connection
  )

  activity_plan <- get_best_effort_activity_plan(
    connection = connection,
    mode = mode,
    activity_ids = activity_ids,
    metrics = metrics,
    durations = durations
  )

  if (!is.null(max_activities)) {
    activity_plan <- head(
      activity_plan,
      as.integer(max_activities)
    )
  }

  if (nrow(activity_plan) == 0) {
    message("No gold activity best efforts require processing.")

    return(
      invisible(
        validate_gold_activity_best_efforts(
          connection = connection
        )
      )
    )
  }

  activity_batches <- split(
    activity_plan$activity_id,
    ceiling(
      seq_len(nrow(activity_plan)) / batch_size
    )
  )

  ensure_transform_logging_tables(
    connection = connection
  )

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

              best_efforts <- purrr::map_dfr(
                split(
                  streams,
                  streams$activity_id
                ),
                \(activity_streams) {
                  compute_activity_best_efforts(
                    activity_streams = activity_streams,
                    metrics = metrics,
                    durations = durations
                  )
                }
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
            "{rows_inserted} rows inserted."
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
    connection = connection
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
    "{total_rows_inserted} rows inserted."
  ))

  invisible(validation_results)
}
