phase_1c_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(phase_1c_path("R", "admin", "operational_health.R"))
source(phase_1c_path("R", "admin", "source_freshness_observability.R"))

testthat::test_that("operational health roll-up uses governed precedence", {
  testthat::expect_equal(operational_health_levels(), c("HEALTHY", "UNKNOWN", "INFO", "WARNING", "CRITICAL"))
  testthat::expect_equal(roll_up_operational_health(c("HEALTHY", "INFO")), "INFO")
  testthat::expect_equal(roll_up_operational_health(c("UNKNOWN", "WARNING")), "WARNING")
  testthat::expect_equal(roll_up_operational_health(c("WARNING", "CRITICAL")), "CRITICAL")
  testthat::expect_error(roll_up_operational_health("BROKEN"), "Unsupported")
})

testthat::test_that("source execution health distinguishes freshness and optionality", {
  testthat::expect_equal(classify_source_execution_health("REQUIRED", TRUE, "SUCCESS", 2), "HEALTHY")
  testthat::expect_equal(classify_source_execution_health("REQUIRED", TRUE, "SUCCESS", 31), "WARNING")
  testthat::expect_equal(classify_source_execution_health("REQUIRED", TRUE, "SUCCESS", 49), "CRITICAL")
  testthat::expect_equal(classify_source_execution_health("REQUIRED", TRUE, "FAILED", 1), "CRITICAL")
  testthat::expect_equal(classify_source_execution_health("OPTIONAL", TRUE, "FAILED", 1), "WARNING")
  testthat::expect_equal(classify_source_execution_health("OPTIONAL", TRUE, "SUCCESS", 100), "INFO")
  testthat::expect_equal(classify_source_execution_health("REQUIRED", TRUE), "UNKNOWN")
  testthat::expect_equal(classify_source_execution_health("OPTIONAL", TRUE), "INFO")
  testthat::expect_equal(classify_source_execution_health("OPTIONAL", FALSE), "INFO")
})

testthat::test_that("source-data change is separate from execution freshness", {
  now <- as.POSIXct("2026-09-12 12:00:00", tz = "UTC")
  old <- as.POSIXct("2026-09-11 12:00:00", tz = "UTC")
  testthat::expect_equal(classify_source_data_change(now, old), "ADVANCED")
  testthat::expect_equal(classify_source_data_change(now, now), "UNCHANGED")
  testthat::expect_equal(classify_source_data_change(old, now), "REGRESSED")
  testthat::expect_equal(classify_source_data_change(now, as.POSIXct(NA)), "FIRST_OBSERVATION")
  testthat::expect_equal(classify_source_data_change(as.POSIXct(NA), old), "NO_SOURCE_DATA")
})

