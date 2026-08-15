source("bootstrap.R")

config <- load_config()
args <- commandArgs(trailingOnly = TRUE)
execution_mode <- if (length(args) > 0L) tolower(args[[1]]) else "refresh"

if (length(args) == 2L) {
  run_mode <- "MANUAL"
  start_date <- as.Date(args[[1]])
  end_date <- as.Date(args[[2]])
} else if (execution_mode %in% c("refresh", "manual")) {
  run_mode <- "MANUAL"
  refresh_days <- config$ingestion$google_health_exercise_refresh_days %||% 14L
  start_date <- Sys.Date() - as.integer(refresh_days)
  end_date <- Sys.Date()
} else if (execution_mode == "backfill") {
  run_mode <- "BACKFILL"
  refresh_days <- config$ingestion$google_health_exercise_backfill_days %||% 365L
  start_date <- Sys.Date() - as.integer(refresh_days)
  end_date <- Sys.Date()
} else {
  stop(
    paste(
      "Unknown execution mode. Use 'refresh', 'manual', 'backfill',",
      "or provide explicit start_date end_date."
    ),
    call. = FALSE
  )
}

if (is.na(start_date) || is.na(end_date) || start_date > end_date) {
  stop("Provide a valid inclusive date window where start_date <= end_date.", call. = FALSE)
}
if (!isTRUE(config$sources$google_health$enabled)) {
  stop("Google Health source is not enabled in config/platform.yml.", call. = FALSE)
}

message("Checking Google Health authentication and scopes before Exercise ingestion.")
check_google_health_authentication(verbose = TRUE)

connection <- get_connection("cycling_platform_raw")
run_id <- create_etl_run(connection, source_id = 2L, run_mode = run_mode)
run_error <- NULL

tryCatch(
  {
    ingest_google_health_exercise(
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
  finally = DBI::dbDisconnect(connection)
)

if (!is.null(run_error)) {
  stop(run_error)
}
