project_file <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(project_file("R", "admin", "activity_achievement_evaluation_state.R"))
source(project_file("R", "transforms", "rebuild_gold_activity_achievements.R"))

context_validation_fixture <- function(rows, trusted = TRUE, status = "COMPLETE") {
  list(
    trusted = trusted,
    status = status,
    context = list(activities = rows)
  )
}

change_rows_fixture <- function(
  activity_id,
  change_type = "update",
  before = "2026-01-01",
  after = before,
  activities_changed = TRUE,
  streams_changed = FALSE,
  power_changed = FALSE
) {
  before_date <- as.Date(before)
  after_date <- as.Date(after)
  dates <- c(before_date, after_date)
  dates <- dates[!is.na(dates)]
  data.frame(
    activity_id = bit64::as.integer64(activity_id),
    change_type = change_type,
    activity_date_before = before_date,
    activity_date_after = after_date,
    silver_activities_changed = activities_changed,
    silver_streams_changed = streams_changed,
    power_classification_changed = power_changed,
    dependency_start_date = if (length(dates)) min(dates) else as.Date(NA)
  )
}

history_boundary_fixture <- function(date = "2026-03-01", id = "300") {
  list(activity_date_local = as.Date(date), activity_id = id)
}

testthat::test_that("no-change and stream-only unchanged-output runs remain empty", {
  empty <- change_rows_fixture("1")[0, ]
  plan <- plan_achievement_daily_invalidation(
    context_validation_fixture(empty), character(), history_boundary_fixture()
  )
  testthat::expect_identical(plan$action, "no_change")

  stream_only <- change_rows_fixture(
    "200", activities_changed = FALSE, streams_changed = TRUE
  )
  plan <- plan_achievement_daily_invalidation(
    context_validation_fixture(stream_only), character(), history_boundary_fixture()
  )
  testthat::expect_identical(plan$action, "no_change")
})

testthat::test_that("one or several pure latest inserts use the append fast path", {
  one <- change_rows_fixture(
    "400", "insert", before = NA_character_, after = "2026-04-01"
  )
  plan <- plan_achievement_daily_invalidation(
    context_validation_fixture(one), "400", history_boundary_fixture()
  )
  testthat::expect_identical(plan$action, "latest_append")
  testthat::expect_identical(plan$direct_activity_ids, "400")
  testthat::expect_length(
    achievement_unexpected_debt_ids(plan, "400"),
    0L
  )
  testthat::expect_identical(
    achievement_unexpected_debt_ids(plan, c("400", "200")),
    "200"
  )

  several <- rbind(
    change_rows_fixture("500", "insert", before = NA_character_, after = "2026-05-02"),
    change_rows_fixture("400", "insert", before = NA_character_, after = "2026-05-01")
  )
  plan <- plan_achievement_daily_invalidation(
    context_validation_fixture(several), c("400", "500"), history_boundary_fixture()
  )
  testthat::expect_identical(plan$action, "latest_append")
  testthat::expect_identical(plan$direct_activity_ids, c("400", "500"))
})

testthat::test_that("historical inserts and same-date tie ordering form a closure", {
  insertion <- change_rows_fixture(
    "150", "insert", before = NA_character_, after = "2026-02-01"
  )
  plan <- plan_achievement_daily_invalidation(
    context_validation_fixture(insertion), "150", history_boundary_fixture()
  )
  testthat::expect_identical(plan$action, "historical_closure")
  testthat::expect_identical(plan$invalidation_reason, "HISTORICAL_INSERT")
  testthat::expect_equal(plan$dependency_start_date, as.Date("2026-02-01"))

  base <- data.frame(
    activity_id = bit64::as.integer64(c("9", "10", "11", "12")),
    activity_date_local = as.Date(c(
      "2026-01-31", "2026-02-01", "2026-02-01", "2026-02-02"
    ))
  )
  testthat::expect_identical(
    achievement_closure_ids_from_activity_base(base, as.Date("2026-02-01")),
    c("10", "11", "12")
  )
})

testthat::test_that("date movement uses the earlier local date", {
  later <- change_rows_fixture("200", before = "2026-02-01", after = "2026-02-20")
  earlier <- change_rows_fixture("200", before = "2026-02-20", after = "2026-02-01")
  for (rows in list(later, earlier)) {
    plan <- plan_achievement_daily_invalidation(
      context_validation_fixture(rows), character(), history_boundary_fixture()
    )
    testthat::expect_identical(plan$invalidation_reason, "DATE_CHANGE")
    testthat::expect_equal(plan$dependency_start_date, as.Date("2026-02-01"))
  }
})

testthat::test_that("multiple changes use their minimum dependency date", {
  rows <- rbind(
    change_rows_fixture("200", before = "2026-02-10"),
    change_rows_fixture("100", before = "2026-01-10")
  )
  plan <- plan_achievement_daily_invalidation(
    context_validation_fixture(rows), character(), history_boundary_fixture()
  )
  testthat::expect_equal(plan$dependency_start_date, as.Date("2026-01-10"))
})

testthat::test_that("actual best-effort and enumerated power changes invalidate", {
  stream <- change_rows_fixture(
    "200", activities_changed = FALSE, streams_changed = TRUE
  )
  best <- plan_achievement_daily_invalidation(
    context_validation_fixture(stream), "200", history_boundary_fixture()
  )
  testthat::expect_identical(best$invalidation_reason, "BEST_EFFORT_CHANGE")

  power <- change_rows_fixture(
    "200", activities_changed = FALSE, power_changed = TRUE
  )
  power_plan <- plan_achievement_daily_invalidation(
    context_validation_fixture(power), character(), history_boundary_fixture()
  )
  testthat::expect_identical(
    power_plan$invalidation_reason,
    "POWER_ELIGIBILITY_CHANGE"
  )
})

