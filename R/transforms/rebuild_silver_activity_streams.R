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

#' Fetch Raw Activity Streams For Silver
#'
#' @param connection Database connection.
#' @param activity_ids Activity IDs.
#'
#' @return Raw activity stream rows.
fetch_raw_activity_streams_for_silver <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(data.frame())
  }

  activity_id_filter <- format_activity_id_filter(activity_ids)

  DBI::dbGetQuery(
    conn = connection,
    statement = glue::glue("
      SELECT
          activity_id,
          stream_type,
          original_size,
          retrieved_at,
          stream_payload
      FROM cycling_platform_raw.activity_streams
      WHERE activity_id IN ({activity_id_filter})
      ORDER BY activity_id, stream_type
    ")
  )
}

#' Parse Raw Stream Payload
#'
#' @param payload Raw JSON payload.
#'
#' @return Parsed JSON vector/list.
parse_raw_stream_payload <- function(payload) {
  if (is.na(payload) || !nzchar(payload)) {
    return(NULL)
  }

  jsonlite::fromJSON(
    payload,
    simplifyVector = FALSE
  )
}

silver_stream_value_at <- function(streams, stream_type, sample_index) {
  stream <- streams[[stream_type]]

  if (is.null(stream) || length(stream) < sample_index) {
    return(NA)
  }

  stream[[sample_index]]
}

silver_stream_numeric_at <- function(streams, stream_type, sample_index) {
  value <- silver_stream_value_at(
    streams = streams,
    stream_type = stream_type,
    sample_index = sample_index
  )

  if (length(value) == 0 || is.null(value)) {
    return(NA_real_)
  }

  as.numeric(value)
}

silver_stream_integer_at <- function(streams, stream_type, sample_index) {
  value <- silver_stream_numeric_at(
    streams = streams,
    stream_type = stream_type,
    sample_index = sample_index
  )

  if (is.na(value)) {
    return(NA_integer_)
  }

  as.integer(value)
}

silver_stream_logical_at <- function(streams, stream_type, sample_index) {
  value <- silver_stream_value_at(
    streams = streams,
    stream_type = stream_type,
    sample_index = sample_index
  )

  if (length(value) == 0 || is.null(value)) {
    return(NA)
  }

  as.logical(value)
}

silver_stream_latlng_at <- function(streams, sample_index, position) {
  value <- silver_stream_value_at(
    streams = streams,
    stream_type = "latlng",
    sample_index = sample_index
  )

  if (length(value) < position) {
    return(NA_real_)
  }

  as.numeric(value[[position]])
}

