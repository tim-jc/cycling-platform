#' Get Silver Stream Activity Plan
#'
#' Return activity IDs with raw stream data and expected silver row counts.
#'
#' @param connection Database connection.
#'
#' @return Data frame with activity_id and expected_row_count.
get_silver_stream_activity_plan <- function(connection) {
  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT
          activity_id,
          MAX(original_size) AS expected_row_count
      FROM cycling_platform_raw.activity_streams
      GROUP BY activity_id
      ORDER BY activity_id
    "
  )
}

#' Get Silver Stream Repair Activity Plan
#'
#' Return activities where silver stream rows are missing or incomplete.
#'
#' @param connection Database connection.
#'
#' @return Data frame with activity_id and expected_row_count.
get_silver_stream_repair_activity_plan <- function(connection) {
  DBI::dbGetQuery(
    conn = connection,
    statement = "
      WITH raw_summary AS (
          SELECT
              activity_id,
              MAX(original_size) AS expected_row_count
          FROM cycling_platform_raw.activity_streams
          GROUP BY activity_id
      ),
      silver_summary AS (
          SELECT
              activity_id,
              COUNT(*) AS actual_row_count
          FROM cycling_platform_silver.activity_streams
          GROUP BY activity_id
      )
      SELECT
          raw_summary.activity_id,
          raw_summary.expected_row_count
      FROM raw_summary
      LEFT JOIN silver_summary
          ON silver_summary.activity_id = raw_summary.activity_id
      WHERE COALESCE(silver_summary.actual_row_count, 0)
          <> raw_summary.expected_row_count
      ORDER BY raw_summary.activity_id
    "
  )
}

#' Build Silver Stream Activity Batches
#'
#' Pack activities into batches using both activity count and expected row count.
#'
#' @param activity_plan Data frame with activity_id and expected_row_count.
#' @param max_activities Maximum activities per batch.
#' @param max_expected_rows Maximum expected rows per batch.
#'
#' @return List of activity plan data frames.
build_silver_stream_activity_batches <- function(
  activity_plan,
  max_activities,
  max_expected_rows
) {
  stopifnot(max_activities > 0)
  stopifnot(max_expected_rows > 0)

  if (nrow(activity_plan) == 0) {
    return(list())
  }

  if (!"expected_row_count" %in% names(activity_plan)) {
    stop(
      "Activity plan must include expected_row_count.",
      call. = FALSE
    )
  }

  activity_plan$expected_row_count <- as.numeric(
    as.character(activity_plan$expected_row_count)
  )

  if (any(is.na(activity_plan$expected_row_count))) {
    stop(
      "Activity plan contains missing expected row counts.",
      call. = FALSE
    )
  }

  batches <- list()
  current_batch <- activity_plan[0, , drop = FALSE]
  current_expected_rows <- 0L

  for (row_index in seq_len(nrow(activity_plan))) {
    activity_row <- activity_plan[row_index, , drop = FALSE]
    activity_expected_rows <- activity_row$expected_row_count[[1]]

    would_exceed_activity_limit <- nrow(current_batch) >= max_activities
    would_exceed_row_limit <- nrow(current_batch) > 0 &&
      current_expected_rows + activity_expected_rows > max_expected_rows

    if (would_exceed_activity_limit || would_exceed_row_limit) {
      batches[[length(batches) + 1L]] <- current_batch

      current_batch <- activity_plan[0, , drop = FALSE]
      current_expected_rows <- 0L
    }

    current_batch <- rbind(
      current_batch,
      activity_row
    )

    current_expected_rows <- current_expected_rows + activity_expected_rows
  }

  if (nrow(current_batch) > 0) {
    batches[[length(batches) + 1L]] <- current_batch
  }

  batches
}

#' Format Activity ID Filter
#'
#' Format activity IDs for use in SQL IN clauses.
#'
#' @param activity_ids Activity IDs.
#'
#' @return Comma-separated activity IDs.
format_activity_id_filter <- function(activity_ids) {
  activity_ids_sql <- as.character(activity_ids)

  if (any(!grepl("^[0-9]+$", activity_ids_sql))) {
    stop("Activity IDs must contain digits only.", call. = FALSE)
  }

  paste(
    activity_ids_sql,
    collapse = ", "
  )
}

#' Delete Silver Activity Streams
#'
#' Delete existing silver stream samples for activity IDs.
#'
#' @param connection Database connection.
#' @param activity_ids Activity IDs.
#'
#' @return Number of rows deleted.
delete_silver_activity_streams <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(0L)
  }

  activity_id_filter <- format_activity_id_filter(activity_ids)

  DBI::dbExecute(
    conn = connection,
    statement = glue::glue("
      DELETE FROM cycling_platform_silver.activity_streams
      WHERE activity_id IN ({activity_id_filter})
    ")
  )
}

