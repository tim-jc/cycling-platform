testthat::test_that("duration table SQL contains configured durations", {
  validation_file <- file.path(
    "R",
    "validation",
    "validate_platform_completeness.R"
  )

  if (!file.exists(validation_file)) {
    validation_file <- file.path(
      "..",
      "..",
      "R",
      "validation",
      "validate_platform_completeness.R"
    )
  }

  source(validation_file)

  duration_sql <- gold_best_effort_duration_table_sql(
    c(
      60L,
      5L
    )
  )

  testthat::expect_true(
    grepl(
      "SELECT 5 AS duration_seconds",
      duration_sql,
      fixed = TRUE
    )
  )

  testthat::expect_true(
    grepl(
      "SELECT 60 AS duration_seconds",
      duration_sql,
      fixed = TRUE
    )
  )
})

testthat::test_that("critical validation helper detects failed critical checks", {
  validation_file <- file.path(
    "R",
    "validation",
    "validate_platform_completeness.R"
  )

  if (!file.exists(validation_file)) {
    validation_file <- file.path(
      "..",
      "..",
      "R",
      "validation",
      "validate_platform_completeness.R"
    )
  }

  source(validation_file)

  validation_results <- tibble::tibble(
    check_name = c(
      "warning_check",
      "critical_check"
    ),
    severity = c(
      "WARNING",
      "CRITICAL"
    ),
    passed = c(
      FALSE,
      FALSE
    ),
    issue_count = c(
      1L,
      1L
    )
  )

  testthat::expect_true(
    platform_validation_has_critical_failures(validation_results)
  )
})

testthat::test_that("validation results retain check timing for slowest summary", {
  validation_file <- file.path(
    "R",
    "validation",
    "validate_platform_completeness.R"
  )

  if (!file.exists(validation_file)) {
    validation_file <- file.path(
      "..",
      "..",
      "R",
      "validation",
      "validate_platform_completeness.R"
    )
  }

  source(validation_file)

  validation_results <- tibble::tibble(
    check_name = c(
      "fast_check",
      "slow_check"
    ),
    check_scope = c(
      "publication",
      "deep"
    ),
    severity = c(
      "CRITICAL",
      "CRITICAL"
    ),
    passed = c(
      TRUE,
      TRUE
    ),
    issue_count = c(
      0L,
      0L
    ),
    elapsed_seconds = c(
      0.2,
      12.5
    )
  )

  slowest <- get_slowest_platform_validation_checks(
    validation_results = validation_results,
    n = 1L
  )

  testthat::expect_equal(
    slowest$check_name[[1]],
    "slow_check"
  )

  testthat::expect_equal(
    slowest$elapsed_seconds[[1]],
    12.5
  )
})

testthat::test_that("publication scope counts only fast blocking checks", {
  validation_file <- file.path(
    "R",
    "validation",
    "validate_platform_completeness.R"
  )

  if (!file.exists(validation_file)) {
    validation_file <- file.path(
      "..",
      "..",
      "R",
      "validation",
      "validate_platform_completeness.R"
    )
  }

  source(validation_file)

  testthat::expect_equal(
    count_platform_completeness_checks(
      validation_scope = "publication",
      include_gold = TRUE,
      gold_table_exists = TRUE,
      gold_metrics = c(
        "watts",
        "cadence_rpm",
        "heartrate_bpm"
      )
    ),
    2L
  )

  testthat::expect_equal(
    count_platform_completeness_checks(
      validation_scope = "deep",
      include_gold = TRUE,
      gold_table_exists = TRUE,
      gold_metrics = c(
        "watts",
        "cadence_rpm",
        "heartrate_bpm"
      )
    ),
    21L
  )
})
