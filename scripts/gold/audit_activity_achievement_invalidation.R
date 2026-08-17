source("bootstrap.R")

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || is.na(as.Date(args[[1]]))) {
  stop(
    "Provide one dependency start date: YYYY-MM-DD.",
    call. = FALSE
  )
}

dependency_start_date <- as.Date(args[[1]])
config <- load_config()
calculation_version <- gold_activity_achievements_calculation_version(config)
connection <- get_connection("cycling_platform_admin")

tryCatch(
  {
    closure_ids <- get_achievement_closure_activity_ids(
      connection,
      dependency_start_date
    )
    boundary <- achievement_history_boundary(connection, calculation_version)
    message("Achievement historical-invalidation audit (read only)")
    message("Calculation version: ", calculation_version)
    message("Current history boundary: ", boundary$activity_date_local, " / ", boundary$activity_id)
    message("Proposed dependency start date: ", dependency_start_date)
    message("Proposed inclusive closure: ", length(closure_ids), " activities")
    message("Current sparse-fact signature: ", achievement_fact_semantic_signature(connection))
  },
  finally = {
    if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection)
  }
)
