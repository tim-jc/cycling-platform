#!/usr/bin/env Rscript

# Must run only against a disposable MariaDB instance: canonical database names
# are created and removed so the production-hardcoded repository functions are
# exercised without substitution.
if (!identical(Sys.getenv("IDENTITY_INTEGRATION_DISPOSABLE"), "1")) {
  stop("Set IDENTITY_INTEGRATION_DISPOSABLE=1 only for a disposable MariaDB instance.")
}
source("bootstrap.R")
config <- load_mariadb_connection_config()
connection <- DBI::dbConnect(
  RMariaDB::MariaDB(), host = config$host, port = config$port,
  user = config$user, password = config$password
)
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
DBI::dbExecute(connection, "SET time_zone = '+00:00'")

databases <- c("cycling_platform_silver", "cycling_platform_admin")
cleanup <- function() {
  for (database in databases) {
    DBI::dbExecute(connection, paste(
      "DROP DATABASE IF EXISTS", DBI::dbQuoteIdentifier(connection, database)
    ))
  }
}
cleanup()
on.exit(if (DBI::dbIsValid(connection)) cleanup(), add = TRUE)
for (database in rev(databases)) {
  DBI::dbExecute(connection, paste(
    "CREATE DATABASE", DBI::dbQuoteIdentifier(connection, database)
  ))
}

run_statements <- function(path) {
  sql <- paste(readLines(path, warn = FALSE), collapse = "\n")
  statements <- Filter(nzchar, trimws(strsplit(sql, ";", fixed = TRUE)[[1L]]))
  for (statement in statements) DBI::dbExecute(connection, statement)
}
run_statements("sql/admin/010_create_data_source.sql")
run_statements("sql/silver/010_create_activities.sql")
run_statements("sql/migrations/020_add_canonical_activity_identity.sql")

compiled_identity_contract <- function() {
  list(
    columns = DBI::dbGetQuery(connection, paste(
      "SELECT table_name, ordinal_position, column_name, column_type,",
      "is_nullable, column_default, extra, character_set_name, collation_name",
      "FROM information_schema.columns",
      "WHERE table_schema = 'cycling_platform_silver'",
      "AND table_name IN ('activity_identity', 'activity_source_map')",
      "ORDER BY table_name, ordinal_position"
    )),
    indexes = DBI::dbGetQuery(connection, paste(
      "SELECT table_name, index_name, non_unique, seq_in_index, column_name",
      "FROM information_schema.statistics",
      "WHERE table_schema = 'cycling_platform_silver'",
      "AND table_name IN ('activity_identity', 'activity_source_map')",
      "ORDER BY table_name, index_name, seq_in_index"
    )),
    constraints = DBI::dbGetQuery(connection, paste(
      "SELECT tc.table_name, tc.constraint_name, tc.constraint_type,",
      "kcu.column_name, kcu.referenced_table_schema,",
      "kcu.referenced_table_name, kcu.referenced_column_name",
      "FROM information_schema.table_constraints tc",
      "LEFT JOIN information_schema.key_column_usage kcu",
      "ON kcu.constraint_schema = tc.constraint_schema",
      "AND kcu.table_name = tc.table_name",
      "AND kcu.constraint_name = tc.constraint_name",
      "WHERE tc.constraint_schema = 'cycling_platform_silver'",
      "AND tc.table_name IN ('activity_identity', 'activity_source_map')",
      "ORDER BY tc.table_name, tc.constraint_name, kcu.ordinal_position"
    )),
    triggers = DBI::dbGetQuery(connection, paste(
      "SELECT trigger_name, event_manipulation, event_object_table,",
      "action_timing, action_statement",
      "FROM information_schema.triggers",
      "WHERE trigger_schema = 'cycling_platform_silver'",
      "AND event_object_table IN ('activity_identity', 'activity_source_map')",
      "ORDER BY trigger_name"
    ))
  )
}
migration_contract <- compiled_identity_contract()
stopifnot(nrow(migration_contract$triggers) == 4L)

DBI::dbExecute(connection,
  "INSERT INTO cycling_platform_admin.data_source (source_name) VALUES ('strava')"
)
insert_activity <- function(activity_id) {
  DBI::dbExecute(connection, paste(
    "INSERT INTO cycling_platform_silver.activities",
    "(activity_id, source_id, has_streams, has_details, has_laps,",
    "raw_activity_retrieved_at, transformed_at)",
    "VALUES (?, 1, 0, 0, 0, UTC_TIMESTAMP(), UTC_TIMESTAMP())"
  ), params = list(activity_id))
}
insert_activity(100)
insert_activity(101)

preview <- preview_canonical_activity_identity_backfill(connection)
stopifnot(preview$allocation_count == 2L, preview$mapped_count == 0L)

