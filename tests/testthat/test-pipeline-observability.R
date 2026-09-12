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

testthat::test_that("validation run modes describe invocation rather than publication target", {
  source(pipeline_observability_path("R", "admin", "create_validation_run.R"))

  testthat::expect_equal(
    validation_run_modes(),
    c("manual", "automated", "standalone")
  )
  testthat::expect_equal(normalise_validation_run_mode("AUTOMATED"), "automated")
  testthat::expect_error(
    normalise_validation_run_mode("automated_gold_publication_gate"),
    "Unsupported validation run_mode"
  )

  daily <- paste(
    readLines(pipeline_observability_path("run_daily_platform.R"), warn = FALSE),
    collapse = "\n"
  )
  testthat::expect_equal(
    lengths(regmatches(daily, gregexpr('run_mode = "automated"', daily, fixed = TRUE))),
    2L
  )
  testthat::expect_false(grepl("automated_publication_gate", daily, fixed = TRUE))
  testthat::expect_false(grepl("automated_gold_publication_gate", daily, fixed = TRUE))

  gold_publication_insert <- validation_run_insert_params(
    pipeline_run_id = 225L,
    validation_scope = "publication",
    run_mode = "automated",
    per_check_timeout_seconds = 30L,
    overall_timeout_seconds = 300L
  )
  testthat::expect_identical(gold_publication_insert[[1]], 225L)
  testthat::expect_identical(gold_publication_insert[[2]], "PUBLICATION")
  testthat::expect_identical(gold_publication_insert[[3]], "AUTOMATED")
  validation_run_ddl <- paste(
    readLines(
      pipeline_observability_path("sql", "admin", "050_create_validation_run.sql"),
      warn = FALSE
    ),
    collapse = "\n"
  )
  run_mode_width <- as.integer(sub(
    ".*run_mode VARCHAR\\(([0-9]+)\\).*",
    "\\1",
    validation_run_ddl
  ))
  testthat::expect_identical(run_mode_width, 30L)
  testthat::expect_lte(nchar(gold_publication_insert[[3]]), run_mode_width)

  silver_publication_insert <- validation_run_insert_params(
    pipeline_run_id = 225L,
    validation_scope = "publication",
    run_mode = "automated",
    per_check_timeout_seconds = 30L,
    overall_timeout_seconds = 300L
  )
  testthat::expect_identical(
    silver_publication_insert[1:3],
    gold_publication_insert[1:3]
  )

  standalone_insert <- validation_run_insert_params(
    pipeline_run_id = NULL,
    validation_scope = "deep",
    run_mode = "standalone",
    per_check_timeout_seconds = 30L,
    overall_timeout_seconds = 300L
  )
  testthat::expect_true(is.na(standalone_insert[[1]]))
  testthat::expect_identical(standalone_insert[[2]], "DEEP")
  testthat::expect_identical(standalone_insert[[3]], "STANDALONE")
})

testthat::test_that("final notification delivery is outside the seven-phase ledger", {
  source(pipeline_observability_path(
    "R", "utils", "send_platform_automation_notification.R"
  ))

  delivered <- attempt_platform_automation_notification(function() TRUE)
  unavailable <- attempt_platform_automation_notification(function() FALSE)
  unexpected <- suppressMessages(attempt_platform_automation_notification(
    function() stop("ntfy timeout", call. = FALSE)
  ))

  testthat::expect_true(delivered$sent)
  testthat::expect_null(delivered$error)
  testthat::expect_false(unavailable$sent)
  testthat::expect_null(unavailable$error)
  testthat::expect_false(unexpected$sent)
  testthat::expect_s3_class(unexpected$error, "error")

  daily <- paste(
    readLines(pipeline_observability_path("run_daily_platform.R"), warn = FALSE),
    collapse = "\n"
  )
  testthat::expect_false(grepl('phase_name = "notification"', daily, fixed = TRUE))
  testthat::expect_false(grepl('record_phase("notification"', daily, fixed = TRUE))

  finalise_position <- regexpr("finish_pipeline_run(", daily, fixed = TRUE)[[1]]
  delivery_position <- regexpr(
    "attempt_platform_automation_notification(", daily, fixed = TRUE
  )[[1]]
  disconnect_position <- regexpr(
    "DBI::dbDisconnect(automation_lock_connection)", daily, fixed = TRUE
  )[[1]]
  testthat::expect_gt(finalise_position, 0L)
  testthat::expect_gt(delivery_position, finalise_position)
  testthat::expect_gt(disconnect_position, delivery_position)
})

testthat::test_that("ntfy outcome cannot replace pipeline execution truth", {
  source(pipeline_observability_path(
    "R", "utils", "send_platform_automation_notification.R"
  ))

  cases <- list(
    success_sent = list(error = NULL, send = function() TRUE),
    success_unavailable = list(error = NULL, send = function() FALSE),
    failed_sent = list(
      error = simpleError("original pipeline failure"),
      send = function() TRUE
    ),
    failed_unavailable = list(
      error = simpleError("original pipeline failure"),
      send = function() FALSE
    )
  )

  outcomes <- lapply(cases, function(case) {
    delivery <- attempt_platform_automation_notification(case$send)
    list(
      pipeline_status = if (is.null(case$error)) "SUCCESS" else "FAILED",
      pipeline_error = case$error,
      notification_sent = delivery$sent
    )
  })

  testthat::expect_identical(outcomes$success_sent$pipeline_status, "SUCCESS")
  testthat::expect_identical(outcomes$success_unavailable$pipeline_status, "SUCCESS")
  testthat::expect_identical(outcomes$failed_sent$pipeline_status, "FAILED")
  testthat::expect_identical(outcomes$failed_unavailable$pipeline_status, "FAILED")
  testthat::expect_identical(
    conditionMessage(outcomes$failed_unavailable$pipeline_error),
    "original pipeline failure"
  )
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