#' Insert Silver Activity Stream Batch
#'
#' Expand raw stream arrays into wide silver stream samples for one batch of
#' activities.
#'
#' @param connection Database connection.
#' @param activity_ids Activity IDs to transform.
#'
#' @return Number of rows inserted.
insert_silver_activity_stream_batch <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(0L)
  }

  activity_id_filter <- format_activity_id_filter(activity_ids)

  sql <- glue::glue("
    INSERT INTO cycling_platform_silver.activity_streams (
        activity_id,
        sample_index,
        time_seconds,
        distance_metres,
        latitude,
        longitude,
        altitude_metres,
        velocity_smooth_metres_per_second,
        heartrate_bpm,
        cadence_rpm,
        watts,
        temperature_celsius,
        is_moving,
        grade_smooth_percent,
        raw_stream_count,
        raw_max_original_size,
        raw_stream_retrieved_at,
        transformed_at
    )
    WITH digits AS (
        SELECT 0 AS n UNION ALL
        SELECT 1 UNION ALL
        SELECT 2 UNION ALL
        SELECT 3 UNION ALL
        SELECT 4 UNION ALL
        SELECT 5 UNION ALL
        SELECT 6 UNION ALL
        SELECT 7 UNION ALL
        SELECT 8 UNION ALL
        SELECT 9
    ),
    sequence_numbers AS (
        SELECT
            ones.n
            + tens.n * 10
            + hundreds.n * 100
            + thousands.n * 1000
            + ten_thousands.n * 10000
            + 1 AS sample_index
        FROM digits ones
        CROSS JOIN digits tens
        CROSS JOIN digits hundreds
        CROSS JOIN digits thousands
        CROSS JOIN digits ten_thousands
    ),
    activity_stream_summary AS (
        SELECT
            activity_id,
            COUNT(*) AS raw_stream_count,
            MAX(original_size) AS raw_max_original_size,
            MAX(retrieved_at) AS raw_stream_retrieved_at
        FROM cycling_platform_raw.activity_streams
        WHERE activity_id IN ({activity_id_filter})
        GROUP BY activity_id
    ),
    activity_samples AS (
        SELECT
            summary.activity_id,
            sequence_numbers.sample_index,
            summary.raw_stream_count,
            summary.raw_max_original_size,
            summary.raw_stream_retrieved_at
        FROM activity_stream_summary summary
        JOIN sequence_numbers
            ON sequence_numbers.sample_index <= summary.raw_max_original_size
    )
    SELECT
        samples.activity_id,
        samples.sample_index,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            time_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS time_seconds,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            distance_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS DECIMAL(18,6)) AS distance_metres,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            latlng_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, '][0]')
        )) AS DECIMAL(11,8)) AS latitude,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            latlng_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, '][1]')
        )) AS DECIMAL(11,8)) AS longitude,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            altitude_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS DECIMAL(18,6)) AS altitude_metres,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            velocity_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS DECIMAL(18,6)) AS velocity_smooth_metres_per_second,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            heartrate_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS heartrate_bpm,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            cadence_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS cadence_rpm,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            watts_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS watts,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            temp_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS temperature_celsius,
        CASE JSON_UNQUOTE(JSON_EXTRACT(
            moving_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        ))
            WHEN 'true' THEN TRUE
            WHEN 'false' THEN FALSE
            ELSE NULL
        END AS is_moving,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            grade_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS DECIMAL(18,6)) AS grade_smooth_percent,
        samples.raw_stream_count,
        samples.raw_max_original_size,
        samples.raw_stream_retrieved_at,
        UTC_TIMESTAMP() AS transformed_at
    FROM activity_samples samples
    LEFT JOIN cycling_platform_raw.activity_streams time_stream
        ON time_stream.activity_id = samples.activity_id
        AND time_stream.stream_type = 'time'
    LEFT JOIN cycling_platform_raw.activity_streams distance_stream
        ON distance_stream.activity_id = samples.activity_id
        AND distance_stream.stream_type = 'distance'
    LEFT JOIN cycling_platform_raw.activity_streams latlng_stream
        ON latlng_stream.activity_id = samples.activity_id
        AND latlng_stream.stream_type = 'latlng'
    LEFT JOIN cycling_platform_raw.activity_streams altitude_stream
        ON altitude_stream.activity_id = samples.activity_id
        AND altitude_stream.stream_type = 'altitude'
    LEFT JOIN cycling_platform_raw.activity_streams velocity_stream
        ON velocity_stream.activity_id = samples.activity_id
        AND velocity_stream.stream_type = 'velocity_smooth'
    LEFT JOIN cycling_platform_raw.activity_streams heartrate_stream
        ON heartrate_stream.activity_id = samples.activity_id
        AND heartrate_stream.stream_type = 'heartrate'
    LEFT JOIN cycling_platform_raw.activity_streams cadence_stream
        ON cadence_stream.activity_id = samples.activity_id
        AND cadence_stream.stream_type = 'cadence'
    LEFT JOIN cycling_platform_raw.activity_streams watts_stream
        ON watts_stream.activity_id = samples.activity_id
        AND watts_stream.stream_type = 'watts'
    LEFT JOIN cycling_platform_raw.activity_streams temp_stream
        ON temp_stream.activity_id = samples.activity_id
        AND temp_stream.stream_type = 'temp'
    LEFT JOIN cycling_platform_raw.activity_streams moving_stream
        ON moving_stream.activity_id = samples.activity_id
        AND moving_stream.stream_type = 'moving'
    LEFT JOIN cycling_platform_raw.activity_streams grade_stream
        ON grade_stream.activity_id = samples.activity_id
        AND grade_stream.stream_type = 'grade_smooth'
  ")

  DBI::dbExecute(
    conn = connection,
    statement = sql
  )
}