# A forced mapping failure rolls back its identity allocation while an earlier
# committed unit remains resumable.
DBI::dbExecute(connection, paste(
  "CREATE TRIGGER cycling_platform_silver.test_identity_mapping_failure",
  "BEFORE INSERT ON cycling_platform_silver.activity_source_map FOR EACH ROW",
  "BEGIN IF NEW.source_activity_id = '101' THEN",
  "SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'synthetic mapping failure';",
  "END IF; END"
))
partial_failed <- tryCatch({
  backfill_canonical_activity_identity(connection); FALSE
}, error = function(error) TRUE)
stopifnot(partial_failed)
partial_counts <- DBI::dbGetQuery(connection, paste(
  "SELECT",
  "(SELECT COUNT(*) FROM cycling_platform_silver.activity_identity) identities,",
  "(SELECT COUNT(*) FROM cycling_platform_silver.activity_source_map) mappings"
))
stopifnot(partial_counts$identities == 1L, partial_counts$mappings == 1L)
DBI::dbExecute(connection,
  "DROP TRIGGER cycling_platform_silver.test_identity_mapping_failure"
)
first <- backfill_canonical_activity_identity(connection)
stopifnot(first$mapped_count == 2L, first$allocation_count == 0L)
keys_before <- DBI::dbGetQuery(connection, paste(
  "SELECT source_activity_id, activity_key",
  "FROM cycling_platform_silver.activity_source_map",
  "ORDER BY source_activity_id"
))

# Exact rerun preserves allocated keys. A later published activity receives only
# one new key, demonstrating interruption/rerun semantics.
second <- backfill_canonical_activity_identity(connection)
stopifnot(second$mapped_count == 2L)
insert_activity(102)
third <- backfill_canonical_activity_identity(connection)
keys_after <- DBI::dbGetQuery(connection, paste(
  "SELECT source_activity_id, activity_key",
  "FROM cycling_platform_silver.activity_source_map",
  "ORDER BY source_activity_id"
))
stopifnot(third$mapped_count == 3L, identical(
  keys_before$activity_key, keys_after$activity_key[1:2]
))

lock_names <- c(
  CANONICAL_ACTIVITY_BACKFILL_LOCK,
  "cycling-platform-canonical-activity-identity-backfill-run",
  "cycling-platform-exclusive-run"
)
lock_state <- DBI::dbGetQuery(connection, paste(
  "SELECT IS_FREE_LOCK(?) first_lock, IS_FREE_LOCK(?) owner_lock,",
  "IS_FREE_LOCK(?) platform_lock"
), params = as.list(lock_names))
stopifnot(all(unlist(lock_state, use.names = FALSE) == 1L))

expect_db_error <- function(statement, params = NULL) {
  tryCatch({
    DBI::dbExecute(connection, statement, params = params)
    FALSE
  }, error = function(error) TRUE)
}
stopifnot(
  expect_db_error(paste(
    "UPDATE cycling_platform_silver.activity_identity",
    "SET activity_key = activity_key + 1000 WHERE activity_key = ?"
  ), list(keys_after$activity_key[[1L]])),
  expect_db_error(paste(
    "UPDATE cycling_platform_silver.activity_source_map",
    "SET activity_key = ? WHERE source_id = 1 AND source_activity_id = '100'"
  ), list(keys_after$activity_key[[2L]])),
  expect_db_error(paste(
    "UPDATE cycling_platform_silver.activity_source_map",
    "SET source_activity_id = 'changed'",
    "WHERE source_id = 1 AND source_activity_id = '100'"
  )),
  expect_db_error(paste(
    "DELETE FROM cycling_platform_silver.activity_source_map",
    "WHERE source_id = 1 AND source_activity_id = '100'"
  )),
  expect_db_error(paste(
    "DELETE FROM cycling_platform_silver.activity_identity WHERE activity_key = ?"
  ), list(keys_after$activity_key[[1L]]))
)

# Temporary Silver withdrawal leaves immutable historical identity; republication
# resolves to the same key.
key_102 <- DBI::dbGetQuery(connection, paste(
  "SELECT activity_key FROM cycling_platform_silver.activity_source_map",
  "WHERE source_id = 1 AND source_activity_id = '102'"
))$activity_key[[1L]]
DBI::dbExecute(connection,
  "DELETE FROM cycling_platform_silver.activities WHERE activity_id = 102"
)
withdrawn <- read_canonical_activity_identity_integrity(connection)
stopifnot(
  withdrawn$item_count[withdrawn$diagnostic_key ==
    "historical_mapping_without_published_activity"] == 1L
)
insert_activity(102)
backfill_canonical_activity_identity(connection)
republished <- DBI::dbGetQuery(connection, paste(
  "SELECT activity_key FROM cycling_platform_silver.activity_source_map",
  "WHERE source_id = 1 AND source_activity_id = '102'"
))$activity_key[[1L]]
stopifnot(identical(key_102, republished))

