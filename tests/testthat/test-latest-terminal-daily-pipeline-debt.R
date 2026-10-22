latest_terminal_daily_fixture <- function(runs) {
  terminal <- runs[
    runs$pipeline_name == "daily-platform" &
      runs$run_status %in% c("SUCCESS", "FAILED"),
    ,
    drop = FALSE
  ]
  if (nrow(terminal) == 0L) return(terminal)

  terminal <- terminal[order(
    terminal$completed_at,
    terminal$pipeline_run_id,
    decreasing = TRUE,
    na.last = TRUE
  ), , drop = FALSE]
  terminal[1L, , drop = FALSE]
}

operational_execution_fixture <- function(runs, now = as.POSIXct("2026-10-22 12:00:00", tz = "UTC")) {
  latest <- latest_terminal_daily_fixture(runs)
  latest_failed <- nrow(latest) == 1L && identical(latest$run_status[[1L]], "FAILED")
  stale_running <- sum(
    runs$run_status == "RUNNING" &
      runs$started_at < now - 6 * 60 * 60,
    na.rm = TRUE
  )

  list(
    latest_daily_pipeline = if (latest_failed) "CRITICAL" else "HEALTHY",
    latest_daily_pipeline_count = as.integer(latest_failed),
    stale_pipeline_execution = if (stale_running > 0L) "CRITICAL" else "HEALTHY",
    stale_pipeline_execution_count = stale_running,
    platform_health = if (latest_failed || stale_running > 0L) "CRITICAL" else "HEALTHY"
  )
}

pipeline_fixture <- function(statuses, completed_offsets = seq_along(statuses),
                             names = rep("daily-platform", length(statuses)),
                             started_offsets = seq_along(statuses)) {
  completed <- as.POSIXct("2026-10-22 00:00:00", tz = "UTC") + completed_offsets * 60
  completed[statuses == "RUNNING"] <- as.POSIXct(NA, tz = "UTC")
  data.frame(
    pipeline_run_id = seq_along(statuses),
    pipeline_name = names,
    run_status = statuses,
    started_at = as.POSIXct("2026-10-22 00:00:00", tz = "UTC") + started_offsets * 60,
    completed_at = completed
  )
}

latest_terminal_sql <- function() {
  candidates <- c(
    file.path("sql", "admin", "100_create_operational_observability_views.sql"),
    file.path("..", "..", "sql", "admin", "100_create_operational_observability_views.sql")
  )
  paste(readLines(candidates[file.exists(candidates)][1L], warn = FALSE), collapse = "\n")
}

testthat::test_that("no terminal daily execution is not fabricated as failure debt", {
  runs <- pipeline_fixture(character(), numeric())
  result <- operational_execution_fixture(runs)
  testthat::expect_identical(result$latest_daily_pipeline, "HEALTHY")
  testthat::expect_identical(result$latest_daily_pipeline_count, 0L)
})

testthat::test_that("latest terminal success and failure drive daily debt", {
  success <- operational_execution_fixture(pipeline_fixture("SUCCESS"))
  failure <- operational_execution_fixture(pipeline_fixture("FAILED"))
  testthat::expect_identical(success$latest_daily_pipeline, "HEALTHY")
  testthat::expect_identical(failure$latest_daily_pipeline, "CRITICAL")
})

testthat::test_that("a running retry does not hide the preceding terminal result", {
  failed_running <- operational_execution_fixture(pipeline_fixture(c("FAILED", "RUNNING")))
  success_running <- operational_execution_fixture(pipeline_fixture(c("SUCCESS", "RUNNING")))
  testthat::expect_identical(failed_running$latest_daily_pipeline, "CRITICAL")
  testthat::expect_identical(success_running$latest_daily_pipeline, "HEALTHY")
})

