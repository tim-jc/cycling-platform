progress_helpers <- function() {
  path <- file.path("R", "utils", "silver_stream_progress.R")
  if (!file.exists(path)) path <- file.path("..", "..", path)
  source(path)
}
progress_helpers()

batch_history_fixture <- function(n = 5L, duration = 10, rows = 100) {
  data.frame(
    batch_index = seq_len(n),
    activities = rep(1L, n),
    expected_rows = rep(rows, n),
    rows_inserted = rep(rows, n),
    rows_deleted = rep(0, n),
    duration_seconds = rep(duration, n)
  )
}

testthat::test_that("durations are concise and human readable", {
  testthat::expect_equal(format_silver_stream_duration(48), "48s")
  testthat::expect_equal(format_silver_stream_duration(734), "12m 14s")
  testthat::expect_equal(format_silver_stream_duration(3780), "1h 03m 00s")
  testthat::expect_equal(format_silver_stream_duration(12702), "3h 31m 42s")
})

testthat::test_that("progress prefers expected rows", {
  progress <- silver_stream_progress_basis(300, 1000, 8, 10, 8, 10)
  testthat::expect_equal(progress$basis, "expected_rows")
  testthat::expect_equal(progress$fraction, 0.3)
})

testthat::test_that("progress falls back to activities then batches", {
  activities <- silver_stream_progress_basis(0, 0, 4, 10, 8, 10)
  batches <- silver_stream_progress_basis(NA, NA, 0, 0, 8, 10)
  testthat::expect_equal(activities$basis, "activities")
  testthat::expect_equal(activities$fraction, 0.4)
  testthat::expect_equal(batches$basis, "batches")
  testthat::expect_equal(batches$fraction, 0.8)
})

testthat::test_that("ETA warms up before selecting rolling rate", {
  progress <- silver_stream_progress_basis(500, 1000, 5, 10, 5, 10)
  warmup <- calculate_silver_stream_eta(40, progress, batch_history_fixture(4))
  rolling <- calculate_silver_stream_eta(60, progress, batch_history_fixture(5))
  testthat::expect_false(warmup$warmed_up)
  testthat::expect_equal(warmup$seconds, 40)
  testthat::expect_true(rolling$warmed_up)
  testthat::expect_equal(rolling$method, "rolling")
  testthat::expect_equal(rolling$seconds, 50)
})

testthat::test_that("completed progress has zero ETA", {
  progress <- silver_stream_progress_basis(1000, 1000, 10, 10, 10, 10)
  eta <- calculate_silver_stream_eta(100, progress, batch_history_fixture(10))
  testthat::expect_equal(eta$method, "complete")
  testthat::expect_equal(eta$seconds, 0)
})

testthat::test_that("warm-up output suppresses ETA and projected finish", {
  history <- batch_history_fixture(2)
  progress <- silver_stream_progress_basis(200, 1000, 2, 10, 2, 10)
  eta <- calculate_silver_stream_eta(20, progress, history)
  output <- format_silver_stream_progress(2, 10, 2, 10, 200, 1000, 200, 0, 20, eta, history)
  testthat::expect_match(output, "ETA: calculating...", fixed = TRUE)
  testthat::expect_match(output, "Projected finish: calculating...", fixed = TRUE)
})

testthat::test_that("rolling output includes estimated projected finish", {
  history <- batch_history_fixture()
  progress <- silver_stream_progress_basis(500, 1000, 5, 10, 5, 10)
  eta <- calculate_silver_stream_eta(60, progress, history)
  output <- format_silver_stream_progress(5, 10, 5, 10, 500, 1000, 500, 0, 60, eta, history, as.POSIXct("2026-08-01 20:00:00", tz = "Europe/London"))
  testthat::expect_match(output, "ETA: 50s (rolling)", fixed = TRUE)
  testthat::expect_match(output, "Projected finish: 20:00 BST (estimate)", fixed = TRUE)
})

testthat::test_that("slow batch detection uses a robust floor and history", {
  testthat::expect_false(is_slow_silver_stream_batch(60, numeric()))
  testthat::expect_true(is_slow_silver_stream_batch(61, numeric()))
  testthat::expect_false(is_slow_silver_stream_batch(89, rep(30, 5)))
  testthat::expect_true(is_slow_silver_stream_batch(91, rep(30, 5)))
})

testthat::test_that("throughput trend identifies improving and degrading rates", {
  improving <- batch_history_fixture(6, duration = 10, rows = 100)
  improving$rows_inserted <- c(100, 100, 100, 130, 130, 130)
  degrading <- improving
  degrading$rows_inserted <- rev(improving$rows_inserted)
  testthat::expect_equal(silver_stream_throughput_trend(improving), "improving")
  testthat::expect_equal(silver_stream_throughput_trend(degrading), "degrading")
})

testthat::test_that("low-level diagnostics require DEBUG logging", {
  testthat::expect_silent(silver_stream_debug("chunk detail", log_level = "INFO"))
  testthat::expect_message(silver_stream_debug("chunk detail", log_level = "DEBUG"), "chunk detail")
})

testthat::test_that("completion and failure summaries retain operational metrics", {
  history <- batch_history_fixture()
  complete <- format_silver_stream_completion_summary(
    status = "COMPLETE", activities_processed = 5, rows_inserted = 500,
    rows_deleted = 10, elapsed_seconds = 50, batch_history = history
  )
  failed <- format_silver_stream_completion_summary(
    status = "FAILED", activities_processed = 3, rows_inserted = 300,
    rows_deleted = 0, elapsed_seconds = 35, batch_history = history[1:3, ],
    failed_batches = 1, error_message = "database unavailable"
  )
  testthat::expect_match(complete, "Average throughput: 10.0 rows/sec", fixed = TRUE)
  testthat::expect_match(complete, "Slowest batches:", fixed = TRUE)
  testthat::expect_match(complete, "Failed batches: 0", fixed = TRUE)
  testthat::expect_match(failed, "Silver stream rebuild failed", fixed = TRUE)
  testthat::expect_match(failed, "Activities processed: 3", fixed = TRUE)
  testthat::expect_match(failed, "Error: database unavailable", fixed = TRUE)
})

testthat::test_that("final Silver notification includes stream throughput and failures", {
  root <- if (file.exists("run_daily_platform.R")) "." else file.path("..", "..")
  source_text <- paste(readLines(file.path(root, "run_daily_platform.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(source_text, "AS failed_batches", fixed = TRUE)
  testthat::expect_match(source_text, "rows_inserted / duration_seconds", fixed = TRUE)
  testthat::expect_match(source_text, "failed {failed_batches}", fixed = TRUE)
})
