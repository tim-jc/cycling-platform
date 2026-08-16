source("bootstrap.R")

config <- load_config()
calculation_version <- gold_activity_achievements_calculation_version(config)
connection <- get_connection("cycling_platform_admin")
args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args) == 0L) "summary" else tolower(args[[1]])
snapshot_path <- if (length(args) >= 2L) args[[2]] else NA_character_

if (!mode %in% c("summary", "snapshot", "compare")) {
  stop("Use summary, snapshot <path>, or compare <path>.", call. = FALSE)
}
if (mode %in% c("snapshot", "compare") && (is.na(snapshot_path) || !nzchar(snapshot_path))) {
  stop(mode, " requires a snapshot path.", call. = FALSE)
}

tryCatch(
  {
    summary <- achievement_evaluation_state_summary(connection, calculation_version)
    audit <- audit_achievement_evaluation_candidates(connection, calculation_version)
    facts <- fetch_achievement_fact_semantic_rows(connection)
    fact_signature <- achievement_fact_semantic_signature(connection)
    achievement_activity_count <- length(unique(as.character(facts$activity_id)))

    message("Achievement evaluation-state audit")
    message("Calculation version: ", calculation_version)
    message("Sparse facts: ", nrow(facts))
    message("Activities with achievements: ", achievement_activity_count)
    message(
      "CURRENT zero-achievement activities: ",
      summary$current_count[[1]] - achievement_activity_count
    )
    message("Sparse fact semantic signature: ", fact_signature)
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

    if (identical(mode, "snapshot")) {
      saveRDS(
        list(
          captured_at = Sys.time(),
          calculation_version = calculation_version,
          semantic_signature = fact_signature,
          facts = facts,
          state_summary = summary
        ),
        snapshot_path
      )
      message("Semantic snapshot written: ", normalizePath(snapshot_path))
    }

    if (identical(mode, "compare")) {
      snapshot <- readRDS(snapshot_path)
      if (!identical(snapshot$calculation_version, calculation_version)) {
        stop("Snapshot calculation version differs from the active version.", call. = FALSE)
      }
      comparison <- compare_achievement_fact_semantics(snapshot$facts, facts)
      message("Compared rows before/after: ", comparison$before_count, "/", comparison$after_count)
      message("Only before rebuild: ", length(comparison$only_before))
      message("Only after rebuild: ", length(comparison$only_after))
      message("Semantic value mismatches: ", length(comparison$mismatched))
      message("Semantic equality: ", if (comparison$equal) "PASS" else "FAIL")
      if (!comparison$equal) {
        stop("Achievement semantic equivalence failed; investigate before continuing.", call. = FALSE)
      }
    }
  },
  finally = {
    if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection)
  }
)
