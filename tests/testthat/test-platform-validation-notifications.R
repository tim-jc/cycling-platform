source_validation_notification_files <- function() {
  files <- list(
    file.path(
      "R",
      "utils",
      "format_notification_helpers.R"
    ),
    file.path(
      "R",
      "validation",
      "summarize_platform_validation.R"
    ),
    file.path(
      "R",
      "utils",
      "send_platform_validation_notification.R"
    )
  )

  purrr::walk(
    files,
    \(file) {
      if (!file.exists(file)) {
        file <- file.path(
          "..",
          "..",
          file
        )
      }

      source(file)
    }
  )
}

validation_result_fixture <- function(
  check_name = "check",
  severity = "CRITICAL",
  passed = TRUE,
  issue_count = 0L,
  details = tibble::tibble()
) {
  tibble::tibble(
    check_name = check_name,
    check_scope = "deep",
    severity = severity,
    passed = passed,
    issue_count = issue_count,
    details = list(details)
  )
}

testthat::test_that("validation outcome summary handles clean runs", {
  source_validation_notification_files()

  results <- validation_result_fixture()
  summary <- summarize_platform_validation_results(results)

  testthat::expect_equal(
    summary$validation_outcome[[1]],
    "PASSED"
  )
  testthat::expect_equal(summary$warning_check_count[[1]], 0L)
  testthat::expect_equal(summary$error_check_count[[1]], 0L)
})

testthat::test_that("validation outcome summary handles one warning", {
  source_validation_notification_files()

  results <- validation_result_fixture(
    check_name = "warning_check",
    severity = "WARNING",
    passed = FALSE,
    issue_count = 3L
  )
  summary <- summarize_platform_validation_results(results)

  testthat::expect_equal(
    summary$validation_outcome[[1]],
    "PASSED_WITH_WARNINGS"
  )
  testthat::expect_equal(summary$warning_check_count[[1]], 1L)
  testthat::expect_equal(summary$warning_issue_count[[1]], 3L)
  testthat::expect_equal(summary$error_check_count[[1]], 0L)
})

testthat::test_that("validation outcome summary handles multiple warnings", {
  source_validation_notification_files()

  results <- dplyr::bind_rows(
    validation_result_fixture(
      check_name = "warning_one",
      severity = "WARNING",
      passed = FALSE,
      issue_count = 2L
    ),
    validation_result_fixture(
      check_name = "warning_two",
      severity = "WARNING",
      passed = FALSE,
      issue_count = 5L
    )
  )
  summary <- summarize_platform_validation_results(results)

  testthat::expect_equal(summary$warning_check_count[[1]], 2L)
  testthat::expect_equal(summary$warning_issue_count[[1]], 7L)
})

testthat::test_that("validation outcome summary handles failures", {
  source_validation_notification_files()

  results <- validation_result_fixture(
    check_name = "critical_check",
    severity = "CRITICAL",
    passed = FALSE,
    issue_count = 4L
  )
  summary <- summarize_platform_validation_results(results)

  testthat::expect_equal(summary$validation_outcome[[1]], "FAILED")
  testthat::expect_equal(summary$error_check_count[[1]], 1L)
  testthat::expect_equal(summary$error_issue_count[[1]], 4L)
})

testthat::test_that("validation outcome detects timeout errors", {
  source_validation_notification_files()

  testthat::expect_equal(
    platform_validation_outcome(
      validation_results = tibble::tibble(),
      error_message = "overall timeout reached"
    ),
    "TIMED_OUT"
  )
})

testthat::test_that("validation notification body includes summary counts", {
  source_validation_notification_files()

  results <- validation_result_fixture(
    check_name = "warning_check",
    severity = "WARNING",
    passed = FALSE,
    issue_count = 2L,
    details = tibble::tibble(
      activity_date = as.Date("2026-07-10"),
      issue_count = 2L
    )
  )
  summary <- summarize_platform_validation_results(results)

  body <- format_platform_validation_notification_body(
    job_name = "platform_validation",
    execution_status = "SUCCESS",
    validation_outcome = "PASSED_WITH_WARNINGS",
    completed_at = as.POSIXct(
      "2026-07-14 08:00:00",
      tz = "UTC"
    ),
    elapsed_seconds = 62,
    validation_summary = summary,
    validation_results = results,
    validation_run_id = 123L
  )

  testthat::expect_true(grepl("Warnings: 1 checks", body, fixed = TRUE))
  testthat::expect_true(grepl("warning_check: 2 issues", body, fixed = TRUE))
  testthat::expect_true(grepl("Validation run: 123", body, fixed = TRUE))
})

testthat::test_that("validation notification samples are truncated to five rows", {
  source_validation_notification_files()

  details <- tibble::tibble(
    row_id = 1:8,
    value = paste0(
      "value_",
      1:8
    )
  )

  sample_lines <- validation_issue_sample_lines(
    details = details,
    max_rows = 5L
  )

  testthat::expect_equal(length(sample_lines), 5L)
  testthat::expect_true(grepl("row_id=5", sample_lines[[5]], fixed = TRUE))
  testthat::expect_false(any(grepl("row_id=6", sample_lines, fixed = TRUE)))
})