#' Build Silver Activity Stream Rows
#'
#' Parse raw JSON payloads in R and build wide silver stream samples.
#'
#' @param raw_streams Raw stream rows for one activity.
#'
#' @return Data frame ready for `silver.activity_streams`.
build_silver_activity_stream_rows <- function(raw_streams) {
  if (nrow(raw_streams) == 0) {
    return(data.frame())
  }

  streams <- stats::setNames(
    lapply(
      raw_streams$stream_payload,
      parse_raw_stream_payload
    ),
    raw_streams$stream_type
  )

  sample_count <- max(
    raw_streams$original_size,
    na.rm = TRUE
  )

  raw_stream_retrieved_at <- max(
    raw_streams$retrieved_at,
    na.rm = TRUE
  )

  activity_id <- raw_streams$activity_id[[1]]
  sample_indexes <- seq_len(sample_count)
  transformed_at <- Sys.time()

  data.frame(
    activity_id = rep(activity_id, sample_count),
    sample_index = sample_indexes,
    time_seconds = vapply(
      sample_indexes,
      \(i) silver_stream_integer_at(streams, "time", i),
      integer(1)
    ),
    distance_metres = vapply(
      sample_indexes,
      \(i) silver_stream_numeric_at(streams, "distance", i),
      numeric(1)
    ),
    latitude = vapply(
      sample_indexes,
      \(i) silver_stream_latlng_at(streams, i, 1L),
      numeric(1)
    ),
    longitude = vapply(
      sample_indexes,
      \(i) silver_stream_latlng_at(streams, i, 2L),
      numeric(1)
    ),
    altitude_metres = vapply(
      sample_indexes,
      \(i) silver_stream_numeric_at(streams, "altitude", i),
      numeric(1)
    ),
    velocity_smooth_metres_per_second = vapply(
      sample_indexes,
      \(i) silver_stream_numeric_at(streams, "velocity_smooth", i),
      numeric(1)
    ),
    heartrate_bpm = vapply(
      sample_indexes,
      \(i) silver_stream_integer_at(streams, "heartrate", i),
      integer(1)
    ),
    cadence_rpm = vapply(
      sample_indexes,
      \(i) silver_stream_integer_at(streams, "cadence", i),
      integer(1)
    ),
    watts = vapply(
      sample_indexes,
      \(i) silver_stream_integer_at(streams, "watts", i),
      integer(1)
    ),
    temperature_celsius = vapply(
      sample_indexes,
      \(i) silver_stream_integer_at(streams, "temp", i),
      integer(1)
    ),
    is_moving = vapply(
      sample_indexes,
      \(i) silver_stream_logical_at(streams, "moving", i),
      logical(1)
    ),
    grade_smooth_percent = vapply(
      sample_indexes,
      \(i) silver_stream_numeric_at(streams, "grade_smooth", i),
      numeric(1)
    ),
    raw_stream_count = rep(nrow(raw_streams), sample_count),
    raw_max_original_size = rep(sample_count, sample_count),
    raw_stream_retrieved_at = rep(raw_stream_retrieved_at, sample_count),
    transformed_at = rep(transformed_at, sample_count)
  )
}

log_silver_stream_phase <- function(batch_index, phase, expr) {
  started_at <- Sys.time()

  message(glue::glue(
    "Silver stream batch {batch_index}: starting {phase}."
  ))

  result <- force(expr)

  elapsed_seconds <- as.numeric(
    difftime(
      Sys.time(),
      started_at,
      units = "secs"
    )
  )

  message(glue::glue(
    "Silver stream batch {batch_index}: completed {phase} in ",
    "{round(elapsed_seconds, 1)}s."
  ))

  result
}

#' Insert Silver Activity Stream Batch
#'
#' Expand raw stream arrays into wide silver stream samples for one batch.
#'
#' @param connection Database connection.
#' @param activity_ids Activity IDs to transform.
#' @param insert_chunk_size Number of rows per database insert chunk.
#' @param batch_index Batch number used for logging.
#'
#' @return Number of rows inserted.
insert_silver_activity_stream_batch <- function(
  connection,
  activity_ids,
  insert_chunk_size = 500L,
  batch_index = NA_integer_
) {
  if (length(activity_ids) == 0) {
    return(0L)
  }

  stopifnot(insert_chunk_size > 0)

  raw_streams <- log_silver_stream_phase(
    batch_index,
    "fetch raw streams",
    fetch_raw_activity_streams_for_silver(
      connection = connection,
      activity_ids = activity_ids
    )
  )

  if (nrow(raw_streams) == 0) {
    return(0L)
  }

  rows <- log_silver_stream_phase(
    batch_index,
    "parse JSON and build rows in R",
    {
      activity_groups <- split(
        raw_streams,
        as.character(raw_streams$activity_id)
      )

      do.call(
        rbind,
        lapply(
          activity_groups,
          build_silver_activity_stream_rows
        )
      )
    }
  )

  if (nrow(rows) == 0) {
    return(0L)
  }

  row_indexes <- split(
    seq_len(nrow(rows)),
    ceiling(seq_len(nrow(rows)) / insert_chunk_size)
  )

  rows_inserted <- 0L

  for (chunk_number in seq_along(row_indexes)) {
    indexes <- row_indexes[[chunk_number]]

    log_silver_stream_phase(
      batch_index,
      glue::glue(
        "insert chunk {chunk_number}/{length(row_indexes)} ",
        "({length(indexes)} rows)"
      ),
      DBI::dbWriteTable(
        conn = connection,
        name = DBI::Id(
          schema = "cycling_platform_silver",
          table = "activity_streams"
        ),
        value = rows[indexes, , drop = FALSE],
        append = TRUE,
        overwrite = FALSE
      )
    )

    rows_inserted <- rows_inserted + length(indexes)
  }

  rows_inserted
}

