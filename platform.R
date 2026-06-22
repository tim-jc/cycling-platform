#load all functions
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

execution_mode <- "manual"

if (length(args) > 0) {
  execution_mode <- tolower(args[[1]])
}

if (!execution_mode %in% c("manual", "backfill")) {
  stop(
    "Unknown execution mode. Use 'manual' or 'backfill'.",
    call. = FALSE
  )
}

if (execution_mode == "backfill") {
  run_mode <- "BACKFILL"
  activity_refresh_days <- config$ingestion$activity_backfill_days
} else {
  run_mode <- "MANUAL"
  activity_refresh_days <- config$ingestion$activity_refresh_days
}

connection <- get_connection(
  database_name = "cycling_platform_raw"
)

run_id <- create_etl_run(
  connection = connection,
  source_id = 1L,
  run_mode = run_mode
)

tryCatch(
  {
    ingest_activities(
      connection = connection,
      run_id = run_id,
      source_id = 1L,
      refresh_days = activity_refresh_days,
      config = config
    )

    stream_activity_ids <- get_pending_stream_activity_ids(
      connection = connection
    )

    if (length(stream_activity_ids) == 0) {
      message(
        "No activities require stream ingestion."
      )
    } else {
      ingest_streams(
        connection = connection,
        run_id = run_id,
        source_id = 1L,
        activity_ids = stream_activity_ids,
        config = config
      )
    }

    detail_activity_ids <- get_pending_detail_activity_ids(
      connection = connection
    )

    if (length(detail_activity_ids) == 0) {
      message(
        "No activities require detail ingestion."
      )
    } else {
      ingest_activity_details(
        connection = connection,
        run_id = run_id,
        source_id = 1L,
        activity_ids = detail_activity_ids,
        config = config
      )
    }

    update_etl_run(
      connection = connection,
      run_id = run_id,
      run_status = "SUCCESS"
    )
  },

  error = function(e) {
    update_etl_run(
      connection = connection,
      run_id = run_id,
      run_status = "FAILED",
      error_message = conditionMessage(e)
    )

    stop(e)
  },

  finally = {
    DBI::dbDisconnect(connection)
  }
)

send_notification(
  run_id = run_id
)
