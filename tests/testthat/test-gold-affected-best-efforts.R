project_file <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(project_file("R", "transforms", "rebuild_gold_activity_best_efforts.R"))
source(project_file("R", "transforms", "rebuild_silver_activity_streams.R"))

testthat::test_that("direct best-effort plan preserves explicit affected IDs", {
  plan <- direct_best_effort_activity_plan(c("3", "1", "3"))
  testthat::expect_equal(as.character(plan$activity_id), c("3", "1"))
  testthat::expect_true(all(plan$repair_reason == "affected_set"))
  testthat::expect_equal(nrow(direct_best_effort_activity_plan(character())), 0L)

  planned <- get_best_effort_activity_plan(
    connection = structure(list(), class = "must-not-query"),
    mode = "daily",
    activity_ids = c("9", "10"),
    metrics = "watts",
    durations = 5L,
    calculation_version = "v1"
  )
  testthat::expect_equal(as.character(planned$activity_id), c("9", "10"))
})

testthat::test_that("same stream row count with changed values is material", {
  before <- data.frame(
    activity_id = rep(1, 3),
    sample_index = 1:3,
    watts = c(100L, 200L, 300L)
  )
  after <- before
  after$watts[[2]] <- 250L

  testthat::expect_equal(nrow(before), nrow(after))
  testthat::expect_false(
    identical(silver_stream_rows_hash(before), silver_stream_rows_hash(after))
  )
})

testthat::test_that("stream addition and removal are material", {
  empty <- data.frame()
  populated <- data.frame(activity_id = 1, sample_index = 1L, watts = 200L)
  testthat::expect_false(identical(
    silver_stream_rows_hash(empty),
    silver_stream_rows_hash(populated)
  ))
  testthat::expect_false(identical(
    silver_stream_rows_hash(populated),
    silver_stream_rows_hash(empty)
  ))
})

testthat::test_that("affected-set calculation matches broad calculation", {
  streams <- data.frame(
    activity_id = rep(c(1, 2), each = 5),
    sample_index = rep(1:5, 2),
    time_seconds = rep(0:4, 2),
    distance_metres = rep(seq(0, 40, by = 10), 2),
    latitude = NA_real_,
    longitude = NA_real_,
    watts = c(100, 200, 300, 400, 500, 50, 60, 70, 80, 90)
  )
  broad <- do.call(rbind, lapply(split(streams, streams$activity_id), function(rows) {
    compute_activity_best_efforts(rows, metrics = "watts", durations = 2L)
  }))
  affected <- compute_activity_best_efforts(
    streams[streams$activity_id == 2, , drop = FALSE],
    metrics = "watts",
    durations = 2L
  )
  broad_activity <- broad[broad$activity_id == 2, , drop = FALSE]
  testthat::expect_identical(
    best_effort_output_signature(broad_activity),
    best_effort_output_signature(affected)
  )
})

testthat::test_that("best-effort output signatures ignore computed timestamp", {
  rows <- data.frame(
    activity_id = bit64::as.integer64("1"),
    metric_name = "watts",
    duration_seconds = 5L,
    peak_value = 300,
    computed_at = as.POSIXct("2026-08-01 01:00:00", tz = "UTC")
  )
  later <- rows
  later$computed_at <- as.POSIXct("2026-08-02 01:00:00", tz = "UTC")
  changed <- later
  changed$peak_value <- 301

  testthat::expect_identical(
    best_effort_output_signature(rows),
    best_effort_output_signature(later)
  )
  testthat::expect_false(identical(
    best_effort_output_signature(rows),
    best_effort_output_signature(changed)
  ))
})

testthat::test_that("actual changed activities exclude equivalent output", {
  existing <- data.frame(
    activity_id = bit64::as.integer64(c("1", "2")),
    metric_name = c("watts", "watts"),
    duration_seconds = c(5L, 5L),
    peak_value = c(300, 250),
    computed_at = as.POSIXct(c("2026-08-01", "2026-08-01"), tz = "UTC")
  )
  proposed <- existing
  proposed$computed_at <- as.POSIXct(c("2026-08-02", "2026-08-02"), tz = "UTC")
  proposed$peak_value[[2]] <- 275

  testthat::expect_equal(
    as.character(best_effort_changed_activity_ids(existing, proposed, c("1", "2"))),
    "2"
  )
})