#' Rebuild Silver Activity Streams
#'
#' Truncate and rebuild silver stream samples in activity batches.
#'
#' @param connection Database connection.
#' @param batch_size Maximum number of activities to process per batch.
#' @param max_expected_rows Maximum expected stream rows per batch.
#' @param insert_chunk_size Number of silver rows inserted per DB write.
#' @param mode Use `full` to truncate and rebuild every activity, or `repair`
#'   to rebuild only activities with missing or incomplete silver rows.
#'
#' @return Invisibly returns NULL.
rebuild_silver_activity_streams <- function(
  connection,
  batch_size = 10L,
  max_expected_rows = 5000L,
  insert_chunk_size = 500L,
  mode = c(
    "full",
    "repair"
  )
) {
  mode <- match.arg(mode)

  stopifnot(batch_size > 0)
  stopifnot(max_expected_rows > 0)
  stopifnot(insert_chunk_size > 0)

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

  is_connection_loss <- function(error) {
    grepl(
      "Lost connection|Server has gone away",
      conditionMessage(error),
      ignore.case = TRUE
    )
  }

  reconnect_transform_connection <- function() {
    message("Silver stream transform connection lost; reconnecting.")

    tryCatch(
      {
        if (DBI::dbIsValid(connection)) {
          DBI::dbDisconnect(connection)
        }
      },
      error = function(e) {
        invisible(NULL)
      }
    )

    if (!exists("get_connection", mode = "function")) {
      stop(
        "Cannot reconnect because get_connection() is not available.",
        call. = FALSE
      )
    }

    connection <<- get_connection("cycling_platform_admin")

    invisible(NULL)
  }

  run_silver_stream_batch_transaction <- function(
    activity_ids,
    batch_index
  ) {
    rows_deleted <- 0L
    rows_inserted <- 0L

    DBI::dbBegin(connection)

    tryCatch(
      {
        rows_deleted <- delete_silver_activity_streams(
          connection = connection,
          activity_ids = activity_ids
        )

        message(glue::glue(
          "Silver stream batch {batch_index}: ",
          "deleted {rows_deleted} existing rows."
        ))

        rows_inserted <- insert_silver_activity_stream_batch(
          connection = connection,
          activity_ids = activity_ids,
          insert_chunk_size = insert_chunk_size,
          batch_index = batch_index
        )

        message(glue::glue(
          "Silver stream batch {batch_index}: committing ",
          "{rows_inserted} inserted rows."
        ))

        DBI::dbCommit(connection)

        message(glue::glue(
          "Silver stream batch {batch_index}: commit complete."
        ))
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

    list(
      rows_deleted = rows_deleted,
      rows_inserted = rows_inserted
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
          batch_result <- NULL

          batch_error <- tryCatch(
            {
              batch_result <- run_silver_stream_batch_transaction(
                activity_ids = activity_ids,
                batch_index = batch_index
              )

              NULL
            },
            error = function(e) {
              e
            }
          )

          if (!is.null(batch_error) && is_connection_loss(batch_error)) {
            message(glue::glue(
              "Silver stream batch {batch_index}: connection lost; ",
              "retrying this batch once after reconnect."
            ))

            reconnect_transform_connection()

            batch_error <- tryCatch(
              {
                batch_result <- run_silver_stream_batch_transaction(
                  activity_ids = activity_ids,
                  batch_index = batch_index
                )

                NULL
              },
              error = function(e) {
                e
              }
            )
          }

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

          rows_deleted <- batch_result$rows_deleted
          rows_inserted <- batch_result$rows_inserted

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