#' Rebuild Silver Activity Streams
#'
#' Truncate and rebuild silver stream samples in activity batches.
#'
#' @param connection Database connection.
#' @param batch_size Maximum number of activities to process per batch.
#' @param max_expected_rows Maximum expected stream rows per batch.
#' @param mode Use `full` to truncate and rebuild every activity, or `repair`
#'   to rebuild only activities with missing or incomplete silver rows.
#'
#' @return Invisibly returns NULL.
rebuild_silver_activity_streams <- function(
  connection,
  batch_size = 10L,
  max_expected_rows = 5000L,
  mode = c(
    "full",
    "repair"
  )
) {
  mode <- match.arg(mode)

  stopifnot(batch_size > 0)
  stopifnot(max_expected_rows > 0)

  if (mode == "full") {
    message("Truncating silver activity streams.")

    DBI::dbExecute(
      conn = connection,
      statement = "TRUNCATE TABLE cycling_platform_silver.activity_streams"
    )

    activity_plan <- get_silver_stream_activity_plan(
      connection = connection
    )
  } else {
    message("Repairing incomplete silver activity streams.")

    activity_plan <- get_silver_stream_repair_activity_plan(
      connection = connection
    )
  }

  activity_batches <- build_silver_stream_activity_batches(
    activity_plan = activity_plan,
    max_activities = batch_size,
    max_expected_rows = max_expected_rows
  )

  if (length(activity_batches) == 0) {
    message("No silver activity streams require rebuild.")

    return(invisible(NULL))
  }

  message(glue::glue(
    "Rebuilding silver activity streams for ",
    "{nrow(activity_plan)} activities in ",
    "{length(activity_batches)} batches ",
    "(max {batch_size} activities or {max_expected_rows} expected rows)."
  ))

  ensure_transform_logging_tables(
    connection = connection
  )

  transform_run_id <- create_transform_run(
    connection = connection,
    layer_name = "silver",
    entity_name = "activity_streams",
    run_mode = mode,
    total_batches = length(activity_batches),
    activities_planned = nrow(activity_plan),
    expected_rows_planned = sum(activity_plan$expected_row_count),
    max_batch_activities = batch_size,
    max_batch_expected_rows = max_expected_rows
  )

  safe_update_transform_run <- function(...) {
    tryCatch(
      update_transform_run(...),
      error = function(e) {
        message(glue::glue(
          "Unable to update transform run log: {conditionMessage(e)}"
        ))
      }
    )
  }

  safe_update_transform_run_batch <- function(...) {
    tryCatch(
      update_transform_run_batch(...),
      error = function(e) {
        message(glue::glue(
          "Unable to update transform batch log: {conditionMessage(e)}"
        ))
      }
    )
  }

  completed_batches <- 0L
  activities_completed <- 0L
  total_rows_deleted <- 0L
  total_rows_inserted <- 0L

  run_error <- tryCatch(
    {
      purrr::iwalk(
        activity_batches,
        \(activity_batch, batch_index) {
          activity_ids <- activity_batch$activity_id
          expected_rows <- sum(activity_batch$expected_row_count)

          message(glue::glue(
            "Processing silver stream batch {batch_index}/",
            "{length(activity_batches)} ",
            "({length(activity_ids)} activities, ",
            "{expected_rows} expected rows)."
          ))

          transform_run_batch_id <- create_transform_run_batch(
            connection = connection,
            transform_run_id = transform_run_id,
            batch_number = batch_index,
            activity_ids = activity_ids,
            expected_rows = expected_rows
          )

          rows_deleted <- 0L
          rows_inserted <- 0L

          batch_error <- tryCatch(
            {
              DBI::dbBegin(connection)

              tryCatch(
                {
                  rows_deleted <- delete_silver_activity_streams(
                    connection = connection,
                    activity_ids = activity_ids
                  )

                  rows_inserted <- insert_silver_activity_stream_batch(
                    connection = connection,
                    activity_ids = activity_ids
                  )

                  DBI::dbCommit(connection)
                },
                error = function(e) {
                  tryCatch(
                    DBI::dbRollback(connection),
                    error = function(rollback_error) {
                      message(glue::glue(
                        "Silver stream batch rollback failed: ",
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
            safe_update_transform_run_batch(
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
          activities_completed <<- activities_completed + length(activity_ids)
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
            "Completed silver stream batch {batch_index}/",
            "{length(activity_batches)}: ",
            "{rows_deleted} rows deleted, ",
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
    safe_update_transform_run(
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
    "Silver activity streams rebuild complete: ",
    "{total_rows_deleted} rows deleted, ",
    "{total_rows_inserted} rows inserted."
  ))

  invisible(NULL)
}
