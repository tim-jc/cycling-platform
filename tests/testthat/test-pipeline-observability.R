pipeline_observability_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

testthat::test_that("pipeline phase contract is singular and ordered", {
  source(pipeline_observability_path("R", "admin", "operational_telemetry.R"))
  phases <- pipeline_phase_contract()
  testthat::expect_equal(nrow(phases), 7L)
  testthat::expect_false(anyDuplicated(phases$phase_name) > 0L)
  testthat::expect_equal(phases$phase_ordinal, seq_len(7L))
  testthat::expect_equal(phases$phase_name[[1]], "raw_ingestion")
  testthat::expect_equal(phases$phase_name[[7]], "deep_validation")
})

testthat::test_that("operational failure summaries redact representative secrets", {
  source(pipeline_observability_path("R", "admin", "operational_telemetry.R"))
  unsafe <- paste(
    "password=hunter2",
    "access_token=abc123",
    "refresh_token=refresh123",
    "client_secret=client123",
    "Authorization: Bearer bearer123",
    "ntfy_topic=private-topic",
    "https://user:pass@example.test/path"
  )
  safe <- sanitize_operational_text(unsafe)
  for (secret in c("hunter2", "abc123", "refresh123", "client123", "bearer123", "private-topic", "pass@")) {
    testthat::expect_false(grepl(secret, safe, fixed = TRUE))
  }
  testthat::expect_true(grepl("[REDACTED]", safe, fixed = TRUE))
})

testthat::test_that("Admin DDL enforces execution and recovery-point contracts", {
  pipeline_sql <- readLines(pipeline_observability_path("sql", "admin", "012_create_pipeline_run.sql"), warn = FALSE)
  phase_sql <- readLines(pipeline_observability_path("sql", "admin", "013_create_pipeline_phase_run.sql"), warn = FALSE)
  backup_sql <- readLines(pipeline_observability_path("sql", "admin", "083_create_backup_attempt.sql"), warn = FALSE)
  pipeline_text <- paste(pipeline_sql, collapse = "\n")
  phase_text <- paste(phase_sql, collapse = "\n")
  backup_text <- paste(backup_sql, collapse = "\n")
  testthat::expect_match(pipeline_text, "DEFAULT CURRENT_TIMESTAMP")
  testthat::expect_match(pipeline_text, "RUNNING.*SUCCESS.*FAILED")
  testthat::expect_match(phase_text, "UNIQUE KEY uq_pipeline_phase_run")
  testthat::expect_match(phase_text, "SKIPPED.*NOT_RUN")
  testthat::expect_match(backup_text, "complete_set_created = 1")
  testthat::expect_match(backup_text, "backup_run_id IS NOT NULL")
})

testthat::test_that("daily execution uses explicit lineage and not latest-run heuristics", {
  daily <- paste(readLines(pipeline_observability_path("run_daily_platform.R"), warn = FALSE), collapse = "\n")
  raw <- paste(readLines(pipeline_observability_path("run_raw_ingestion.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(daily, "create_pipeline_run\\(")
  testthat::expect_match(daily, "WHERE pipeline_run_id = \\?")
  testthat::expect_false(grepl("get_latest_etl_run_id", daily, fixed = TRUE))
  testthat::expect_false(grepl("get_latest_silver_transform_summary", daily, fixed = TRUE))
  testthat::expect_false(grepl("get_latest_gold_transform_summary", daily, fixed = TRUE))
  testthat::expect_match(raw, "--pipeline-run-id=")
  testthat::expect_match(raw, "pipeline_run_id = pipeline_run_id")
})

testthat::test_that("standalone child execution lineage remains nullable", {
  helpers <- c(
    pipeline_observability_path("R", "admin", "create_etl_run.R"),
    pipeline_observability_path("R", "admin", "create_transform_run.R"),
    pipeline_observability_path("R", "admin", "create_validation_run.R")
  )
  for (helper in helpers) {
    text <- paste(readLines(helper, warn = FALSE), collapse = "\n")
    testthat::expect_match(text, "pipeline_run_id = NULL")
  }
})

testthat::test_that("connection setup establishes an explicit UTC session", {
  text <- paste(readLines(pipeline_observability_path("R", "database", "get_connection.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(text, "SET time_zone = '\\+00:00'", fixed = FALSE)
  instant <- as.POSIXct("2026-10-25 01:30:00", tz = "UTC")
  testthat::expect_equal(as.numeric(instant + 3600) - as.numeric(instant), 3600)
})

testthat::test_that("backup workflow records attempts separately from recovery points", {
  workflow <- paste(readLines(pipeline_observability_path("scripts", "run_backup_workflow.sh"), warn = FALSE), collapse = "\n")
  backup <- paste(readLines(pipeline_observability_path("scripts", "backup_mariadb.sh"), warn = FALSE), collapse = "\n")
  testthat::expect_match(backup, "manage_backup_attempt.R start", fixed = TRUE)
  testthat::expect_match(workflow, "manage_backup_attempt.R fail", fixed = TRUE)
  testthat::expect_match(backup, "finalize_backup_observability.R", fixed = TRUE)
  testthat::expect_match(workflow, "caffeinate", fixed = TRUE)
})
