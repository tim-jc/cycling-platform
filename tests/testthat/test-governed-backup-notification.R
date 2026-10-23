source_governed_backup_notification <- function() {
  root <- if (dir.exists("R")) "." else file.path("..", "..")
  source(file.path(root, "R", "config", "platform_database_inventory.R"))
  source(file.path(root, "R", "utils", "backup_observability.R"))
  source(file.path(root, "R", "utils", "execution_context.R"))
  source(file.path(root, "R", "utils", "format_notification_helpers.R"))
  source(file.path(root, "R", "utils", "send_platform_automation_notification.R"))
  source(file.path(root, "R", "validation", "summarize_platform_validation.R"))
  source(file.path(root, "R", "utils", "send_platform_validation_notification.R"))
}

governed_backup_fixture <- function(
  health_status = "HEALTHY",
  attempt_status = "SUCCESS",
  recovery_point = TRUE,
  age_hours = 10,
  reconciliation = TRUE,
  reconciliation_status = "HEALTHY",
  missing = 0L,
  incomplete = 0L,
  orphan = 0L,
  unexpected = 0L
) {
  data.frame(
    latest_attempt_id = if (is.na(attempt_status)) NA_integer_ else 51L,
    latest_attempt_status = attempt_status,
    latest_attempt_completed_at_utc = as.POSIXct("2026-10-22 05:00:00", tz = "UTC"),
    latest_attempt_failure_class = if (identical(attempt_status, "FAILED")) "database_metadata_failure" else NA_character_,
    latest_attempt_failing_database = if (identical(attempt_status, "FAILED")) "cycling_platform_admin" else NA_character_,
    latest_recovery_point_id = if (recovery_point) 50L else NA_integer_,
    latest_recovery_point_at_utc = if (recovery_point) as.POSIXct("2026-10-22 04:00:00", tz = "UTC") else as.POSIXct(NA, tz = "UTC"),
    recovery_point_age_hours = if (recovery_point) age_hours else NA_real_,
    latest_reconciliation_id = if (reconciliation) 22L else NA_integer_,
    latest_reconciliation_status = if (reconciliation) reconciliation_status else NA_character_,
    latest_reconciliation_at_utc = if (reconciliation) as.POSIXct("2026-10-22 05:10:00", tz = "UTC") else as.POSIXct(NA, tz = "UTC"),
    missing_file_count = missing,
    incomplete_run_count = incomplete,
    orphan_file_count = orphan,
    unexpected_file_count = unexpected,
    health_status = health_status,
    stringsAsFactors = FALSE
  )
}

governed_summary <- function(health) {
  backup_health_notification_summary(
    connection = NULL,
    health_reader = function(connection) health
  )
}

testthat::test_that("healthy governed backup state is concise and explicit", {
  source_governed_backup_notification()
  summary <- governed_summary(governed_backup_fixture())

  testthat::expect_identical(summary$health_status, "HEALTHY")
  testthat::expect_match(summary$lines[[1]], "Overall: HEALTHY ✓", fixed = TRUE)
  testthat::expect_match(summary$lines[[2]], "Latest attempt: SUCCESS", fixed = TRUE)
  testthat::expect_match(summary$lines[[3]], "Last verified backup: 10h ago", fixed = TRUE)
  testthat::expect_match(summary$lines[[4]], "Reconciliation: HEALTHY ✓", fixed = TRUE)
})

testthat::test_that("a failed latest attempt remains visible beside an older recovery point", {
  source_governed_backup_notification()
  summary <- governed_summary(governed_backup_fixture(
    health_status = "WARNING",
    attempt_status = "FAILED"
  ))

  testthat::expect_identical(summary$health_status, "WARNING")
  testthat::expect_match(summary$lines[[1]], "Overall: WARNING ⚠", fixed = TRUE)
  testthat::expect_match(summary$lines[[2]], "Latest attempt: FAILED", fixed = TRUE)
  testthat::expect_match(summary$lines[[2]], "database_metadata_failure", fixed = TRUE)
  testthat::expect_match(summary$lines[[3]], "10h ago", fixed = TRUE)
})

testthat::test_that("missing recovery points are never rendered healthy", {
  source_governed_backup_notification()
  summary <- governed_summary(governed_backup_fixture(
    health_status = "UNKNOWN",
    attempt_status = "FAILED",
    recovery_point = FALSE
  ))

  testthat::expect_identical(summary$health_status, "UNKNOWN")
  testthat::expect_match(summary$lines[[1]], "Overall: UNKNOWN ⚠", fixed = TRUE)
  testthat::expect_match(summary$lines[[3]], "Last verified backup: none", fixed = TRUE)
})

testthat::test_that("governed warning and critical freshness bands are preserved", {
  source_governed_backup_notification()
  warning <- governed_summary(governed_backup_fixture(health_status = "WARNING", age_hours = 31))
  critical <- governed_summary(governed_backup_fixture(health_status = "CRITICAL", age_hours = 49))

  testthat::expect_identical(warning$health_status, "WARNING")
  testthat::expect_match(warning$lines[[3]], "31h ago", fixed = TRUE)
  testthat::expect_identical(critical$health_status, "CRITICAL")
  testthat::expect_match(critical$lines[[3]], "49h ago", fixed = TRUE)
})

testthat::test_that("successful attempts do not override governed stale recovery health", {
  source_governed_backup_notification()
  summary <- governed_summary(governed_backup_fixture(
    health_status = "CRITICAL",
    attempt_status = "SUCCESS",
    age_hours = 52
  ))

  testthat::expect_identical(summary$health_status, "CRITICAL")
  testthat::expect_match(summary$lines[[2]], "Latest attempt: SUCCESS", fixed = TRUE)
})

