source("bootstrap.R")

args <- commandArgs(
  trailingOnly = TRUE
)

dry_run <- "--dry-run" %in% args

connection <- get_connection("mysql")

backfill_error <- NULL
backfill_results <- NULL

tryCatch(
  {
    backfill_results <- backfill_google_health_daily_source_provenance(
      connection = connection,
      dry_run = dry_run
    )

    print(backfill_results)
  },
  error = function(e) {
    backfill_error <<- e
  },
  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)

if (!is.null(backfill_error)) {
  stop(backfill_error)
}

if (isTRUE(dry_run)) {
  message("Google Health daily source provenance dry run complete.")
} else {
  message("Google Health daily source provenance backfill complete.")
}
