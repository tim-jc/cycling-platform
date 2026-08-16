source("bootstrap.R")

config <- load_config()
calculation_version <- gold_activity_achievements_calculation_version(config)
connection <- get_connection("cycling_platform_admin")

tryCatch(
  {
    ensure_activity_achievement_evaluation_state(connection)
    summary <- achievement_evaluation_state_summary(connection, calculation_version)
    audit <- audit_achievement_evaluation_candidates(connection, calculation_version)

    message("Achievement evaluation-state audit")
    message("Calculation version: ", calculation_version)
    message("Sparse fact semantic signature: ", achievement_fact_semantic_signature(connection))
    message("Silver activities: ", summary$silver_count[[1]])
    message("CURRENT state rows: ", summary$current_count[[1]])
    message("INVALIDATED state rows: ", summary$invalidated_count[[1]])
    message("Conservative candidates: ", audit$conservative_candidate_count)
    message("State-driven candidates: ", audit$state_candidate_count)
    message(
      "Previously recurring conservative-only candidates: ",
      length(audit$selected_only_by_conservative)
    )
    message("State-only repair candidates: ", length(audit$selected_only_by_state))
  },
  finally = {
    if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection)
  }
)
