#' Local Silver Activity Stream Backfill
#'
#' Temporary historical backfill for silver activity streams. This parses raw
#' stream JSON in R and writes one activity at a time, which avoids expensive
#' MariaDB JSON extraction on the Raspberry Pi.
#'
#' @param connection DBI connection to MariaDB.
#' @param mode Use `repair` for missing/mismatched activities, `full` for all
#'   raw stream activities, `staging_repair` to stage remaining repair rows and
#'   merge them into silver, or `staging_merge` to merge existing staged rows
#'   without rebuilding staging.
#' @param activity_ids Optional activity IDs to process.
#' @param insert_chunk_size Number of silver rows inserted per DB write.
#' @param stop_on_error Stop on first activity failure when TRUE.
#' @param max_activities Optional maximum number of activities to process.
#' @param max_runtime_minutes Optional maximum runtime in minutes.
#' @param run_id Optional ETL run identifier for `staging_repair` ownership.
#' @param source_id Source identifier used if `staging_repair` creates a run.
#' @param merge_batch_activities Number of staged activity IDs merged per
#'   transaction.
#'
#' @return Invisibly returns a data frame of activity-level results.
backfill_silver_activity_streams_local <- function(
  connection,
  mode = c(
    "repair",
    "full",
    "staging_repair",
    "staging_merge"
  ),
  activity_ids = NULL,
  insert_chunk_size = 500L,
  stop_on_error = FALSE,
  max_activities = NULL,
  max_runtime_minutes = NULL,
  run_id = NULL,
  source_id = 1L,
  merge_batch_activities = 5L
) {
  mode <- match.arg(mode)

  created_stage_run <- FALSE
  stage_run_completed <- FALSE

  stopifnot(insert_chunk_size > 0)
  stopifnot(merge_batch_activities > 0)

  if (!is.null(max_activities)) {
    stopifnot(max_activities > 0)
  }

  if (!is.null(max_runtime_minutes)) {
    stopifnot(max_runtime_minutes > 0)
  }

  if (mode == "staging_repair" && is.null(run_id)) {
    run_id <- create_etl_run(
      connection = connection,
      source_id = source_id,
      run_mode = "BACKFILL"
    )

    created_stage_run <- TRUE

    message(glue::glue(
      "Staging repair: created ETL run {run_id} for stage ownership."
    ))

    on.exit(
      {
        if (!isTRUE(stage_run_completed)) {
          tryCatch(
            update_etl_run(
              connection = connection,
              run_id = run_id,
              run_status = "FAILED",
              error_message = "staging_repair exited before successful completion"
            ),
            error = function(e) {
              invisible(NULL)
            }
          )
        }
      },
      add = TRUE
    )
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

  silver_stream_columns <- c(
    "activity_id",
    "sample_index",
    "time_seconds",
    "distance_metres",
    "latitude",
    "longitude",
    "altitude_metres",
    "velocity_smooth_metres_per_second",
    "heartrate_bpm",
    "cadence_rpm",
    "watts",
    "temperature_celsius",
    "is_moving",
    "grade_smooth_percent",
    "raw_stream_count",
    "raw_max_original_size",
    "raw_stream_retrieved_at",
    "transformed_at"
  )

  staging_table <- DBI::Id(
    schema = "cycling_platform_stage",
    table = "activity_streams_build"
  )

  create_staging_table <- function() {
    DBI::dbExecute(
      conn = connection,
      statement = "
        CREATE TABLE IF NOT EXISTS
          cycling_platform_stage.activity_streams_build (

          run_id BIGINT NOT NULL,

          activity_id BIGINT NOT NULL,

          sample_index INT NOT NULL,

          time_seconds INT NULL,

          distance_metres DOUBLE NULL,

          latitude DOUBLE NULL,

          longitude DOUBLE NULL,

          altitude_metres DOUBLE NULL,

          velocity_smooth_metres_per_second DOUBLE NULL,

          heartrate_bpm INT NULL,

          cadence_rpm INT NULL,

          watts INT NULL,

          temperature_celsius INT NULL,

          is_moving BOOLEAN NULL,

          grade_smooth_percent DOUBLE NULL,

          raw_stream_count INT NOT NULL,

          raw_max_original_size INT NOT NULL,

          raw_stream_retrieved_at DATETIME NOT NULL,

          transformed_at DATETIME NOT NULL,

          staged_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

          PRIMARY KEY (run_id, activity_id, sample_index),

          CONSTRAINT fk_stage_activity_streams_build_run
            FOREIGN KEY (run_id)
            REFERENCES cycling_platform_admin.etl_run (run_id)

        )
      "
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

    repair_mode <- mode %in% c(
      "repair",
      "staging_repair"
    )

    sql <- if (!repair_mode) {
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

  get_staging_summary <- function() {
    create_staging_table()

    if (is.null(run_id)) {
      return(
        DBI::dbGetQuery(
          conn = connection,
          statement = "
            SELECT
              activity_id,
              COUNT(*) AS staged_sample_count
            FROM cycling_platform_stage.activity_streams_build
            GROUP BY activity_id
          "
        )
      )
    }

    DBI::dbGetQuery(
      conn = connection,
      statement = "
        SELECT
          activity_id,
          COUNT(*) AS staged_sample_count
        FROM cycling_platform_stage.activity_streams_build
        WHERE run_id = ?
        GROUP BY activity_id
      ",
      params = list(run_id)
    )
  }

  get_next_staged_activity_ids <- function() {
    limit <- as.integer(merge_batch_activities)

    if (is.null(run_id)) {
      return(
        DBI::dbGetQuery(
          conn = connection,
          statement = "
            SELECT DISTINCT activity_id
            FROM cycling_platform_stage.activity_streams_build
            ORDER BY activity_id
            LIMIT ?
          ",
          params = list(limit)
        )$activity_id
      )
    }

    DBI::dbGetQuery(
      conn = connection,
      statement = "
        SELECT DISTINCT activity_id
        FROM cycling_platform_stage.activity_streams_build
        WHERE run_id = ?
        ORDER BY activity_id
        LIMIT ?
      ",
      params = list(
        run_id,
        limit
      )
    )$activity_id
  }

  placeholders <- function(values) {
    paste(
      rep("?", length(values)),
      collapse = ", "
    )
  }

  remove_fully_staged_activities <- function(activity_plan) {
    staging_summary <- get_staging_summary()

    if (nrow(staging_summary) == 0) {
      return(activity_plan)
    }

    activity_plan$activity_id_chr <- as.character(
      activity_plan$activity_id
    )

    staging_summary$activity_id_chr <- as.character(
      staging_summary$activity_id
    )

    activity_plan <- merge(
      activity_plan,
      staging_summary[
        ,
        c(
          "activity_id_chr",
          "staged_sample_count"
        ),
        drop = FALSE
      ],
      by = "activity_id_chr",
      all.x = TRUE,
      sort = FALSE
    )

    activity_plan$staged_sample_count <- as.numeric(
      activity_plan$staged_sample_count
    )

    already_staged <- !is.na(activity_plan$staged_sample_count) &
      activity_plan$staged_sample_count == activity_plan$expected_sample_count

    if (any(already_staged)) {
      message(glue::glue(
        "Staging repair: {sum(already_staged)} activities already staged ",
        "with expected row counts; skipping rebuild."
      ))
    }

    activity_plan <- activity_plan[
      !already_staged,
      c(
        "activity_id",
        "expected_sample_count"
      ),
      drop = FALSE
    ]

    activity_plan
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

  delete_staging_activity_rows <- function(activity_id) {
    DBI::dbExecute(
      conn = connection,
      statement = "
        DELETE FROM cycling_platform_stage.activity_streams_build
        WHERE run_id = ?
          AND activity_id = ?
      ",
      params = list(
        run_id,
        activity_id
      )
    )
  }

  append_staging_rows <- function(rows, activity_id) {
    if (nrow(rows) == 0) {
      return(0L)
    }

    row_indexes <- split(
      seq_len(nrow(rows)),
      ceiling(seq_len(nrow(rows)) / insert_chunk_size)
    )

    rows$run_id <- run_id

    rows <- rows[
      ,
      c(
        "run_id",
        silver_stream_columns
      ),
      drop = FALSE
    ]

    rows_inserted <- 0L

    for (chunk_number in seq_along(row_indexes)) {
      indexes <- row_indexes[[chunk_number]]

      phase_time(
        activity_id,
        paste0(
          "stage append chunk ",
          chunk_number,
          "/",
          length(row_indexes)
        ),
        tryCatch(
          DBI::dbWriteTable(
            conn = connection,
            name = staging_table,
            value = rows[indexes, , drop = FALSE],
            append = TRUE,
            overwrite = FALSE
          ),
          error = function(e) {
            message(glue::glue(
              "Activity {activity_id}: staging chunk {chunk_number}/",
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

  process_activity_to_staging <- function(
    activity_id,
    expected_sample_count,
    retry_connection_loss = TRUE
  ) {
    ensure_connection("staging activity start")

    started_at <- Sys.time()
    staged_rows <- 0L

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

        ensure_connection("staging writes")

        phase_time(
          activity_id,
          "delete existing staging rows",
          delete_staging_activity_rows(activity_id)
        )

        staged_rows <- append_staging_rows(
          rebuilt_rows,
          activity_id
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
          "staged {staged_rows}, elapsed {round(elapsed_seconds, 2)}s."
        ))

        data.frame(
          activity_id = as.character(activity_id),
          status = "SUCCESS",
          expected_sample_count = expected_sample_count,
          inserted_rows = staged_rows,
          elapsed_seconds = elapsed_seconds,
          error_message = NA_character_
        )
      },
      error = function(e) {
        if (is_connection_loss(e)) {
          reconnect()

          if (isTRUE(retry_connection_loss)) {
            message(glue::glue(
              "Retrying staging for activity {activity_id} once after ",
              "reconnect."
            ))

            return(
              process_activity_to_staging(
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
          "Activity {activity_id}: STAGING FAILED after ",
          "{round(elapsed_seconds, 2)}s: {conditionMessage(e)}"
        ))

        if (isTRUE(stop_on_error)) {
          stop(e)
        }

        data.frame(
          activity_id = as.character(activity_id),
          status = "FAILED",
          expected_sample_count = expected_sample_count,
          inserted_rows = staged_rows,
          elapsed_seconds = elapsed_seconds,
          error_message = conditionMessage(e)
        )
      }
    )
  }

  apply_staged_rows <- function() {
    ensure_connection("staging apply")

    staging_summary <- get_staging_summary()

    if (nrow(staging_summary) == 0) {
      message("Staging repair: no staged rows to apply.")

      return(
        list(
          activities_applied = 0L,
          rows_deleted = 0L,
          rows_inserted = 0L
        )
      )
    }

    validation_sql <- if (is.null(run_id)) {
      "
      WITH staged_summary AS (
        SELECT
          activity_id,
          COUNT(*) AS staged_sample_count
        FROM cycling_platform_stage.activity_streams_build
        GROUP BY activity_id
      ),
      raw_summary AS (
        SELECT
          activity_id,
          MAX(original_size) AS expected_sample_count
        FROM cycling_platform_raw.activity_streams
        GROUP BY activity_id
      )
      SELECT
        staged_summary.activity_id,
        staged_summary.staged_sample_count,
        raw_summary.expected_sample_count
      FROM staged_summary
      LEFT JOIN raw_summary
        ON raw_summary.activity_id = staged_summary.activity_id
      WHERE raw_summary.activity_id IS NULL
         OR staged_summary.staged_sample_count
           <> raw_summary.expected_sample_count
      "
    } else {
      "
      WITH staged_summary AS (
        SELECT
          activity_id,
          COUNT(*) AS staged_sample_count
        FROM cycling_platform_stage.activity_streams_build
        WHERE run_id = ?
        GROUP BY activity_id
      ),
      raw_summary AS (
        SELECT
          activity_id,
          MAX(original_size) AS expected_sample_count
        FROM cycling_platform_raw.activity_streams
        GROUP BY activity_id
      )
      SELECT
        staged_summary.activity_id,
        staged_summary.staged_sample_count,
        raw_summary.expected_sample_count
      FROM staged_summary
      LEFT JOIN raw_summary
        ON raw_summary.activity_id = staged_summary.activity_id
      WHERE raw_summary.activity_id IS NULL
         OR staged_summary.staged_sample_count
           <> raw_summary.expected_sample_count
      "
    }

    validation_failures <- if (is.null(run_id)) {
      DBI::dbGetQuery(
        conn = connection,
        statement = validation_sql
      )
    } else {
      DBI::dbGetQuery(
        conn = connection,
        statement = validation_sql,
        params =
        list(run_id)
      )
    }

    if (nrow(validation_failures) > 0) {
      stop(
        "Staging repair validation failed for ",
        nrow(validation_failures),
        " activities; staged rows retained",
        if (is.null(run_id)) "" else paste0(" for run_id ", run_id),
        ".",
        call. = FALSE
      )
    }

    if (is.null(run_id)) {
      message("Staging repair: validation passed for all staged rows.")
    } else {
      message(glue::glue(
        "Staging repair: validation passed for run_id {run_id}."
      ))
    }

    staged_activity_count <- nrow(staging_summary)

    staged_row_count <- sum(
      as.numeric(staging_summary$staged_sample_count),
      na.rm = TRUE
    )

    message(glue::glue(
      "Staging repair: applying {staged_row_count} staged rows for ",
      "{staged_activity_count} activities to silver.activity_streams ",
      "in batches of {merge_batch_activities} activities."
    ))

    column_sql <- paste(
      silver_stream_columns,
      collapse = ", "
    )

    rows_deleted <- 0L
    rows_inserted <- 0L
    apply_started_at <- Sys.time()

    batches_applied <- 0L

    repeat {
      batch_activity_ids <- get_next_staged_activity_ids()

      if (length(batch_activity_ids) == 0) {
        break
      }

      batch_started_at <- Sys.time()
      batch_activity_ids_chr <- as.character(batch_activity_ids)
      activity_placeholder_sql <- placeholders(batch_activity_ids_chr)

      staged_batch_rows <- DBI::dbGetQuery(
        conn = connection,
        statement = paste0(
          "SELECT COUNT(*) AS row_count ",
          "FROM cycling_platform_stage.activity_streams_build ",
          "WHERE activity_id IN (",
          activity_placeholder_sql,
          ")",
          if (is.null(run_id)) "" else " AND run_id = ?"
        ),
        params = if (is.null(run_id)) {
          as.list(batch_activity_ids_chr)
        } else {
          c(
            as.list(batch_activity_ids_chr),
            list(run_id)
          )
        }
      )$row_count[[1]]

      message(glue::glue(
        "Staging merge batch {batches_applied + 1}: ",
        "{length(batch_activity_ids_chr)} activities, ",
        "{staged_batch_rows} staged rows."
      ))

      DBI::dbBegin(connection)

      batch_deleted <- 0L
      batch_inserted <- 0L

      tryCatch(
        {
          batch_deleted <- DBI::dbExecute(
            conn = connection,
            statement = paste0(
              "DELETE FROM cycling_platform_silver.activity_streams ",
              "WHERE activity_id IN (",
              activity_placeholder_sql,
              ")"
            ),
            params = as.list(batch_activity_ids_chr)
          )

          batch_inserted <- DBI::dbExecute(
            conn = connection,
            statement = paste0(
              "INSERT INTO cycling_platform_silver.activity_streams (",
              column_sql,
              ") SELECT ",
              column_sql,
              " FROM cycling_platform_stage.activity_streams_build ",
              "WHERE activity_id IN (",
              activity_placeholder_sql,
              ")",
              if (is.null(run_id)) "" else " AND run_id = ?"
            ),
            params = if (is.null(run_id)) {
              as.list(batch_activity_ids_chr)
            } else {
              c(
                as.list(batch_activity_ids_chr),
                list(run_id)
              )
            }
          )

          DBI::dbCommit(connection)
        },
        error = function(e) {
          tryCatch(
            DBI::dbRollback(connection),
            error = function(rollback_error) {
              message(glue::glue(
                "Staging merge batch rollback failed: ",
                "{conditionMessage(rollback_error)}"
              ))
            }
          )

          message(glue::glue(
            "Staging merge batch failed; staged rows retained for retry: ",
            "{conditionMessage(e)}"
          ))

          stop(e)
        }
      )

      staged_rows_deleted <- DBI::dbExecute(
        conn = connection,
        statement = paste0(
          "DELETE FROM cycling_platform_stage.activity_streams_build ",
          "WHERE activity_id IN (",
          activity_placeholder_sql,
          ")",
          if (is.null(run_id)) "" else " AND run_id = ?"
        ),
        params = if (is.null(run_id)) {
          as.list(batch_activity_ids_chr)
        } else {
          c(
            as.list(batch_activity_ids_chr),
            list(run_id)
          )
        }
      )

      batch_elapsed_seconds <- as.numeric(
        difftime(
          Sys.time(),
          batch_started_at,
          units = "secs"
        )
      )

      rows_deleted <- rows_deleted + batch_deleted
      rows_inserted <- rows_inserted + batch_inserted
      batches_applied <- batches_applied + 1L

      message(glue::glue(
        "Completed staging merge batch {batches_applied}: ",
        "{length(batch_activity_ids_chr)} activities, ",
        "{batch_deleted} silver rows deleted, ",
        "{batch_inserted} silver rows inserted, ",
        "{staged_rows_deleted} staged rows removed, ",
        "elapsed {round(batch_elapsed_seconds, 2)}s."
      ))
    }

    elapsed_seconds <- as.numeric(
      difftime(
        Sys.time(),
        apply_started_at,
        units = "secs"
      )
    )

    message(glue::glue(
      "Staging repair apply complete: {rows_deleted} rows deleted, ",
      "{rows_inserted} rows inserted, elapsed {round(elapsed_seconds, 2)}s."
    ))

    list(
      activities_applied = staged_activity_count,
      batches_applied = batches_applied,
      rows_deleted = rows_deleted,
      rows_inserted = rows_inserted
    )
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

  if (mode == "staging_merge") {
    phase_time(
      "staging",
      "create staging table",
      create_staging_table()
    )

    return(
      invisible(
        apply_staged_rows()
      )
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

  if (mode == "staging_repair") {
    phase_time(
      "staging",
      "create staging table",
      create_staging_table()
    )

    activity_plan <- remove_fully_staged_activities(
      activity_plan
    )
  }

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

    if (mode == "staging_repair") {
      results[[length(results) + 1L]] <- process_activity_to_staging(
        activity_id = activity_plan$activity_id[[i]],
        expected_sample_count = activity_plan$expected_sample_count[[i]]
      )
    } else {
      results[[length(results) + 1L]] <- process_activity(
        activity_id = activity_plan$activity_id[[i]],
        expected_sample_count = activity_plan$expected_sample_count[[i]]
      )
    }
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

  if (mode == "staging_repair") {
    successful_staging_rows <- sum(
      results$inserted_rows[results$status == "SUCCESS"],
      na.rm = TRUE
    )

    if (successful_staging_rows == 0) {
      message(
        "Staging repair: no newly staged rows in this run; checking existing staging table."
      )
    }

    apply_staged_rows()

    if (isTRUE(created_stage_run)) {
      stage_run_status <- if (any(results$status == "FAILED")) {
        "FAILED"
      } else {
        "SUCCESS"
      }

      update_etl_run(
        connection = connection,
        run_id = run_id,
        run_status = stage_run_status
      )

      stage_run_completed <- TRUE
    }
  }

  invisible(results)
}
