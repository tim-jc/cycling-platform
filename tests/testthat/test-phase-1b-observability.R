phase_1b_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(phase_1b_path("R", "admin", "operational_telemetry.R"))
source(phase_1b_path("R", "admin", "phase_1b_observability.R"))
source(phase_1b_path("R", "api", "perform_strava_request.R"))

testthat::test_that("Gold Phase 1B metrics and dimensions are governed", {
  catalogue <- gold_transform_metric_catalogue()
  testthat::expect_identical(anyDuplicated(catalogue[c("entity_name", "metric_name")]), 0L)
  testthat::expect_true(all(catalogue$metric_unit == "COUNT"))
  testthat::expect_error(
    normalise_gold_transform_metrics("activity_best_efforts", list(unknown = 1)),
    "Unsupported Gold transform metric"
  )
  testthat::expect_equal(
    normalise_gold_transform_dimension("discovery_mode", "affected_set"),
    "affected_set"
  )
  testthat::expect_error(
    normalise_gold_transform_dimension("candidate_mode", "dashboard_magic"),
    "Unsupported Gold transform dimension"
  )
})

testthat::test_that("Phase 1B DDL has durable keys, lineage, and typed timings", {
  metric <- paste(readLines(phase_1b_path("sql", "admin", "042_create_transform_run_metric.sql"), warn = FALSE), collapse = "\n")
  attempt <- paste(readLines(phase_1b_path("sql", "admin", "033_create_api_request_attempt.sql"), warn = FALSE), collapse = "\n")
  transform <- paste(readLines(phase_1b_path("sql", "admin", "040_create_transform_run.sql"), warn = FALSE), collapse = "\n")
  entity <- paste(readLines(phase_1b_path("sql", "admin", "030_create_etl_run_entity.sql"), warn = FALSE), collapse = "\n")
  phase <- paste(readLines(phase_1b_path("sql", "admin", "013_create_pipeline_phase_run.sql"), warn = FALSE), collapse = "\n")

  testthat::expect_match(metric, "PRIMARY KEY \\(transform_run_id, metric_name\\)")
  testthat::expect_match(metric, "metric_unit IN \\('COUNT'\\)")
  testthat::expect_match(attempt, "UNIQUE KEY uq_api_request_attempt")
  testthat::expect_match(attempt, "FOREIGN KEY \\(endpoint_run_id\\)")
  testthat::expect_match(attempt, "retry_decision IN \\('SUCCESS', 'RETRY', 'STOP'\\)")
  for (field in c("setup_seconds", "discovery_seconds", "source_preparation_seconds", "processing_seconds", "finalisation_seconds")) {
    testthat::expect_match(transform, field, fixed = TRUE)
  }
  testthat::expect_match(entity, "source_id INT NULL", fixed = TRUE)
  testthat::expect_match(entity, "REFERENCES cycling_platform_admin.data_source", fixed = TRUE)
  testthat::expect_match(phase, "notifications_deferred INT NULL", fixed = TRUE)
})

testthat::test_that("Strava attempts record retries and terminal failure without network", {
  observed <- list()
  observer <- function(...) observed[[length(observed) + 1L]] <<- list(...)
  failure <- structure(
    simpleError("access_token=secret network unavailable"),
    class = c("httr2_failure", "error", "condition")
  )
  config <- list(
    sources = list(strava = list(api_base_url = "https://example.invalid")),
    ingestion = list(timeout_seconds = 1, max_retries = 1)
  )

  testthat::expect_error(
    perform_strava_request(
      "/athlete", config, token = "token", attempt_observer = observer,
      request_perform = function(request) stop(failure), sleep_fn = function(seconds) NULL
    ),
    "network unavailable"
  )
  testthat::expect_equal(length(observed), 2L)
  testthat::expect_equal(vapply(observed, `[[`, character(1), "retry_decision"), c("RETRY", "STOP"))
  testthat::expect_equal(vapply(observed, `[[`, integer(1), "attempt_number"), 1:2)
})

testthat::test_that("HTTP 597 is retained as a concrete terminal request attempt", {
  observed <- list()
  observer <- function(...) observed[[length(observed) + 1L]] <<- list(...)
  failure <- structure(simpleError("HTTP 597"), class = c("httr2_http_597", "httr2_http", "error", "condition"))
  config <- list(
    sources = list(strava = list(api_base_url = "https://example.invalid")),
    ingestion = list(timeout_seconds = 1, max_retries = 3)
  )
  testthat::expect_error(
    perform_strava_request(
      "/gear/b1", config, token = "token", attempt_observer = observer,
      request_perform = function(request) stop(failure), sleep_fn = function(seconds) NULL
    ),
    "597"
  )
  testthat::expect_equal(length(observed), 1L)
  testthat::expect_equal(observed[[1]]$retry_decision, "STOP")
  testthat::expect_equal(observed[[1]]$path, "/gear/b1")
})

testthat::test_that("Phase 1B persistence is wired without changing transform calculations", {
  best <- paste(readLines(phase_1b_path("R", "transforms", "rebuild_gold_activity_best_efforts.R"), warn = FALSE), collapse = "\n")
  achievements <- paste(readLines(phase_1b_path("R", "transforms", "rebuild_gold_activity_achievements.R"), warn = FALSE), collapse = "\n")
  daily <- paste(readLines(phase_1b_path("run_daily_platform.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(best, "persist_gold_transform_observability\\(")
  testthat::expect_match(best, "output_changed_activity_count")
  testthat::expect_match(achievements, "persist_gold_transform_observability\\(")
  testthat::expect_match(achievements, "zero_achievement_evaluations")
  testthat::expect_match(daily, "update_achievement_notification_phase_workload\\(")
  testthat::expect_false(grepl("send_platform_automation_notification", phase_1b_path("R", "admin", "phase_1b_observability.R"), fixed = TRUE))
})

testthat::test_that("achievement notification workload accepts zero and non-zero passes", {
  zero <- normalise_achievement_notification_workload(0, 0, 0, 0, 0)
  work <- normalise_achievement_notification_workload(3, 2, 1, 1, 1)
  testthat::expect_equal(unname(unlist(zero)), rep(0L, 5L))
  testthat::expect_equal(unname(unlist(work)), c(3L, 2L, 1L, 1L, 1L))
  testthat::expect_error(
    normalise_achievement_notification_workload(1, -1, 0, 0, 0),
    "non-negative integer"
  )
})

testthat::test_that("request telemetry sanitises secrets and uses UTC instants", {
  unsafe <- sanitize_operational_text("Authorization: Bearer abc123 refresh_token=secret")
  testthat::expect_false(grepl("abc123|secret", unsafe))
  ddl <- paste(readLines(phase_1b_path("sql", "admin", "033_create_api_request_attempt.sql"), warn = FALSE), collapse = "\n")
  helper <- paste(readLines(phase_1b_path("R", "admin", "phase_1b_observability.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(ddl, "started_at DATETIME")
  testthat::expect_match(helper, 'as.POSIXct\\(started_at, tz = "UTC"\\)')
})
