# run_gold_activity_achievements.R
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

mode <- "repair"

if (length(args) > 0) {
  mode <- tolower(args[[1]])
}

if (!mode %in% c("daily", "repair", "backfill")) {
  stop(
    "Unknown gold activity achievements mode. Use 'daily', 'repair' or 'backfill'.",
    call. = FALSE
  )
}

connection <- get_connection("mysql")

tryCatch(
  {
    validation_results <- rebuild_gold_activity_achievements(
      connection = connection,
      config = config,
      mode = mode
    )

    message("Gold activity achievements validation results:")
    print(validation_results)
  },
  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)