# Database constraints reject duplicate source identities and invalid parents.
duplicate_failed <- tryCatch({
  DBI::dbExecute(connection, paste(
    "INSERT INTO cycling_platform_silver.activity_source_map",
    "(source_id, source_activity_id, activity_key, mapping_method)",
    "VALUES (1, '100', ?, 'STRAVA_BACKFILL')"
  ), params = list(keys_after$activity_key[[1L]])); FALSE
}, error = function(error) TRUE)
invalid_parent_failed <- tryCatch({
  DBI::dbExecute(connection, paste(
    "INSERT INTO cycling_platform_silver.activity_source_map",
    "(source_id, source_activity_id, activity_key, mapping_method)",
    "VALUES (1, 'invalid', 999999, 'STRAVA_BACKFILL')"
  )); FALSE
}, error = function(error) TRUE)
stopifnot(duplicate_failed, invalid_parent_failed)

# Repository reconciliation can safely replay idempotent create/convert DDL.
run_statements("sql/migrations/020_add_canonical_activity_identity.sql")

# A second evaluator cannot enter while the named lock is held.
second_connection <- DBI::dbConnect(
  RMariaDB::MariaDB(), host = config$host, port = config$port,
  user = config$user, password = config$password
)
on.exit(if (DBI::dbIsValid(second_connection)) DBI::dbDisconnect(second_connection),
        add = TRUE)
acquire_canonical_activity_backfill_lock(connection, 0L)
lock_failed <- tryCatch({
  backfill_canonical_activity_identity(second_connection, lock_timeout = 0L)
  FALSE
}, error = function(error) grepl("Could not acquire", conditionMessage(error)))
release_canonical_activity_backfill_lock(connection)
stopifnot(lock_failed)
stopifnot(tryCatch({
  release_canonical_activity_backfill_lock(connection)
  FALSE
}, error = function(error) grepl("not confirmed", conditionMessage(error))))

# The state-changing backfill participates in the existing platform-wide lock.
acquire_platform_run_lock(second_connection, "synthetic-publication", 0L)
publication_contention <- tryCatch({
  backfill_canonical_activity_identity(connection, lock_timeout = 0L)
  FALSE
}, error = function(error) grepl("another daily", conditionMessage(error)))
release_platform_run_lock(second_connection, "synthetic-publication")
stopifnot(publication_contention)

# Release failure is observable, while an original execution error remains the
# primary error. Connection cleanup remains able to release the real lock.
original_release <- release_canonical_activity_backfill_lock
assign(
  "release_canonical_activity_backfill_lock",
  function(connection) stop("synthetic release failure", call. = FALSE),
  envir = .GlobalEnv
)
release_failure <- tryCatch({
  backfill_canonical_activity_identity(connection)
  "none"
}, error = function(error) conditionMessage(error))
assign("release_canonical_activity_backfill_lock", original_release,
       envir = .GlobalEnv)
original_release(connection)
stopifnot(grepl("lock release failed", release_failure))

original_perform <- perform_canonical_activity_identity_backfill
assign(
  "release_canonical_activity_backfill_lock",
  function(connection) stop("synthetic release failure", call. = FALSE),
  envir = .GlobalEnv
)
assign(
  "perform_canonical_activity_identity_backfill",
  function(connection) stop("synthetic execution failure", call. = FALSE),
  envir = .GlobalEnv
)
release_warning <- NULL
original_error <- withCallingHandlers(
  tryCatch({
    backfill_canonical_activity_identity(connection)
    "none"
  }, error = function(error) conditionMessage(error)),
  warning = function(warning) {
    release_warning <<- conditionMessage(warning)
    invokeRestart("muffleWarning")
  }
)
assign("release_canonical_activity_backfill_lock", original_release,
       envir = .GlobalEnv)
assign("perform_canonical_activity_identity_backfill", original_perform,
       envir = .GlobalEnv)
original_release(connection)
stopifnot(
  grepl("synthetic execution failure", original_error),
  grepl("synthetic release failure", release_warning)
)