testthat::test_that("untrusted and deletion contexts require safe fallback", {
  rows <- change_rows_fixture("200")
  untrusted <- plan_achievement_daily_invalidation(
    context_validation_fixture(rows, FALSE, "UNTRUSTED"),
    character(),
    history_boundary_fixture()
  )
  testthat::expect_identical(untrusted$action, "fallback")

  rows$change_type <- "delete_or_exclude"
  deletion <- plan_achievement_daily_invalidation(
    context_validation_fixture(rows), character(), history_boundary_fixture()
  )
  testthat::expect_identical(deletion$action, "fallback")

  classification <- context_validation_fixture(rows, FALSE, "UNTRUSTED")
  classification$reason <- "Global power-classification control changed."
  global <- plan_achievement_daily_invalidation(
    classification, character(), history_boundary_fixture()
  )
  testthat::expect_match(global$reason, "classification")
})

achievement_source_fixture <- function(values) {
  data.frame(
    activity_id = bit64::as.integer64(c("1", "2", "3")),
    activity_date = as.Date(c("2026-01-01", "2026-02-01", "2026-03-01")),
    achievement_type = "power_best_effort",
    metric_name = "power_watts",
    duration_seconds = 300L,
    metric_value = values
  )
}

semantic_achievement_rows <- function(rows) {
  rows[, c(
    "activity_achievement_key", "activity_id", "achievement_type", "metric_name",
    "duration_seconds", "comparison_scope", "comparison_period_start",
    "comparison_period_end", "achievement_rank", "metric_value",
    "previous_best_value", "previous_best_activity_id", "previous_best_date",
    "days_since_previous_best", "achievement_title", "achievement_detail",
    "calculation_status", "calculation_version"
  ), drop = FALSE]
}

incremental_closure_facts <- function(initial_source, changed_source, closure_ids) {
  initial <- compute_activity_achievements(
    initial_source, as.character(initial_source$activity_id), "v1"
  )
  replacement <- compute_activity_achievements(changed_source, closure_ids, "v1")
  retained <- initial[!as.character(initial$activity_id) %in% closure_ids, , drop = FALSE]
  rbind(retained, replacement)
}

testthat::test_that("upward historical correction equals full rebuild truth", {
  initial <- achievement_source_fixture(c(300, 310, 320))
  changed <- achievement_source_fixture(c(315, 310, 320))
  incremental <- incremental_closure_facts(initial, changed, c("1", "2", "3"))
  rebuilt <- compute_activity_achievements(changed, c("1", "2", "3"), "v1")
  comparison <- compare_achievement_fact_semantics(
    semantic_achievement_rows(incremental), semantic_achievement_rows(rebuilt)
  )
  testthat::expect_true(comparison$equal)
  testthat::expect_false("2" %in% as.character(rebuilt$activity_id))
  testthat::expect_true("3" %in% as.character(rebuilt$activity_id))
})

testthat::test_that("downward historical correction equals full rebuild truth", {
  initial <- achievement_source_fixture(c(315, 310, 320))
  changed <- achievement_source_fixture(c(300, 310, 320))
  incremental <- incremental_closure_facts(initial, changed, c("1", "2", "3"))
  rebuilt <- compute_activity_achievements(changed, c("1", "2", "3"), "v1")
  comparison <- compare_achievement_fact_semantics(
    semantic_achievement_rows(incremental), semantic_achievement_rows(rebuilt)
  )
  testthat::expect_true(comparison$equal)
  testthat::expect_true("2" %in% as.character(rebuilt$activity_id))
  testthat::expect_true("3" %in% as.character(rebuilt$activity_id))
})

testthat::test_that("closure is durably invalidated before batch processing", {
  transform <- paste(readLines(
    project_file("R", "transforms", "rebuild_gold_activity_achievements.R")
  ), collapse = "\n")
  invalidation <- regexpr(
    "mark_achievement_evaluation_closure_invalidated", transform, fixed = TRUE
  )[[1]]
  processing <- regexpr("purrr::iwalk", transform, fixed = TRUE)[[1]]
  testthat::expect_gt(invalidation, 0L)
  testthat::expect_lt(invalidation, processing)
  testthat::expect_match(transform, "remaining_invalidated_count", fixed = TRUE)
})

testthat::test_that("Gold orchestration passes actual best-effort output changes", {
  orchestration <- paste(readLines(
    project_file("R", "transforms", "run_gold_transformations.R")
  ), collapse = "\n")
  metadata_position <- regexpr(
    "best_effort_metadata <- attr", orchestration, fixed = TRUE
  )[[1]]
  achievement_position <- regexpr(
    "achievement_result <- rebuild_gold_activity_achievements", orchestration,
    fixed = TRUE
  )[[1]]
  testthat::expect_gt(metadata_position, 0L)
  testthat::expect_lt(metadata_position, achievement_position)
  testthat::expect_match(
    orchestration,
    "best_effort_changed_activity_ids =",
    fixed = TRUE
  )
  testthat::expect_match(
    orchestration,
    "best_effort_metadata$output_changed_activity_ids",
    fixed = TRUE
  )
})
