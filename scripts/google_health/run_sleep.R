source("bootstrap.R")

config <- load_config()

args <- commandArgs(trailingOnly = TRUE)

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

if (is.null(config$sources$google_health$enabled) ||
    !isTRUE(config$sources$google_health$enabled)) {
  stop(
    "Google Health source is not enabled in config/platform.yml.",
    call. = FALSE
  )
}

if (execution_mode == "backfill") {
  run_mode <- "BACKFILL"
  refresh_days <- config$ingestion$google_health_sleep_backfill_days
} else {
  run_mode <- "MANUAL"
  refresh_days <- config$ingestion$google_health_sleep_refresh_days
}

if (is.null(refresh_days)) {
  refresh_days <- 7L
}

start_date <- Sys.Date() - as.integer(refresh_days)
end_date <- Sys.Date()

connection <- get_connection(database_name = "cycling_platform_raw")

run_id <- create_etl_run(
  connection = connection,
  source_id = 2L,
  run_mode = run_mode
)

run_error <- NULL

tryCatch(
  {
    ingest_google_health_sleep_logs(
      connection = connection,
      run_id = run_id,
      source_id = 2L,
      config = config,
      start_date = start_date,
      end_date = end_date
    )

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

    run_error <<- e
  },

  finally = {
    DBI::dbDisconnect(connection)
  }
)

if (!is.null(run_error)) {
  stop(run_error)
}