# Bounded diagnostics distinguish violations from retained historical mappings.
DBI::dbExecute(connection, paste(
  "INSERT INTO cycling_platform_silver.activity_identity",
  "(identity_origin) VALUES ('STRAVA_BACKFILL')"
))
orphan_key <- DBI::dbGetQuery(connection,
  "SELECT LAST_INSERT_ID() AS activity_key"
)$activity_key[[1L]]
DBI::dbExecute(connection, paste(
  "INSERT INTO cycling_platform_silver.activity_source_map",
  "(source_id, source_activity_id, activity_key, mapping_method)",
  "VALUES (1, 'duplicate-100', ?, 'STRAVA_BACKFILL')"
), params = list(keys_after$activity_key[[1L]]))
DBI::dbExecute(connection, paste(
  "INSERT INTO cycling_platform_silver.activity_identity",
  "(identity_origin) VALUES ('SOURCE_ALLOCATION')"
))
unexpected_key <- DBI::dbGetQuery(connection,
  "SELECT LAST_INSERT_ID() AS activity_key"
)$activity_key[[1L]]
DBI::dbExecute(connection, paste(
  "INSERT INTO cycling_platform_silver.activity_source_map",
  "(source_id, source_activity_id, activity_key, mapping_method)",
  "VALUES (1, 'unexpected-policy', ?, 'SOURCE_ALLOCATION')"
), params = list(unexpected_key))
diagnostics <- read_canonical_activity_identity_integrity(connection)
diagnostic_count <- stats::setNames(
  diagnostics$item_count, diagnostics$diagnostic_key
)
diagnostic_status <- stats::setNames(
  diagnostics$diagnostic_status, diagnostics$diagnostic_key
)
stopifnot(
  diagnostic_count[["published_activity_without_mapping"]] == 0L,
  diagnostic_count[["identity_without_source_mapping"]] == 1L,
  diagnostic_count[["multiple_strava_records_per_identity"]] == 1L,
  diagnostic_count[["mapping_provenance_inconsistent"]] == 1L,
  diagnostic_count[["historical_mapping_without_published_activity"]] == 2L,
  diagnostic_status[["historical_mapping_without_published_activity"]] ==
    "EXPECTED_HISTORICAL",
  orphan_key > 0
)

# Fresh-bootstrap definitions independently create the same usable contract.
DBI::dbExecute(connection,
  "DROP TABLE cycling_platform_silver.activity_source_map"
)
DBI::dbExecute(connection,
  "DROP TABLE cycling_platform_silver.activity_identity"
)
run_statements("sql/silver/070_create_activity_identity.sql")
run_statements("sql/silver/080_create_activity_source_map.sql")
run_statements("sql/silver/090_create_activity_identity_immutability_triggers.sql")
fresh_contract <- compiled_identity_contract()
stopifnot(identical(migration_contract, fresh_contract))
DBI::dbExecute(connection, paste(
  "ALTER TABLE cycling_platform_silver.activity_identity",
  "AUTO_INCREMENT = 9007199254740993"
))
fresh <- backfill_canonical_activity_identity(connection)
stopifnot(fresh$mapped_count == 3L, fresh$allocation_count == 0L)
large_keys <- DBI::dbGetQuery(connection, paste(
  "SELECT activity_key FROM cycling_platform_silver.activity_source_map",
  "WHERE source_activity_id IN ('100', '101', '102') ORDER BY source_activity_id"
))$activity_key
stopifnot(
  bit64::is.integer64(large_keys),
  identical(as.character(large_keys),
            c("9007199254740993", "9007199254740994", "9007199254740995"))
)
large_keys_before <- as.character(large_keys)
backfill_canonical_activity_identity(connection)
large_keys_after <- DBI::dbGetQuery(connection, paste(
  "SELECT activity_key FROM cycling_platform_silver.activity_source_map",
  "WHERE source_activity_id IN ('100', '101', '102') ORDER BY source_activity_id"
))$activity_key
stopifnot(identical(large_keys_before, as.character(large_keys_after)))

# Binary source identity remains case-sensitive and preserves UTF-8 bytes.
exact_identifiers <- c("RideA", "ridea", "ridé-東京")
for (identifier in exact_identifiers) {
  allocate_canonical_activity_identity(connection, 1L, identifier)
}
exact_rows <- DBI::dbGetQuery(connection, paste(
  "SELECT HEX(source_activity_id) source_id_hex, activity_key",
  "FROM cycling_platform_silver.activity_source_map",
  "WHERE source_activity_id IN ('RideA', 'ridea', 'ridé-東京')",
  "ORDER BY source_id_hex"
))
expected_hex <- toupper(vapply(
  exact_identifiers,
  function(value) paste(sprintf("%02x", as.integer(charToRaw(enc2utf8(value)))),
                         collapse = ""),
  character(1)
))
stopifnot(
  nrow(exact_rows) == 3L,
  setequal(exact_rows$source_id_hex, expected_hex),
  length(unique(as.character(exact_rows$activity_key))) == 3L
)
DBI::dbDisconnect(second_connection)
cleanup()
DBI::dbDisconnect(connection)
message("Canonical activity identity MariaDB integration test passed.")
