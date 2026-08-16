project_file <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(project_file("R", "admin", "activity_achievement_evaluation_state.R"))

testthat::test_that("achievement input signature contains semantic inputs only", {
  rows <- data.frame(
    activity_id = bit64::as.integer64("1"),
    activity_date = as.Date("2026-08-01"),
    achievement_type = "power_best_effort",
    metric_name = "power_watts",
    duration_seconds = 300L,
    metric_value = 300
  )
  signature <- achievement_input_signature(
    "1", as.Date("2026-08-01"), rows, "achievement_v1", "best_v1"
  )
  testthat::expect_identical(
    signature,
    achievement_input_signature(
      "1", as.Date("2026-08-01"), rows, "achievement_v1", "best_v1"
    )
  )
  changed <- rows
  changed$metric_value <- 301
  testthat::expect_false(identical(
    signature,
    achievement_input_signature(
      "1", as.Date("2026-08-01"), changed, "achievement_v1", "best_v1"
    )
  ))
  testthat::expect_false(identical(
    signature,
    achievement_input_signature(
      "1", as.Date("2026-08-01"), rows, "achievement_v1", "best_v2"
    )
  ))
})

testthat::test_that("zero-achievement activities receive deterministic inputs and count zero", {
  base <- data.frame(
    activity_id = bit64::as.integer64("2"),
    activity_date_local = as.Date("2026-08-02")
  )
  inputs <- build_achievement_evaluation_inputs(
    base,
    source_rows = data.frame(
      activity_id = bit64::as.integer64(character()),
      activity_date = as.Date(character()),
      achievement_type = character(),
      metric_name = character(),
      duration_seconds = integer(),
      metric_value = numeric()
    ),
    calculation_version = "achievement_v1",
    best_effort_calculation_version = "best_v1"
  )
  testthat::expect_equal(nchar(inputs$input_signature), 64L)
  testthat::expect_equal(achievement_fact_counts(data.frame(), "2")[["2"]], 0L)
})

testthat::test_that("state-driven DAILY requires initialized state and trusted no-change context", {
  safe <- achievement_candidate_policy("daily", TRUE, TRUE, FALSE)
  testthat::expect_true(safe$use_state_daily)
  testthat::expect_identical(safe$candidate_mode, "evaluation_state")

  testthat::expect_identical(
    achievement_candidate_policy("daily", FALSE, TRUE, FALSE)$candidate_mode,
    "conservative_fallback"
  )
  testthat::expect_identical(
    achievement_candidate_policy("daily", TRUE, FALSE, FALSE)$candidate_mode,
    "conservative_fallback"
  )
  testthat::expect_identical(
    achievement_candidate_policy("daily", TRUE, TRUE, TRUE)$candidate_mode,
    "conservative_fallback"
  )
})

testthat::test_that("state initialization and calculation-version mismatch are explicit", {
  initialized <- data.frame(
    silver_count = 3, state_count = 3, current_count = 3,
    invalidated_count = 0, version_count = 1, other_version_count = 0
  )
  testthat::expect_true(achievement_evaluation_state_initialized(initialized))
  initialized$invalidated_count <- 1
  initialized$current_count <- 2
  testthat::expect_false(achievement_evaluation_state_initialized(initialized))

  mismatch <- initialized
  mismatch$silver_count <- 3
  mismatch$state_count <- 0
  mismatch$other_version_count <- 3
  testthat::expect_true(achievement_evaluation_version_requires_rebuild(mismatch))
})

testthat::test_that("signature candidate detection covers every stale state class", {
  inputs <- data.frame(
    activity_id = bit64::as.integer64(c("1", "2", "3", "4", "5")),
    activity_date_local = as.Date(rep("2026-08-01", 5)),
    input_signature = c("same", "changed", "same", "same", "same")
  )
  state <- data.frame(
    activity_id = bit64::as.integer64(c("1", "2", "3", "4")),
    input_signature = c("same", "old", "same", "same"),
    evaluation_status = c("CURRENT", "CURRENT", "INVALIDATED", "CURRENT"),
    source_best_effort_calculation_version = c("best_v1", "best_v1", "best_v1", "best_v0")
  )
  testthat::expect_setequal(
    achievement_signature_mismatch_ids(inputs, state, "best_v1"),
    c("2", "3", "4", "5")
  )
})

testthat::test_that("matching current signature is skipped", {
  inputs <- data.frame(
    activity_id = bit64::as.integer64("1"),
    input_signature = "same"
  )
  state <- data.frame(
    activity_id = bit64::as.integer64("1"),
    input_signature = "same",
    evaluation_status = "CURRENT",
    source_best_effort_calculation_version = "best_v1"
  )
  testthat::expect_length(
    achievement_signature_mismatch_ids(inputs, state, "best_v1"),
    0L
  )
})

testthat::test_that("historical and global changes retain conservative Phase 2 fallback", {
  historical <- achievement_candidate_policy("daily", TRUE, TRUE, TRUE)
  global_untrusted <- achievement_candidate_policy("daily", TRUE, FALSE, FALSE)
  testthat::expect_identical(historical$candidate_mode, "conservative_fallback")
  testthat::expect_identical(global_untrusted$candidate_mode, "conservative_fallback")
})

testthat::test_that("evaluation-state DDL preserves sparse facts and has no Silver foreign key", {
  ddl <- paste(readLines(
    project_file("sql", "admin", "090_create_activity_achievement_evaluation_state.sql")
  ), collapse = "\n")
  testthat::expect_match(ddl, "PRIMARY KEY (activity_id, calculation_version)", fixed = TRUE)
  testthat::expect_match(ddl, "'CURRENT', 'INVALIDATED'", fixed = TRUE)
  testthat::expect_false(grepl("FOREIGN KEY", ddl, fixed = TRUE))
})

testthat::test_that("achievement facts and state are written in one batch transaction", {
  transform <- paste(readLines(
    project_file("R", "transforms", "rebuild_gold_activity_achievements.R")
  ), collapse = "\n")
  transaction <- regmatches(
    transform,
    regexpr("DBI::dbBegin\\(connection\\)[\\s\\S]*?DBI::dbCommit\\(connection\\)", transform, perl = TRUE)
  )
  testthat::expect_match(transaction, "insert_gold_activity_achievements", fixed = TRUE)
  testthat::expect_match(transaction, "upsert_achievement_evaluation_state", fixed = TRUE)
  testthat::expect_match(transform, "DBI::dbRollback(connection)", fixed = TRUE)
  testthat::expect_match(
    transform,
    "run explicit backfill before REPAIR",
    fixed = TRUE
  )
})

testthat::test_that("semantic comparison reports business-key and value drift", {
  before <- data.frame(
    activity_achievement_key = c("a", "b"),
    activity_id = c("1", "2"),
    metric_value = c(100, 200),
    calculation_version = "v1"
  )
  testthat::expect_true(compare_achievement_fact_semantics(before, before)$equal)

  changed <- before
  changed$metric_value[[2]] <- 201
  comparison <- compare_achievement_fact_semantics(before, changed)
  testthat::expect_false(comparison$equal)
  testthat::expect_identical(comparison$mismatched, "b")

  removed <- before[1, , drop = FALSE]
  comparison <- compare_achievement_fact_semantics(before, removed)
  testthat::expect_identical(comparison$only_before, "b")
  testthat::expect_length(comparison$only_after, 0L)
})
