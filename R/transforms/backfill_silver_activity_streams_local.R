#' Local Silver Activity Stream Backfill
#'
#' Temporary historical backfill for silver activity streams. This parses raw
#' stream JSON in R and writes one activity at a time, which avoids expensive
#' MariaDB JSON extraction on the Raspberry Pi.
#'
#' @param connection DBI connection to MariaDB.
#' @param mode Use `repair` for missing/mismatched activities or `full` for all
#'   raw stream activities.
#' @param activity_ids Optional activity IDs to process.
#' @param insert_chunk_size Number of silver rows inserted per DB write.
#' @param stop_on_error Stop on first activity failure when TRUE.
#' @param max_activities Optional maximum number of activities to process.
#' @param max_runtime_minutes Optional maximum runtime in minutes.
#'
#' @return Invisibly returns a data frame of activity-level results.
backfill_silver_activity_streams_local <- function(
  connection,
  mode = c(
    "repair",
    "full"
  ),
  activity_ids = NULL,
  insert_chunk_size = 500L,
  stop_on_error = FALSE,
  max_activities = NULL,
  max_runtime_minutes = NULL
) {
  mode <- match.arg(mode)

  stopifnot(insert_chunk_size > 0)

  if (!is.null(max_activities)) {
    stopifnot(max_activities > 0)
  }

  if (!is.null(max_runtime_minutes)) {
    stopifnot(max_runtime_minutes > 0)
  }

  is_connection_loss <- function(error) {
    grepl(
      "Lost connection|Server has gone away",
      conditionMessage(error),
      ignore.case = TRUE
    )
  }

  reconnect <- function() {
    message("Database connection lost; reconnecting before continuing.")

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

    connection <<- get_connection("cycling_platform_raw")

    invisible(NULL)
  }

  ensure_connection <- function(reason) {
    connection_ok <- tryCatch(
      DBI::dbIsValid(connection) &&
        isTRUE(
          DBI::dbGetQuery(
            connection,
            "SELECT 1 AS ok"
          )$ok[[1]] == 1
        ),
      error = function(e) {
        FALSE
      }
    )

    if (!isTRUE(connection_ok)) {
      message(glue::glue(
        "Database connection invalid before {reason}; reconnecting."
      ))

      reconnect()
    }

    invisible(NULL)
  }

  phase_time <- function(activity_id, phase, expr) {
    phase_started_at <- Sys.time()

    result <- force(expr)

    elapsed_seconds <- as.numeric(
      difftime(
        Sys.time(),
        phase_started_at,
        units = "secs"
      )
    )

    message(glue::glue(
      "Activity {activity_id}: {phase} completed in ",
      "{round(elapsed_seconds, 2)}s."
    ))

    result
  }

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

  get_activity_plan <- function() {
    activity_filter <- ""

    if (!is.null(activity_ids)) {
      activity_filter <- paste0(
        "WHERE activity_id IN (",
        format_activity_id_filter(activity_ids),
        ")"
      )
    }

    sql <- if (mode == "full") {
      paste0(
        "
        SELECT
          activity_id,
          MAX(original_size) AS expected_sample_count
        FROM cycling_platform_raw.activity_streams
        ",
        activity_filter,
        "
        GROUP BY activity_id
        ORDER BY activity_id
        "
      )
    } else {
      paste0(
        "
        WITH raw_summary AS (
          SELECT
            activity_id,
            MAX(original_size) AS expected_sample_count
          FROM cycling_platform_raw.activity_streams
          ",
          activity_filter,
          "
          GROUP BY activity_id
        ),
        silver_summary AS (
          SELECT
            activity_id,
            COUNT(*) AS actual_sample_count
          FROM cycling_platform_silver.activity_streams
          GROUP BY activity_id
        )
        SELECT
          raw_summary.activity_id,
          raw_summary.expected_sample_count
        FROM raw_summary
        LEFT JOIN silver_summary
          ON silver_summary.activity_id = raw_summary.activity_id
        WHERE COALESCE(silver_summary.actual_sample_count, 0)
          <> raw_summary.expected_sample_count
        ORDER BY raw_summary.activity_id
        "
      )
    }

    DBI::dbGetQuery(
      conn = connection,
      statement = sql
    )
  }

  get_raw_streams <- function(activity_id) {
    DBI::dbGetQuery(
      conn = connection,
      statement = "
        SELECT
          activity_id,
          stream_type,
          original_size,
          retrieved_at,
          stream_payload
        FROM cycling_platform_raw.activity_streams
        WHERE activity_id = ?
        ORDER BY stream_type
      ",
      params = list(activity_id)
    )
  }

  parse_stream_payload <- function(payload) {
    if (is.na(payload) || !nzchar(payload)) {
      return(NULL)
    }

    jsonlite::fromJSON(
      payload,
      simplifyVector = FALSE
    )
  }

  value_at <- function(streams, stream_type, sample_index) {
    stream <- streams[[stream_type]]

    if (is.null(stream) || length(stream) < sample_index) {
      return(NA)
    }

    stream[[sample_index]]
  }

  numeric_at <- function(streams, stream_type, sample_index) {
    value <- value_at(
      streams,
      stream_type,
      sample_index
    )

    if (length(value) == 0 || is.null(value)) {
      return(NA_real_)
    }

    as.numeric(value)
  }

  integer_at <- function(streams, stream_type, sample_index) {
    value <- numeric_at(
      streams,
      stream_type,
      sample_index
    )

    if (is.na(value)) {
      return(NA_integer_)
    }

    as.integer(value)
  }

  logical_at <- function(streams, stream_type, sample_index) {
    value <- value_at(
      streams,
      stream_type,
      sample_index
    )

    if (length(value) == 0 || is.null(value)) {
      return(NA)
    }

    as.logical(value)
  }

  latlng_at <- function(streams, sample_index, position) {
    value <- value_at(
      streams,
      "latlng",
      sample_index
    )

    if (length(value) < position) {
      return(NA_real_)
    }

    as.numeric(value[[position]])
  }

  parse_raw_streams <- function(raw_streams) {
    stats::setNames(
      lapply(
        raw_streams$stream_payload,
        parse_stream_payload
      ),
      raw_streams$stream_type
    )
  }

  build_activity_stream_rows <- function(raw_streams, streams) {
    if (nrow(raw_streams) == 0) {
      return(data.frame())
    }

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

    data.frame(
      activity_id = rep(
        activity_id,
        sample_count
      ),
      sample_index = sample_indexes,
      time_seconds = vapply(
        sample_indexes,
        \(i) integer_at(streams, "time", i),
        integer(1)
      ),
      distance_metres = vapply(
        sample_indexes,
        \(i) numeric_at(streams, "distance", i),
        numeric(1)
      ),
      latitude = vapply(
        sample_indexes,
        \(i) latlng_at(streams, i, 1L),
        numeric(1)
      ),
      longitude = vapply(
        sample_indexes,
        \(i) latlng_at(streams, i, 2L),
        numeric(1)
      ),
      altitude_metres = vapply(
        sample_indexes,
        \(i) numeric_at(streams, "altitude", i),
        numeric(1)
      ),
      velocity_smooth_metres_per_second = vapply(
        sample_indexes,
        \(i) numeric_at(streams, "velocity_smooth", i),
        numeric(1)
      ),
      heartrate_bpm = vapply(
        sample_indexes,
        \(i) integer_at(streams, "heartrate", i),
        integer(1)
      ),
      cadence_rpm = vapply(
        sample_indexes,
        \(i) integer_at(streams, "cadence", i),
        integer(1)
      ),
      watts = vapply(
        sample_indexes,
        \(i) integer_at(streams, "watts", i),
        integer(1)
      ),
      temperature_celsius = vapply(
        sample_indexes,
        \(i) integer_at(streams, "temp", i),
        integer(1)
      ),
      is_moving = vapply(
        sample_indexes,
        \(i) logical_at(streams, "moving", i),
        logical(1)
      ),
      grade_smooth_percent = vapply(
        sample_indexes,
        \(i) numeric_at(streams, "grade_smooth", i),
        numeric(1)
      ),
      raw_stream_count = rep(
        nrow(raw_streams),
        sample_count
      ),
      raw_max_original_size = rep(
        sample_count,
        sample_count
      ),
      raw_stream_retrieved_at = rep(
        raw_stream_retrieved_at,
        sample_count
      ),
      transformed_at = rep(
        Sys.time(),
        sample_count
      )
    )
  }

  delete_activity_rows <- function(activity_id) {
    DBI::dbExecute(
      conn = connection,
      statement = "
        DELETE FROM cycling_platform_silver.activity_streams
        WHERE activity_id = ?
      ",
      params = list(activity_id)
    )
  }

  insert_activity_rows <- function(rows, activity_id) {
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

      phase_time(
        activity_id,
        paste0(
          "insert chunk ",
          chunk_number,
          "/",
          length(row_indexes)
        ),
        tryCatch(
          DBI::dbWriteTable(
            conn = connection,
            name = DBI::Id(
              schema = "cycling_platform_silver",
              table = "activity_streams"
            ),
            value = rows[indexes, , drop = FALSE],
            append = TRUE,
            overwrite = FALSE
          ),
          error = function(e) {
            message(glue::glue(
              "Activity {activity_id}: insert chunk {chunk_number}/",
              "{length(row_indexes)} failed: {conditionMessage(e)}"
            ))

            stop(e)
          }
        )
      )

      rows_inserted <- rows_inserted + length(indexes)
    }

    rows_inserted
  }

  process_activity <- function(
    activity_id,
    expected_sample_count,
    retry_connection_loss = TRUE
  ) {
    ensure_connection("activity start")

    started_at <- Sys.time()
    inserted_rows <- 0L

    tryCatch(
      {
        raw_streams <- phase_time(
          activity_id,
          "fetch raw",
          get_raw_streams(activity_id)
        )

        streams <- phase_time(
          activity_id,
          "parse JSON",
          parse_raw_streams(raw_streams)
        )

        rebuilt_rows <- phase_time(
          activity_id,
          "build rows",
          build_activity_stream_rows(
            raw_streams,
            streams
          )
        )

        ensure_connection("DB writes")

        DBI::dbBegin(connection)

        phase_time(
          activity_id,
          "delete existing",
          delete_activity_rows(activity_id)
        )

        inserted_rows <- insert_activity_rows(
          rebuilt_rows,
          activity_id
        )

        phase_time(
          activity_id,
          "commit",
          DBI::dbCommit(connection)
        )

        elapsed_seconds <- as.numeric(
          difftime(
            Sys.time(),
            started_at,
            units = "secs"
          )
        )

        message(glue::glue(
          "Activity {activity_id}: expected {expected_sample_count}, ",
          "inserted {inserted_rows}, elapsed {round(elapsed_seconds, 2)}s."
        ))

        data.frame(
          activity_id = as.character(activity_id),
          status = "SUCCESS",
          expected_sample_count = expected_sample_count,
          inserted_rows = inserted_rows,
          elapsed_seconds = elapsed_seconds,
          error_message = NA_character_
        )
      },
      error = function(e) {
        tryCatch(
          DBI::dbRollback(connection),
          error = function(rollback_error) {
            message(glue::glue(
              "Rollback failed for activity {activity_id}: ",
              "{conditionMessage(rollback_error)}"
            ))
          }
        )

        if (is_connection_loss(e)) {
          reconnect()

          if (isTRUE(retry_connection_loss)) {
            message(glue::glue(
              "Retrying activity {activity_id} once after reconnect."
            ))

            return(
              process_activity(
                activity_id = activity_id,
                expected_sample_count = expected_sample_count,
                retry_connection_loss = FALSE
              )
            )
          }
        }

        elapsed_seconds <- as.numeric(
          difftime(
            Sys.time(),
            started_at,
            units = "secs"
          )
        )

        message(glue::glue(
          "Activity {activity_id}: FAILED after ",
          "{round(elapsed_seconds, 2)}s: {conditionMessage(e)}"
        ))

        if (isTRUE(stop_on_error)) {
          stop(e)
        }

        data.frame(
          activity_id = as.character(activity_id),
          status = "FAILED",
          expected_sample_count = expected_sample_count,
          inserted_rows = inserted_rows,
          elapsed_seconds = elapsed_seconds,
          error_message = conditionMessage(e)
        )
      }
    )
  }

  activity_plan <- get_activity_plan()

  if (nrow(activity_plan) == 0) {
    message("No silver activity streams require local backfill.")

    return(
      invisible(
        data.frame(
          activity_id = character(),
          status = character(),
          expected_sample_count = numeric(),
          inserted_rows = integer(),
          elapsed_seconds = numeric(),
          error_message = character()
        )
      )
    )
  }

  activity_plan$expected_sample_count <- as.numeric(
    as.character(activity_plan$expected_sample_count)
  )

  message(glue::glue(
    "Local silver stream backfill: processing {nrow(activity_plan)} ",
    "activities in {mode} mode."
  ))

  run_started_at <- Sys.time()

  results <- list()

  for (i in seq_len(nrow(activity_plan))) {
    processed_count <- length(results)

    if (!is.null(max_activities) && processed_count >= max_activities) {
      message(glue::glue(
        "Stopping local silver stream backfill after ",
        "{processed_count} activities because max_activities=",
        "{max_activities} was reached."
      ))

      break
    }

    if (!is.null(max_runtime_minutes)) {
      elapsed_minutes <- as.numeric(
        difftime(
          Sys.time(),
          run_started_at,
          units = "mins"
        )
      )

      if (elapsed_minutes >= max_runtime_minutes) {
        message(glue::glue(
          "Stopping local silver stream backfill after ",
          "{round(elapsed_minutes, 2)} minutes because ",
          "max_runtime_minutes={max_runtime_minutes} was reached."
        ))

        break
      }
    }

    results[[length(results) + 1L]] <- process_activity(
      activity_id = activity_plan$activity_id[[i]],
      expected_sample_count = activity_plan$expected_sample_count[[i]]
    )
  }

  if (length(results) == 0) {
    results <- data.frame(
      activity_id = character(),
      status = character(),
      expected_sample_count = numeric(),
      inserted_rows = integer(),
      elapsed_seconds = numeric(),
      error_message = character()
    )
  } else {
    results <- do.call(
      rbind,
      results
    )
  }

  message(glue::glue(
    "Local silver stream backfill complete: ",
    "{sum(results$status == 'SUCCESS')} succeeded, ",
    "{sum(results$status == 'FAILED')} failed, ",
    "{sum(results$inserted_rows)} rows inserted."
  ))

  invisible(results)
}
