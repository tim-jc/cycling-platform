inventory_file <- file.path("R", "config", "platform_database_inventory.R")
if (!file.exists(inventory_file)) inventory_file <- file.path("..", "..", inventory_file)
source(inventory_file)

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

testthat::test_that("daily publication gates and deep diagnostics remain separate", {
  project_root <- if (file.exists("run_daily_platform.R")) "." else file.path("..", "..")
  daily_text <- paste(
    readLines(file.path(project_root, "run_daily_platform.R"), warn = FALSE),
    collapse = "\n"
  )

  silver_gate <- regexpr('run_phase\\(\\n      "silver_publication_checks"', daily_text)
  gold_transform <- regexpr('run_phase\\(\\n      "gold_transforms"', daily_text)
  gold_gate <- regexpr('run_phase\\(\\n      "gold_publication_checks"', daily_text)

  testthat::expect_gt(silver_gate[[1]], 0L)
  testthat::expect_gt(gold_transform[[1]], silver_gate[[1]])
  testthat::expect_gt(gold_gate[[1]], gold_transform[[1]])
  testthat::expect_match(
    daily_text,
    'phase_name = "deep_validation",\\n      phase_status = "NOT_RUN"'
  )
  testthat::expect_match(
    daily_text,
    "Run separately with Rscript run_platform_validation.R",
    fixed = TRUE
  )
})

testthat::test_that("validation execution errors are distinct from findings", {
  project_root <- if (file.exists("R/quality/run_platform_validation.R")) "." else file.path("..", "..")
  runner_text <- paste(
    readLines(
      file.path(project_root, "R/quality/run_platform_validation.R"),
      warn = FALSE
    ),
    collapse = "\n"
  )

  testthat::expect_match(
    runner_text,
    "if (!is.null(validation_error))",
    fixed = TRUE
  )
  testthat::expect_match(
    runner_text,
    "validation_failed <- platform_validation_has_critical_failures",
    fixed = TRUE
  )
  testthat::expect_match(runner_text, "stop(validation_error)", fixed = TRUE)
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

testthat::test_that("publication scope counts fast blocking and audit checks", {
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
    14L
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
    78L
  )
})

testthat::test_that("Silver working-table validation is explicit and scoped", {
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
  query <- platform_silver_working_table_query()

  testthat::expect_match(
    query,
    "table_schema = 'cycling_platform_silver'",
    fixed = TRUE
  )
  testthat::expect_match(
    query,
    "table_type = 'BASE TABLE'",
    fixed = TRUE
  )
  testthat::expect_match(
    query,
    "(_staging|_build|_tmp)$",
    fixed = TRUE
  )
})

testthat::test_that("Google Health overlap validation ignores the current day", {
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

  validation_source <- paste(
    readLines(
      validation_file,
      warn = FALSE
    ),
    collapse = "\n"
  )

  overlap_check <- regmatches(
    validation_source,
    regexpr(
      paste0(
        "check_name = \"raw_google_health_rhr_hrv_sleep_date_overlap\"",
        "[\\s\\S]*?",
        "check_name = "
      ),
      validation_source,
      perl = TRUE
    )
  )

  testthat::expect_match(
    overlap_check,
    "AND dates.activity_date < UTC_DATE()",
    fixed = TRUE
  )
})