testthat::test_that("freshness snapshots cover every governed Raw entity", {
  queries <- source_entity_newest_data_queries()
  expected <- c(
    "activities", "gear", "activity_details", "activity_streams", "activity_laps",
    "google_health_heart_rate", "google_health_sleep_logs", "google_health_exercise",
    "google_health_daily_resting_heart_rate",
    "google_health_daily_heart_rate_variability",
    "google_health_daily_respiratory_rate"
  )
  testthat::expect_setequal(names(queries), expected)
  testthat::expect_true(all(grepl("MAX\\(", queries)))
  raw <- paste(readLines(phase_1c_path("run_raw_ingestion.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(raw, "record_source_freshness_observations\\(")
  testthat::expect_match(raw, 'run_status = "SUCCESS"')
  testthat::expect_match(raw, 'run_status = "FAILED"')
})

testthat::test_that("Phase 1C DDL keeps policy and observation grains narrow", {
  policy <- paste(readLines(phase_1c_path("sql", "admin", "014_create_source_entity_observability_policy.sql"), warn = FALSE), collapse = "\n")
  observation <- paste(readLines(phase_1c_path("sql", "admin", "034_create_source_freshness_observation.sql"), warn = FALSE), collapse = "\n")
  seed <- paste(readLines(phase_1c_path("sql", "admin", "015_seed_source_entity_observability_policy.sql"), warn = FALSE), collapse = "\n")
  testthat::expect_match(policy, "PRIMARY KEY \\(source_id, entity_name\\)")
  testthat::expect_match(policy, "REQUIRED.*OPTIONAL")
  testthat::expect_match(observation, "UNIQUE KEY uq_source_freshness_run_entity \\(run_entity_id\\)")
  testthat::expect_match(observation, "newest_source_data_at DATETIME NULL")
  testthat::expect_match(seed, "google_health_exercise', 'OPTIONAL'")
  testthat::expect_match(seed, "activity_streams', 'OPTIONAL', 0")
})

testthat::test_that("cross-schema Admin views bootstrap after their dependencies", {
  source(phase_1c_path("R", "database", "bootstrap_platform_schema.R"))
  files <- list_platform_bootstrap_sql_files(dirname(dirname(phase_1c_path("R", "database"))))
  view_position <- match("100_create_operational_observability_views.sql", basename(files))
  gold_position <- max(which(grepl("/sql/gold/", files, fixed = TRUE)))
  testthat::expect_false(is.na(view_position))
  testthat::expect_gt(view_position, gold_position)
})

testthat::test_that("dashboard-facing view catalogue is stable and MariaDB-safe", {
  sql <- paste(readLines(phase_1c_path("sql", "admin", "100_create_operational_observability_views.sql"), warn = FALSE), collapse = "\n")
  expected_views <- c(
    "v_platform_health_latest", "v_pipeline_run_history",
    "v_pipeline_phase_history", "v_transform_performance_history",
    "v_source_freshness_latest", "v_source_health_latest",
    "v_publication_freshness_latest", "v_operational_debt_latest",
    "v_validation_history", "v_backup_health_latest", "v_backup_history",
    "v_api_request_failure_history"
  )
  for (view in expected_views) {
    testthat::expect_match(sql, paste0("CREATE OR REPLACE VIEW cycling_platform_admin.", view), fixed = TRUE)
  }
  testthat::expect_false(grepl("FROM \\(SELECT", sql))
  testthat::expect_match(sql, "entity_requirement = 'REQUIRED'", fixed = TRUE)
  testthat::expect_match(sql, "source_freshness_observation", fixed = TRUE)
  testthat::expect_match(sql, "is_behind_upstream", fixed = TRUE)
  testthat::expect_match(sql, "latest_success_at_utc < upstream_success_at_utc", fixed = TRUE)
  testthat::expect_match(sql, "WHERE pipeline_name = 'daily-platform'", fixed = TRUE)
})

testthat::test_that("generated Phase 1C view text uses the canonical collation", {
  source(phase_1c_path("R", "config", "platform_database_inventory.R"))
  sql_lines <- readLines(
    phase_1c_path("sql", "admin", "100_create_operational_observability_views.sql"),
    warn = FALSE
  )
  sql <- paste(sql_lines, collapse = "\n")
  canonical <- platform_canonical_collation()

  # Literal-only CASE outputs otherwise inherit the MariaDB session collation.
  generated_statuses <- gregexpr(
    paste0("END COLLATE ", canonical, " AS (health_status|source_data_change_status)"),
    sql,
    perl = TRUE
  )[[1]]
  testthat::expect_equal(sum(generated_statuses > 0L), 9L)
  testthat::expect_false(grepl("END AS (health_status|source_data_change_status)", sql))

  # Every SELECT-list literal in the two UNION-based contracts is explicit.
  union_lines <- sql_lines[
    grepl("^[[:space:]]*SELECT '[^']+'", sql_lines) |
      grepl("^[[:space:]]*UNION ALL SELECT '[^']+'", sql_lines)
  ]
  testthat::expect_true(length(union_lines) > 0L)
  testthat::expect_true(all(grepl(paste("COLLATE", canonical), union_lines, fixed = TRUE)))

  debt_start <- grep("CREATE OR REPLACE VIEW cycling_platform_admin.v_operational_debt_condition_latest", sql_lines, fixed = TRUE)
  debt_end <- grep("CREATE OR REPLACE VIEW cycling_platform_admin.v_operational_debt_latest", sql_lines, fixed = TRUE) - 1L
  debt_sql <- paste(sql_lines[debt_start:debt_end], collapse = "\n")
  testthat::expect_false(grepl("END[ ,\n]+COUNT", debt_sql, perl = TRUE))
  debt_collations <- gregexpr(paste("COLLATE", canonical), debt_sql, fixed = TRUE)[[1]]
  testthat::expect_gte(sum(debt_collations > 0L), 40L)
})

testthat::test_that("transform view distinguishes true zero work from old telemetry", {
  sql <- paste(readLines(phase_1c_path("sql", "admin", "100_create_operational_observability_views.sql"), warn = FALSE), collapse = "\n")
  testthat::expect_match(sql, "has_phase_1b_metrics")
  testthat::expect_match(sql, "CASE WHEN COUNT\\(metric.metric_name\\) = 0 THEN 0 ELSE 1 END")
  testthat::expect_match(sql, "upstream_affected_count")
  testthat::expect_match(sql, "activities_planned")
  testthat::expect_false(grepl("COALESCE\\(MAX\\(CASE WHEN metric.metric_name", sql))
})

testthat::test_that("debt views govern current actionable conditions", {
  sql <- paste(readLines(phase_1c_path("sql", "admin", "100_create_operational_observability_views.sql"), warn = FALSE), collapse = "\n")
  for (debt in c(
    "raw_activity_details", "raw_activity_streams", "raw_activity_laps",
    "achievement_evaluation", "notification_pending",
    "notification_retry_or_failed", "notification_stale_sending",
    "stale_pipeline_execution",
    "stale_child_execution", "latest_validation", "backup"
  )) testthat::expect_match(sql, debt, fixed = TRUE)
  testthat::expect_match(sql, "INTERVAL 6 HOUR", fixed = TRUE)
  testthat::expect_match(sql, "evaluation_status = 'INVALIDATED'", fixed = TRUE)
})

testthat::test_that("backup and validation views preserve authoritative semantics", {
  sql <- paste(readLines(phase_1c_path("sql", "admin", "100_create_operational_observability_views.sql"), warn = FALSE), collapse = "\n")
  testthat::expect_match(sql, "is_complete_verified_recovery_point")
  testthat::expect_match(sql, "latest_recovery_point_at_utc")
  testthat::expect_match(sql, "attempt_status = 'FAILED'", fixed = TRUE)
  testthat::expect_match(sql, "latest_reconciliation.backup_reconciliation_run_id IS NULL", fixed = TRUE)
  testthat::expect_match(sql, "checks.check_status = 'PASS'", fixed = TRUE)
  testthat::expect_match(sql, "checks.check_status = 'FAIL'", fixed = TRUE)
})

testthat::test_that("mixed Raw identity uses entity source attribution", {
  sql <- paste(readLines(phase_1c_path("sql", "admin", "100_create_operational_observability_views.sql"), warn = FALSE), collapse = "\n")
  helper <- paste(readLines(phase_1c_path("R", "admin", "source_freshness_observability.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(sql, "observation.source_id")
  testthat::expect_match(helper, "SELECT run_entity_id, source_id, entity_name", fixed = TRUE)
  testthat::expect_false(grepl("parent.source_id", sql, fixed = TRUE))
})

testthat::test_that("publication validation governs freshness lineage", {
  validation <- paste(readLines(phase_1c_path("R", "validation", "validate_platform_completeness.R"), warn = FALSE), collapse = "\n")
  testthat::expect_match(validation, "admin_phase_1c_source_freshness_lineage_consistent", fixed = TRUE)
  testthat::expect_match(validation, "observation.source_id <=> entity.source_id", fixed = TRUE)
  testthat::expect_match(validation, "observation.pipeline_run_id <=> run.pipeline_run_id", fixed = TRUE)
})
