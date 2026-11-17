identity_root <- local({
  candidates <- c(".", "..", "../..")
  match <- candidates[file.exists(file.path(candidates, "sql/migrations/020_add_canonical_activity_identity.sql"))]
  normalizePath(match[[1L]], mustWork = TRUE)
})

source(file.path(identity_root, "R/admin/canonical_activity_identity.R"), local = TRUE)

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
})
