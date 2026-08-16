source_gold_timing_helpers <- function() {
  helper_files <- c(
    file.path("R", "utils", "format_notification_helpers.R"),
    file.path("R", "utils", "gold_transform_timing.R")
  )

  for (helper_file in helper_files) {
    if (!file.exists(helper_file)) {
      helper_file <- file.path("..", "..", helper_file)
    }

    source(helper_file)
  }
}

testthat::test_that("Gold timing formats complete and zero-duration stages", {
  source_gold_timing_helpers()

  timing <- gold_transform_timing(
    entity_name = "activity_best_efforts",
    setup_seconds = 3,
    candidate_discovery_seconds = 354,
    processing_seconds = 1,
    finalisation_seconds = 0,
    total_seconds = 358
  )

  testthat::expect_equal(
    gold_transform_timing_accounted_seconds(timing),
    timing$total_seconds,
    tolerance = 0.01
  )
  testthat::expect_equal(
    format_gold_transform_timing(timing),
    paste(
      "setup 3s",
      "discovery 5m 54s",
      "processing 1s",
      "finalisation 0s",
      "total 5m 58s",
      sep = " · "
    )
  )
})

testthat::test_that("Gold timing omits unavailable optional stages", {
  source_gold_timing_helpers()

  timing <- gold_transform_timing(
    entity_name = "activity_best_efforts",
    setup_seconds = 0,
    processing_seconds = 1,
    total_seconds = 1
  )

  text <- format_gold_transform_timing(timing)

  testthat::expect_match(text, "setup 0s", fixed = TRUE)
  testthat::expect_match(text, "processing 1s", fixed = TRUE)
  testthat::expect_false(grepl("source preparation", text, fixed = TRUE))
  testthat::expect_false(grepl("discovery", text, fixed = TRUE))
})

testthat::test_that("achievement summary describes evaluated candidates", {
  source_gold_timing_helpers()

  line <- format_gold_transform_summary_line(
    entity_name = "activity_achievements",
    run_status = "SUCCESS",
    run_mode = "daily",
    activities_completed = 3527,
    activities_planned = 3527,
    rows_inserted = 0,
    rows_deleted = 0,
    timing = gold_transform_timing(
      entity_name = "activity_achievements",
      candidate_discovery_seconds = 2,
      source_preparation_seconds = 4,
      processing_seconds = 148,
      finalisation_seconds = 0,
      total_seconds = 154
    )
  )

  testthat::expect_match(
    line,
    "candidates evaluated 3527/3527",
    fixed = TRUE
  )
  testthat::expect_match(line, "rows changed +0 / -0", fixed = TRUE)
  testthat::expect_match(line, "source preparation 4s", fixed = TRUE)
  testthat::expect_false(grepl("3527/3527 activities", line, fixed = TRUE))
})

testthat::test_that("summary labels legacy Admin duration accurately", {
  source_gold_timing_helpers()

  line <- format_gold_transform_summary_line(
    entity_name = "activity_best_efforts",
    run_status = "SUCCESS",
    run_mode = "daily",
    activities_completed = 1,
    activities_planned = 1,
    rows_inserted = 30,
    rows_deleted = 30,
    recorded_duration_seconds = 1
  )

  testthat::expect_match(
    line,
    "recorded processing/finalisation 1s",
    fixed = TRUE
  )
})

testthat::test_that("Gold summary exposes affected-set discovery semantics", {
  source_gold_timing_helpers()
  timing <- gold_transform_timing(
    entity_name = "activity_best_efforts",
    candidate_discovery_seconds = 0,
    processing_seconds = 0,
    total_seconds = 0
  )
  timing$discovery_mode <- "skipped"
  timing$upstream_affected_count <- 0L
  timing$output_changed_activity_count <- 0L

  line <- format_gold_transform_summary_line(
    entity_name = "activity_best_efforts",
    run_status = "SUCCESS",
    run_mode = "daily",
    activities_completed = 0L,
    activities_planned = 0L,
    rows_inserted = 0L,
    rows_deleted = 0L,
    timing = timing
  )

  testthat::expect_match(line, "affected 0", fixed = TRUE)
  testthat::expect_match(line, "discovery skipped", fixed = TRUE)
  testthat::expect_match(line, "outputs changed 0", fixed = TRUE)
})

testthat::test_that("achievement summary exposes durable evaluation state", {
  source_gold_timing_helpers()
  timing <- gold_transform_timing(
    entity_name = "activity_achievements",
    candidate_discovery_seconds = 0,
    processing_seconds = 0,
    total_seconds = 0
  )
  timing$candidate_mode <- "evaluation_state"
  timing$evaluation_debt_count <- 0L
  timing$evaluation_state_rows_written <- 0L
  timing$zero_achievement_evaluations <- 0L
  line <- format_gold_transform_summary_line(
    entity_name = "activity_achievements",
    run_status = "SUCCESS",
    run_mode = "daily",
    activities_completed = 0L,
    activities_planned = 0L,
    rows_inserted = 0L,
    rows_deleted = 0L,
    timing = timing
  )
  testthat::expect_match(line, "evaluation debt 0", fixed = TRUE)
  testthat::expect_match(line, "candidates evaluated 0/0", fixed = TRUE)
  testthat::expect_match(line, "candidate mode evaluation_state", fixed = TRUE)
})