testthat::test_that("only a later terminal result changes current daily debt", {
  recovered <- operational_execution_fixture(pipeline_fixture(c("FAILED", "RUNNING", "SUCCESS")))
  failed_again <- operational_execution_fixture(pipeline_fixture(c("FAILED", "RUNNING", "FAILED")))
  testthat::expect_identical(recovered$latest_daily_pipeline, "HEALTHY")
  testthat::expect_identical(failed_again$latest_daily_pipeline, "CRITICAL")
})

testthat::test_that("multiple active runs leave terminal debt unchanged", {
  result <- operational_execution_fixture(pipeline_fixture(c("FAILED", "RUNNING", "RUNNING")))
  testthat::expect_identical(result$latest_daily_pipeline, "CRITICAL")
  testthat::expect_identical(result$latest_daily_pipeline_count, 1L)
})

testthat::test_that("stale running debt remains independent of terminal failure debt", {
  runs <- pipeline_fixture(c("FAILED", "RUNNING"))
  runs$started_at[[2L]] <- as.POSIXct("2026-10-22 05:00:00", tz = "UTC")
  result <- operational_execution_fixture(runs)
  testthat::expect_identical(result$latest_daily_pipeline, "CRITICAL")
  testthat::expect_identical(result$stale_pipeline_execution, "CRITICAL")
  testthat::expect_identical(result$stale_pipeline_execution_count, 1L)
  testthat::expect_identical(result$platform_health, "CRITICAL")
})

testthat::test_that("completion order governs overlapping terminal executions", {
  runs <- pipeline_fixture(
    c("FAILED", "SUCCESS"),
    completed_offsets = c(20, 10)
  )
  latest <- latest_terminal_daily_fixture(runs)
  testthat::expect_identical(latest$pipeline_run_id, 1L)
  testthat::expect_identical(latest$run_status, "FAILED")

  tied <- pipeline_fixture(c("FAILED", "SUCCESS"), completed_offsets = c(20, 20))
  testthat::expect_identical(latest_terminal_daily_fixture(tied)$pipeline_run_id, 2L)
})

testthat::test_that("non-daily executions do not affect daily debt", {
  runs <- pipeline_fixture(
    c("FAILED", "SUCCESS"),
    names = c("daily-platform", "platform-validation")
  )
  result <- operational_execution_fixture(runs)
  testthat::expect_identical(result$latest_daily_pipeline, "CRITICAL")
  testthat::expect_equal(sum(runs$run_status == "FAILED"), 1L)
})

testthat::test_that("canonical SQL implements the terminal completion-order contract", {
  sql <- latest_terminal_sql()
  testthat::expect_match(sql, "terminal.run_status IN ('SUCCESS', 'FAILED')", fixed = TRUE)
  testthat::expect_match(
    sql,
    "ORDER BY terminal.completed_at DESC, terminal.pipeline_run_id DESC",
    fixed = TRUE
  )
  testthat::expect_match(sql, "LIMIT 1", fixed = TRUE)
  testthat::expect_false(grepl(
    "SELECT MAX(latest.pipeline_run_id) FROM cycling_platform_admin.pipeline_run latest",
    sql,
    fixed = TRUE
  ))
  testthat::expect_match(sql, "INTERVAL 6 HOUR", fixed = TRUE)
})

testthat::test_that("public debt and platform-health column contracts remain stable", {
  sql <- latest_terminal_sql()
  testthat::expect_match(
    sql,
    "SELECT debt_key, debt_domain, health_status, item_count, summary,[[:space:]]+UTC_TIMESTAMP\\(\\) AS observed_at_utc"
  )
  testthat::expect_match(
    sql,
    "CREATE OR REPLACE VIEW cycling_platform_admin.v_platform_health_latest AS",
    fixed = TRUE
  )
  for (column in c(
    "observed_at_utc", "health_status", "critical_condition_count",
    "warning_condition_count", "info_condition_count",
    "unknown_condition_count", "latest_pipeline_run_id",
    "latest_pipeline_status", "latest_pipeline_completed_at_utc"
  )) testthat::expect_match(sql, column, fixed = TRUE)
})
