# run_gold_activity_best_efforts.R
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

mode <- "repair"

if (length(args) > 0) {
  mode <- tolower(args[[1]])
}

if (!mode %in% c("repair", "backfill")) {
  stop(
    "Unknown gold activity best efforts mode. Use 'repair' or 'backfill'.",
    call. = FALSE
  )
}

connection <- get_connection("cycling_platform_admin")

tryCatch(
  {
    validation_results <- rebuild_gold_activity_best_efforts(
      connection = connection,
      config = config,
      mode = mode
    )

    message("Gold activity best efforts validation results:")
    print(validation_results)
  },
  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)