testthat::test_that("missing reconciliation remains governed UNKNOWN", {
  source_governed_backup_notification()
  summary <- governed_summary(governed_backup_fixture(
    health_status = "UNKNOWN",
    reconciliation = FALSE
  ))

  testthat::expect_identical(summary$health_status, "UNKNOWN")
  testthat::expect_identical(summary$reconciliation_status, "MISSING")
  testthat::expect_match(summary$lines[[4]], "no evidence recorded", fixed = TRUE)
})

testthat::test_that("incomplete and inconsistent reconciliation preserve critical health", {
  source_governed_backup_notification()
  summary <- governed_summary(governed_backup_fixture(
    health_status = "CRITICAL",
    reconciliation_status = "WARNING",
    missing = 5L,
    incomplete = 1L
  ))

  testthat::expect_identical(summary$health_status, "CRITICAL")
  testthat::expect_match(summary$lines[[4]], "missing 5", fixed = TRUE)
  testthat::expect_match(summary$lines[[4]], "incomplete 1", fixed = TRUE)
})

testthat::test_that("orphaned and unexpected files retain governed warning", {
  source_governed_backup_notification()
  summary <- governed_summary(governed_backup_fixture(
    health_status = "WARNING",
    reconciliation_status = "WARNING",
    orphan = 2L,
    unexpected = 1L
  ))

  testthat::expect_identical(summary$health_status, "WARNING")
  testthat::expect_match(summary$lines[[4]], "orphan 2", fixed = TRUE)
  testthat::expect_match(summary$lines[[4]], "unexpected 1", fixed = TRUE)
})

testthat::test_that("empty, failed, and malformed governed reads are unavailable", {
  source_governed_backup_notification()

  empty <- backup_health_notification_summary(
    NULL,
    health_reader = function(connection) stop("Governed backup health must return exactly one row; received 0.")
  )
  failed <- backup_health_notification_summary(
    NULL,
    health_reader = function(connection) stop("database unavailable")
  )
  malformed <- governed_summary(governed_backup_fixture(health_status = "BROKEN"))

  for (summary in list(empty, failed, malformed)) {
    testthat::expect_identical(summary$health_status, "UNAVAILABLE")
    testthat::expect_match(summary$lines[[1]], "Overall: UNAVAILABLE ⚠", fixed = TRUE)
  }
})

testthat::test_that("the adapter reads only the governed current-health view", {
  source_governed_backup_notification()
  reader <- paste(deparse(body(get_governed_backup_health)), collapse = " ")
  summary_reader <- paste(deparse(body(backup_health_notification_summary)), collapse = " ")

  testthat::expect_match(reader, "v_backup_health_latest", fixed = TRUE)
  testthat::expect_false(grepl("backup_run", reader, fixed = TRUE))
  testthat::expect_false(grepl("backup_reconciliation_run", reader, fixed = TRUE))
  testthat::expect_false(grepl("freshness_stale_hours", summary_reader, fixed = TRUE))
  testthat::expect_false(grepl("freshness_critical_hours", summary_reader, fixed = TRUE))
  testthat::expect_false(grepl("backup_freshness_status", summary_reader, fixed = TRUE))
})

testthat::test_that("daily and validation renderers preserve governed backup severity", {
  source_governed_backup_notification()
  backup <- governed_summary(governed_backup_fixture(
    health_status = "WARNING",
    attempt_status = "FAILED"
  ))
  phases <- data.frame(
    phase_name = "raw_ingestion",
    phase_status = "SUCCESS",
    duration_seconds = 1
  )
  daily <- paste(format_platform_automation_notification_body(
    run_status = "SUCCESS",
    phase_results = phases,
    backup_health_summary = backup
  ), collapse = "\n")
  results <- tibble::tibble(
    check_name = "check", check_scope = "deep", severity = "CRITICAL",
    passed = TRUE, issue_count = 0L, details = list(tibble::tibble())
  )
  validation <- format_platform_validation_notification_body(
    job_name = "platform_validation",
    execution_status = "SUCCESS",
    validation_outcome = "PASSED",
    completed_at = as.POSIXct("2026-10-22 06:00:00", tz = "UTC"),
    elapsed_seconds = 1,
    validation_summary = summarize_platform_validation_results(results),
    validation_results = results,
    backup_health_summary = backup
  )

  for (body in list(daily, validation)) {
    testthat::expect_match(body, "Overall: WARNING ⚠", fixed = TRUE)
    testthat::expect_match(body, "Latest attempt: FAILED", fixed = TRUE)
  }
})

testthat::test_that("routine backup health does not alter notification priority policy", {
  root <- if (dir.exists("R")) "." else file.path("..", "..")
  automation <- paste(readLines(file.path(root, "R", "utils", "send_platform_automation_notification.R")), collapse = "\n")
  validation <- paste(readLines(file.path(root, "R", "utils", "send_platform_validation_notification.R")), collapse = "\n")
  backup_script <- paste(readLines(file.path(root, "scripts", "backup_mariadb.sh")), collapse = "\n")

  testthat::expect_match(automation, 'identical(run_status, "FAILED")', fixed = TRUE)
  testthat::expect_match(validation, 'validation_outcome %in% c("FAILED", "TIMED_OUT")', fixed = TRUE)
  testthat::expect_false(grepl("backup_health_summary$health_status", automation, fixed = TRUE))
  testthat::expect_false(grepl("backup_health_summary$health_status", validation, fixed = TRUE))
  testthat::expect_false(grepl("ntfy", backup_script, ignore.case = TRUE))
})
