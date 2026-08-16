project_file <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(project_file("R", "utils", "gold_change_context.R"))
source(project_file("R", "transforms", "run_silver_transformations.R"))

gold_context_row <- function(activity_id = "1") {
  data.frame(
    activity_id = bit64::as.integer64(activity_id),
    change_type = "update",
    activity_date_before = as.Date("2026-08-01"),
    activity_date_after = as.Date("2026-08-01"),
    silver_activities_changed = FALSE,
    silver_streams_changed = TRUE,
    power_classification_changed = FALSE,
    dependency_start_date = as.Date("2026-08-01")
  )
}

testthat::test_that("trusted empty context is distinct from missing context", {
  complete <- new_gold_change_context(status = "COMPLETE")
  testthat::expect_true(validate_gold_change_context(complete)$trusted)
  testthat::expect_length(gold_best_effort_affected_ids(complete), 0L)

  missing <- validate_gold_change_context(NULL)
  testthat::expect_false(missing$trusted)
  testthat::expect_identical(missing$status, "UNAVAILABLE")
  testthat::expect_null(gold_best_effort_affected_ids(NULL))
})

testthat::test_that("complete context selects only best-effort input changes", {
  rows <- rbind(
    gold_context_row("1"),
    transform(gold_context_row("2"), silver_streams_changed = FALSE,
              silver_activities_changed = TRUE),
    transform(gold_context_row("3"), silver_streams_changed = FALSE,
              power_classification_changed = TRUE)
  )
  context <- new_gold_change_context(status = "COMPLETE", activities = rows)
  testthat::expect_equal(
    as.character(gold_best_effort_affected_ids(context)),
    c("1", "3")
  )
})

testthat::test_that("unavailable and untrusted contexts require fallback", {
  unavailable <- unavailable_gold_change_context("raw summary unavailable")
  untrusted <- new_gold_change_context(
    status = "UNTRUSTED",
    activities = gold_context_row(),
    reason = "global classification changed"
  )
  testthat::expect_null(gold_best_effort_affected_ids(unavailable))
  testthat::expect_null(gold_best_effort_affected_ids(untrusted))
})

testthat::test_that("invalid context cannot become trusted empty context", {
  rows <- rbind(gold_context_row("1"), gold_context_row("1"))
  testthat::expect_error(
    new_gold_change_context(status = "COMPLETE", activities = rows),
    "duplicate activity IDs"
  )

  bad_date <- gold_context_row()
  bad_date$dependency_start_date <- as.Date("2026-08-02")
  testthat::expect_error(
    new_gold_change_context(status = "COMPLETE", activities = bad_date),
    "inconsistent dependency dates"
  )
})

testthat::test_that("Silver snapshots report only material Gold input changes", {
  before <- data.frame(
    activity_id = bit64::as.integer64(c("1", "2")),
    start_date_local = as.Date(c("2026-08-01", "2026-08-02")),
    distance_metres = c(1000, 2000),
    moving_time_seconds = c(100, 200),
    elevation_gain_metres = c(10, 20),
    power_source_type = c("measured", "measured"),
    is_power_record_eligible = c(1L, 1L),
    power_record_exclusion_reason = c(NA, NA),
    power_classification_version = c("v1", "v1")
  )
  after <- before
  after$distance_metres[[2]] <- 2100

  rows <- build_gold_change_rows(
    activity_ids = c("1", "2"),
    activities_before = before,
    activities_after = after,
    stream_changed_ids = bit64::as.integer64(character())
  )
  testthat::expect_equal(as.character(rows$activity_id), "2")
  testthat::expect_true(rows$silver_activities_changed[[1]])
  testthat::expect_false(rows$silver_streams_changed[[1]])
})
