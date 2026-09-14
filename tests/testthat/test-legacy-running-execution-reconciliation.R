testthat::test_that("legacy reconciliation target set is exact and reviewed", {
  targets <- legacy_running_execution_targets()

  testthat::expect_identical(
    targets$etl_run,
    c(17, 18, 19, 23, 24, 33, 46, 48, 49)
  )
  testthat::expect_identical(
    targets$transform_run,
    c(4, 6, 8, 40, 53, 54)
  )
  testthat::expect_identical(targets$validation_run, 27)
  testthat::expect_equal(sum(lengths(targets)), 16L)
})

testthat::test_that("legacy reconciliation rejects changed preconditions", {
  targets <- legacy_running_execution_targets()
  inspected <- data.frame(
    execution_type = c(
      rep("etl_run", 9), rep("transform_run", 6), "validation_run"
    ),
    execution_id = c(targets$etl_run, targets$transform_run, targets$validation_run),
    pipeline_run_id = NA_real_,
    run_status = "RUNNING",
    completed_at = as.POSIXct(NA),
    later_success_exists = 1
  )

  testthat::expect_true(
    validate_legacy_running_execution_targets(inspected, targets)
  )

  changed <- inspected
  changed$run_status[[1]] <- "FAILED"
  testthat::expect_error(
    validate_legacy_running_execution_targets(changed, targets),
    "no longer RUNNING"
  )

  linked <- inspected
  linked$pipeline_run_id[[1]] <- 1
  testthat::expect_error(
    validate_legacy_running_execution_targets(linked, targets),
    "pipeline lineage"
  )

  unrecovered <- inspected
  unrecovered$later_success_exists[[1]] <- 0
  testthat::expect_error(
    validate_legacy_running_execution_targets(unrecovered, targets),
    "lacks a later successful"
  )
})

testthat::test_that("legacy reconciliation runner is read-only by default", {
  runner_path <- c(
    "scripts/operations/reconcile_legacy_running_executions.R",
    "../../scripts/operations/reconcile_legacy_running_executions.R"
  )
  runner_path <- runner_path[file.exists(runner_path)][[1]]
  runner <- paste(
    readLines(runner_path, warn = FALSE),
    collapse = "\n"
  )

  testthat::expect_match(runner, "apply <- identical\\(args, \\\"--apply\\\"\\)")
  testthat::expect_match(runner, "apply = apply", fixed = TRUE)
})
