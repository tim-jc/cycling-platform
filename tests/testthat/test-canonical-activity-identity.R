identity_root <- local({
  candidates <- c(".", "..", "../..")
  match <- candidates[file.exists(file.path(candidates, "sql/migrations/020_add_canonical_activity_identity.sql"))]
  normalizePath(match[[1L]], mustWork = TRUE)
})

source(file.path(identity_root, "R/admin/canonical_activity_identity.R"), local = TRUE)
source(file.path(identity_root, "R/database/bootstrap_platform_schema.R"), local = TRUE)

testthat::test_that("candidate validation accepts unique Strava identities", {
  candidates <- data.frame(
    source_id = c(1L, 1L), source_activity_id = c("100", "101"),
    activity_key = c(NA_real_, 42), source_name = c("strava", "strava")
  )
  testthat::expect_identical(
    validate_canonical_activity_backfill_candidates(candidates), candidates
  )
})

testthat::test_that("candidate validation refuses ambiguity and non-Strava data", {
  duplicate <- data.frame(
    source_id = c(1L, 1L), source_activity_id = c("100", "100"),
    activity_key = c(NA, NA), source_name = c("strava", "strava")
  )
  testthat::expect_error(
    validate_canonical_activity_backfill_candidates(duplicate), "duplicate"
  )
  other <- duplicate[1L, ]
  other$source_name <- "garmin"
  testthat::expect_error(
    validate_canonical_activity_backfill_candidates(other), "only supports Strava"
  )
})

testthat::test_that("migration is additive and preserves compatibility keys", {
  migration <- paste(readLines(
    file.path(identity_root, "sql/migrations/020_add_canonical_activity_identity.sql"),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(migration, "activity_key BIGINT NOT NULL AUTO_INCREMENT", fixed = TRUE)
  testthat::expect_match(migration, "PRIMARY KEY (source_id, source_activity_id)", fixed = TRUE)
  testthat::expect_match(migration, "source_activity_id VARBINARY(255)", fixed = TRUE)
  testthat::expect_match(migration, "FOREIGN KEY (activity_key)", fixed = TRUE)
  testthat::expect_match(migration, "CREATE OR REPLACE TRIGGER", fixed = TRUE)
  testthat::expect_match(migration, "Canonical activity source mappings are immutable", fixed = TRUE)
  testthat::expect_false(grepl("ALTER TABLE.*activities", migration))
  testthat::expect_false(grepl("DROP TABLE|DROP COLUMN", migration))
})

testthat::test_that("bootstrap and migration definitions remain aligned", {
  identity <- readLines(file.path(identity_root, "sql/silver/070_create_activity_identity.sql"), warn = FALSE)
  mapping <- readLines(file.path(identity_root, "sql/silver/080_create_activity_source_map.sql"), warn = FALSE)
  triggers <- readLines(file.path(identity_root, "sql/silver/090_create_activity_identity_immutability_triggers.sql"), warn = FALSE)
  migration <- paste(readLines(file.path(identity_root, "sql/migrations/020_add_canonical_activity_identity.sql"), warn = FALSE), collapse = "\n")
  for (needle in c(
    "activity_key BIGINT NOT NULL AUTO_INCREMENT",
    "chk_activity_identity_origin",
    "PRIMARY KEY (source_id, source_activity_id)",
    "idx_activity_source_map_activity_key",
    "fk_activity_source_map_identity",
    "trg_activity_identity_immutable_update",
    "trg_activity_source_map_immutable_delete"
  )) {
    testthat::expect_match(
      paste(c(identity, mapping, triggers), collapse = "\n"), needle, fixed = TRUE
    )
    testthat::expect_match(migration, needle, fixed = TRUE)
  }
})

testthat::test_that("backfill is serialized, transactional and rerunnable", {
  implementation <- paste(readLines(
    file.path(identity_root, "R/admin/canonical_activity_identity.R"), warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(implementation, "GET_LOCK", fixed = TRUE)
  testthat::expect_match(implementation, "RELEASE_LOCK", fixed = TRUE)
  testthat::expect_match(implementation, "DBI::dbWithTransaction", fixed = TRUE)
  testthat::expect_match(implementation, "FOR UPDATE", fixed = TRUE)
  testthat::expect_match(implementation, "is.na(candidates$activity_key)", fixed = TRUE)
  testthat::expect_match(implementation, "acquire_platform_run_lock", fixed = TRUE)
  testthat::expect_match(implementation, "Advisory lock release was not confirmed", fixed = TRUE)
})

testthat::test_that("preview is read-only", {
  body_text <- paste(deparse(body(preview_canonical_activity_identity_backfill)), collapse = "\n")
  testthat::expect_false(grepl("dbExecute|dbBegin|dbCommit|dbRollback", body_text))
})

testthat::test_that("integrity diagnostics are read-only and governed", {
  body_text <- paste(
    deparse(body(read_canonical_activity_identity_integrity)), collapse = "\n"
  )
  testthat::expect_false(grepl("dbExecute|dbBegin|dbCommit|dbRollback", body_text))
  for (key in c(
    "published_activity_without_mapping",
    "identity_without_source_mapping",
    "historical_mapping_without_published_activity",
    "multiple_strava_records_per_identity",
    "mapping_provenance_inconsistent"
  )) {
    testthat::expect_match(body_text, key, fixed = TRUE)
  }
  testthat::expect_match(body_text, "EXPECTED_HISTORICAL", fixed = TRUE)
  testthat::expect_match(body_text, "SOURCE_ALLOCATION", fixed = TRUE)
})

testthat::test_that("continuous publication owns allocation transaction", {
  rebuild <- paste(readLines(
    file.path(identity_root, "R/transforms/rebuild_silver_activities.R"),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(rebuild, "DBI::dbWithTransaction", fixed = TRUE)
  testthat::expect_match(
    rebuild, "ensure_published_activity_identities(connection)", fixed = TRUE
  )
  testthat::expect_match(
    rebuild, "assert_canonical_activity_identity_immutability(connection)",
    fixed = TRUE
  )
  implementation <- paste(readLines(
    file.path(identity_root, "R/admin/canonical_activity_identity.R"),
    warn = FALSE
  ), collapse = "\n")
  testthat::expect_match(implementation, "SOURCE_ALLOCATION", fixed = TRUE)
  testthat::expect_match(implementation, "activity_refresh_ids", fixed = TRUE)
  testthat::expect_match(implementation, "FOR UPDATE", fixed = TRUE)
  transform <- paste(readLines(file.path(
    identity_root, "sql/silver/020_transform_activities.sql"
  ), warn = FALSE), collapse = "\n")
  testthat::expect_false(grepl(
    "activity_identity|activity_source_map", transform
  ))
  testthat::expect_false(grepl(
    "DROP TABLE|TRUNCATE TABLE", implementation
  ))
})

testthat::test_that("runtime excludes trigger DDL and fails closed on missing safeguards", {
  runner <- paste(readLines(file.path(
    identity_root, "R/transforms/run_silver_transformations.R"
  ), warn = FALSE), collapse = "\n")
  testthat::expect_match(
    runner, 'exclude_pattern = "_triggers[.]sql$"', fixed = TRUE
  )
  implementation <- paste(readLines(file.path(
    identity_root, "R/admin/canonical_activity_identity.R"
  ), warn = FALSE), collapse = "\n")
  for (trigger_name in CANONICAL_ACTIVITY_IMMUTABILITY_TRIGGERS$trigger_name) {
    testthat::expect_match(implementation, trigger_name, fixed = TRUE)
  }
  testthat::expect_match(
    implementation,
    "refusing Silver activity publication. Run governed schema recovery.",
    fixed = TRUE
  )
  bootstrap <- list_platform_bootstrap_sql_files(identity_root)
  testthat::expect_true(any(
    basename(bootstrap) == "090_create_activity_identity_immutability_triggers.sql"
  ))
})

testthat::test_that("identity operations explicitly close their connection", {
  disconnected <- 0L
  result <- with_canonical_activity_identity_connection(
    operation = function(connection) paste0(connection, "-ok"),
    connect = function(database_name) database_name,
    is_valid = function(connection) TRUE,
    disconnect = function(connection) disconnected <<- disconnected + 1L
  )
  testthat::expect_identical(result, "cycling_platform_silver-ok")
  testthat::expect_identical(disconnected, 1L)

  disconnected <- 0L
  testthat::expect_error(
    with_canonical_activity_identity_connection(
      operation = function(connection) stop("primary failure", call. = FALSE),
      connect = function(database_name) database_name,
      is_valid = function(connection) TRUE,
      disconnect = function(connection) disconnected <<- disconnected + 1L
    ),
    "primary failure"
  )
  testthat::expect_identical(disconnected, 1L)
})

testthat::test_that("cleanup failure does not mask the primary error", {
  cleanup_warning <- NULL
  primary <- withCallingHandlers(
    tryCatch(
      with_canonical_activity_identity_connection(
        operation = function(connection) stop("primary failure", call. = FALSE),
        connect = function(database_name) database_name,
        is_valid = function(connection) TRUE,
        disconnect = function(connection) stop("cleanup failure", call. = FALSE)
      ),
      error = conditionMessage
    ),
    warning = function(warning) {
      cleanup_warning <<- conditionMessage(warning)
      invokeRestart("muffleWarning")
    }
  )
  testthat::expect_match(primary, "primary failure", fixed = TRUE)
  testthat::expect_match(cleanup_warning, "cleanup failure", fixed = TRUE)
})

testthat::test_that("identity commands use the governed connection wrapper", {
  backfill <- paste(readLines(file.path(
    identity_root, "scripts/operations/backfill_canonical_activity_identity.R"
  ), warn = FALSE), collapse = "\n")
  diagnostics <- paste(readLines(file.path(
    identity_root, "scripts/operations/diagnose_canonical_activity_identity.R"
  ), warn = FALSE), collapse = "\n")
  testthat::expect_match(
    backfill, "with_canonical_activity_identity_connection", fixed = TRUE
  )
  testthat::expect_match(
    diagnostics, "with_canonical_activity_identity_connection", fixed = TRUE
  )
  testthat::expect_false(grepl("on.exit", backfill, fixed = TRUE))
  testthat::expect_false(grepl("on.exit", diagnostics, fixed = TRUE))
})

testthat::test_that("publication validation governs canonical identity coverage", {
  validation <- paste(readLines(file.path(
    identity_root, "R/validation/validate_platform_completeness.R"
  ), warn = FALSE), collapse = "\n")
  testthat::expect_match(
    validation, "silver_activity_canonical_identity_coverage", fixed = TRUE
  )
  testthat::expect_match(validation, "activity_source_map mapping", fixed = TRUE)
})
