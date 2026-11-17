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

databases <- c(
  "cycling_platform_raw", "cycling_platform_silver", "cycling_platform_admin"
)
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
DBI::dbExecute(connection, "USE cycling_platform_silver")

run_statements <- function(path) {
  sql <- paste(readLines(path, warn = FALSE), collapse = "\n")
  statements <- Filter(nzchar, trimws(strsplit(sql, ";", fixed = TRUE)[[1L]]))
  for (statement in statements) DBI::dbExecute(connection, statement)
}
run_statements("sql/admin/010_create_data_source.sql")
run_statements("sql/admin/012_create_pipeline_run.sql")
run_statements("sql/admin/020_create_etl_run.sql")
run_statements("sql/admin/040_create_transform_run.sql")
run_statements("sql/admin/041_create_transform_run_batch.sql")
run_statements("sql/admin/042_create_transform_run_metric.sql")
execute_sql_file("sql/admin/070_create_power_source_classification.sql", connection)
run_statements("sql/raw/010_create_strava_activities.sql")
run_statements("sql/raw/020_create_strava_activity_streams.sql")
run_statements("sql/raw/030_create_strava_activity_details.sql")
run_statements("sql/raw/040_create_strava_activity_laps.sql")
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
DBI::dbExecute(connection, paste(
  "INSERT INTO cycling_platform_admin.etl_run",
  "(source_id, run_mode, run_status) VALUES (1, 'SCHEDULED', 'SUCCESS')"
))
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

# Normal publication resolves identity inside the caller-owned transaction.
DBI::dbExecute(connection, paste(
  "CREATE TEMPORARY TABLE activity_refresh_ids",
  "(activity_id BIGINT PRIMARY KEY) ENGINE=InnoDB"
))
publish_activity <- function(activity_id) {
  DBI::dbWithTransaction(connection, {
    DBI::dbExecute(connection, "DELETE FROM activity_refresh_ids")
    DBI::dbExecute(
      connection,
      "INSERT INTO activity_refresh_ids (activity_id) VALUES (?)",
      params = list(activity_id)
    )
    insert_activity(activity_id)
    ensure_published_activity_identities(connection)
  })
}
publish_activity(103)
continuous_103 <- DBI::dbGetQuery(connection, paste(
  "SELECT mapping.activity_key, mapping.mapping_method, identity_row.identity_origin",
  "FROM cycling_platform_silver.activity_source_map mapping",
  "JOIN cycling_platform_silver.activity_identity identity_row",
  "ON identity_row.activity_key = mapping.activity_key",
  "WHERE mapping.source_id = 1 AND mapping.source_activity_id = '103'"
))
stopifnot(
  nrow(continuous_103) == 1L,
  continuous_103$mapping_method == "SOURCE_ALLOCATION",
  continuous_103$identity_origin == "SOURCE_ALLOCATION"
)
key_103 <- continuous_103$activity_key[[1L]]
DBI::dbWithTransaction(connection, {
  DBI::dbExecute(connection, "DELETE FROM activity_refresh_ids")
  DBI::dbExecute(connection, "INSERT INTO activity_refresh_ids VALUES (103)")
  ensure_published_activity_identities(connection)
})
stopifnot(identical(
  key_103,
  DBI::dbGetQuery(connection, paste(
    "SELECT activity_key FROM cycling_platform_silver.activity_source_map",
    "WHERE source_id = 1 AND source_activity_id = '103'"
  ))$activity_key[[1L]]
))

DBI::dbWithTransaction(connection, {
  DBI::dbExecute(connection, "DELETE FROM activity_refresh_ids")
  DBI::dbExecute(connection,
    "INSERT INTO activity_refresh_ids VALUES (106), (107)"
  )
  insert_activity(106)
  insert_activity(107)
  ensure_published_activity_identities(connection)
})
multiple_publication <- DBI::dbGetQuery(connection, paste(
  "SELECT COUNT(*) n, COUNT(DISTINCT activity_key) distinct_keys",
  "FROM cycling_platform_silver.activity_source_map",
  "WHERE source_id = 1 AND source_activity_id IN ('106', '107')"
))
stopifnot(
  multiple_publication$n == 2L,
  multiple_publication$distinct_keys == 2L
)

# Mapping failure rolls activity publication and identity allocation back.
DBI::dbExecute(connection, paste(
  "CREATE TRIGGER cycling_platform_silver.test_continuous_mapping_failure",
  "BEFORE INSERT ON cycling_platform_silver.activity_source_map FOR EACH ROW",
  "BEGIN IF NEW.source_activity_id = '104' THEN",
  "SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'continuous mapping failure';",
  "END IF; END"
))
continuous_failed <- tryCatch({
  publish_activity(104)
  FALSE
}, error = function(error) TRUE)
DBI::dbExecute(connection,
  "DROP TRIGGER cycling_platform_silver.test_continuous_mapping_failure"
)
continuous_counts <- DBI::dbGetQuery(connection, paste(
  "SELECT",
  "(SELECT COUNT(*) FROM cycling_platform_silver.activities WHERE activity_id = 104) activity_rows,",
  "(SELECT COUNT(*) FROM cycling_platform_silver.activity_source_map WHERE source_activity_id = '104') mapping_rows,",
  "(SELECT COUNT(*) FROM cycling_platform_silver.activity_identity identity_row",
  "LEFT JOIN cycling_platform_silver.activity_source_map mapping",
  "ON mapping.activity_key = identity_row.activity_key",
  "WHERE mapping.activity_key IS NULL) orphan_rows"
))
stopifnot(
  continuous_failed,
  continuous_counts$activity_rows == 0L,
  continuous_counts$mapping_rows == 0L,
  continuous_counts$orphan_rows == 0L
)

# A failure after allocation rolls back both publication and identity state.
publication_failed <- tryCatch({
  DBI::dbWithTransaction(connection, {
    DBI::dbExecute(connection, "DELETE FROM activity_refresh_ids")
    DBI::dbExecute(connection, "INSERT INTO activity_refresh_ids VALUES (105)")
    insert_activity(105)
    ensure_published_activity_identities(connection)
    stop("synthetic post-allocation publication failure", call. = FALSE)
  })
  FALSE
}, error = function(error) TRUE)
stopifnot(
  publication_failed,
  DBI::dbGetQuery(connection, paste(
    "SELECT COUNT(*) n FROM cycling_platform_silver.activities",
    "WHERE activity_id = 105"
  ))$n == 0L,
  DBI::dbGetQuery(connection, paste(
    "SELECT COUNT(*) n FROM cycling_platform_silver.activity_source_map",
    "WHERE source_activity_id = '105'"
  ))$n == 0L
)

# A failed delete/reinsert refresh restores the previously published row.
refresh_failed <- tryCatch({
  DBI::dbWithTransaction(connection, {
    DBI::dbExecute(connection,
      "DELETE FROM cycling_platform_silver.activities WHERE activity_id = 103"
    )
    stop("synthetic refresh failure", call. = FALSE)
  })
  FALSE
}, error = function(error) TRUE)
stopifnot(
  refresh_failed,
  DBI::dbGetQuery(connection, paste(
    "SELECT COUNT(*) n FROM cycling_platform_silver.activities",
    "WHERE activity_id = 103"
  ))$n == 1L
)

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

# Database uniqueness and transaction rollback prevent duplicate identities even
# if callers bypass the supported platform lock and race the same source record.
concurrent_allocate <- function() {
  worker_connection <- DBI::dbConnect(
    RMariaDB::MariaDB(), host = config$host, port = config$port,
    user = config$user, password = config$password
  )
  on.exit(DBI::dbDisconnect(worker_connection), add = TRUE)
  tryCatch(
    as.character(allocate_canonical_activity_identity(
      worker_connection, 1L, "concurrent-identity", "SOURCE_ALLOCATION"
    )),
    error = function(error) paste0("ERROR: ", conditionMessage(error))
  )
}
concurrent_results <- parallel::mccollect(list(
  parallel::mcparallel(concurrent_allocate()),
  parallel::mcparallel(concurrent_allocate())
))
concurrent_state <- DBI::dbGetQuery(connection, paste(
  "SELECT COUNT(*) mapping_count, COUNT(DISTINCT activity_key) key_count",
  "FROM cycling_platform_silver.activity_source_map",
  "WHERE source_id = 1 AND source_activity_id = 'concurrent-identity'"
))
concurrent_orphans <- DBI::dbGetQuery(connection, paste(
  "SELECT COUNT(*) orphan_count",
  "FROM cycling_platform_silver.activity_identity identity_row",
  "LEFT JOIN cycling_platform_silver.activity_source_map mapping",
  "ON mapping.activity_key = identity_row.activity_key",
  "WHERE mapping.activity_key IS NULL"
))$orphan_count[[1L]]
stopifnot(
  concurrent_state$mapping_count == 1L,
  concurrent_state$key_count == 1L,
  concurrent_orphans == 0L,
  any(!grepl("^ERROR:", unlist(concurrent_results)))
)

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

# Exercise the real production publication boundary and transformation SQL.
insert_raw_activity <- function(activity_id, activity_name) {
  DBI::dbExecute(connection, paste(
    "INSERT INTO cycling_platform_raw.activities (",
    "activity_id, run_id, source_id, retrieved_at, raw_payload, athlete_id,",
    "activity_name, sport_type, start_datetime_utc, start_datetime_local,",
    "timezone_name, distance_metres, moving_time_seconds, elapsed_time_seconds,",
    "elevation_gain_metres, average_speed_metres_per_second, is_device_watts",
    ") VALUES (?, 1, 1, UTC_TIMESTAMP(),",
    "JSON_OBJECT('manual', false, 'trainer', false), 1, ?, 'Ride',",
    "'2026-01-01 10:00:00', '2026-01-01 10:00:00', 'Europe/London',",
    "10000, 1800, 1900, 100, 5.5, 0)"
  ), params = list(activity_id, activity_name))
}
insert_raw_activity(200, "Real publication initial")
rebuild_silver_activities(connection, activity_ids = bit64::as.integer64("200"))
real_first <- DBI::dbGetQuery(connection, paste(
  "SELECT activity.activity_name, mapping.activity_key, mapping.mapping_method,",
  "identity_row.identity_origin",
  "FROM cycling_platform_silver.activities activity",
  "JOIN cycling_platform_silver.activity_source_map mapping",
  "ON mapping.source_id = activity.source_id",
  "AND mapping.source_activity_id = CAST(CAST(activity.activity_id AS CHAR) AS BINARY)",
  "JOIN cycling_platform_silver.activity_identity identity_row",
  "ON identity_row.activity_key = mapping.activity_key",
  "WHERE activity.activity_id = 200"
))
stopifnot(
  nrow(real_first) == 1L,
  real_first$mapping_method == "SOURCE_ALLOCATION",
  real_first$identity_origin == "SOURCE_ALLOCATION"
)
real_key_200 <- real_first$activity_key[[1L]]

DBI::dbExecute(connection, paste(
  "UPDATE cycling_platform_raw.activities",
  "SET activity_name = 'Real publication refreshed' WHERE activity_id = 200"
))
rebuild_silver_activities(connection, activity_ids = bit64::as.integer64("200"))
real_refresh <- DBI::dbGetQuery(connection, paste(
  "SELECT activity.activity_name, mapping.activity_key, mapping.mapping_method",
  "FROM cycling_platform_silver.activities activity",
  "JOIN cycling_platform_silver.activity_source_map mapping",
  "ON mapping.source_id = activity.source_id",
  "AND mapping.source_activity_id = CAST(CAST(activity.activity_id AS CHAR) AS BINARY)",
  "WHERE activity.activity_id = 200"
))
stopifnot(
  real_refresh$activity_name == "Real publication refreshed",
  identical(real_refresh$activity_key[[1L]], real_key_200),
  real_refresh$mapping_method == "SOURCE_ALLOCATION"
)

# A test-local Silver INSERT trigger fails after the production DELETE and proves
# that the previously committed row is restored by the real transaction.
DBI::dbExecute(connection, paste(
  "CREATE TRIGGER cycling_platform_silver.test_real_reconstruction_failure",
  "BEFORE INSERT ON cycling_platform_silver.activities FOR EACH ROW",
  "BEGIN IF NEW.activity_id = 200 THEN SIGNAL SQLSTATE '45000'",
  "SET MESSAGE_TEXT = 'synthetic reconstruction failure'; END IF; END"
))
DBI::dbExecute(connection, paste(
  "UPDATE cycling_platform_raw.activities",
  "SET activity_name = 'Must roll back' WHERE activity_id = 200"
))
real_reconstruction_failed <- tryCatch({
  rebuild_silver_activities(connection, activity_ids = bit64::as.integer64("200"))
  FALSE
}, error = function(error) TRUE)
DBI::dbExecute(connection,
  "DROP TRIGGER cycling_platform_silver.test_real_reconstruction_failure"
)
stopifnot(
  real_reconstruction_failed,
  DBI::dbGetQuery(connection, paste(
    "SELECT activity_name FROM cycling_platform_silver.activities",
    "WHERE activity_id = 200"
  ))$activity_name == "Real publication refreshed"
)

# Mapping failure rolls back the real Silver INSERT and newly allocated identity.
insert_raw_activity(201, "Mapping failure")
DBI::dbExecute(connection, paste(
  "CREATE TRIGGER cycling_platform_silver.test_real_mapping_failure",
  "BEFORE INSERT ON cycling_platform_silver.activity_source_map FOR EACH ROW",
  "BEGIN IF NEW.source_activity_id = '201' THEN SIGNAL SQLSTATE '45000'",
  "SET MESSAGE_TEXT = 'synthetic real mapping failure'; END IF; END"
))
real_mapping_failed <- tryCatch({
  rebuild_silver_activities(connection, activity_ids = bit64::as.integer64("201"))
  FALSE
}, error = function(error) TRUE)
DBI::dbExecute(connection,
  "DROP TRIGGER cycling_platform_silver.test_real_mapping_failure"
)
stopifnot(
  real_mapping_failed,
  DBI::dbGetQuery(connection, paste(
    "SELECT COUNT(*) n FROM cycling_platform_silver.activities WHERE activity_id = 201"
  ))$n == 0L,
  DBI::dbGetQuery(connection, paste(
    "SELECT COUNT(*) n FROM cycling_platform_silver.activity_source_map",
    "WHERE source_activity_id = '201'"
  ))$n == 0L
)

# Test-local wrapper fails only after production identity resolution returns,
# proving rollback after successful allocation but before transaction commit.
insert_raw_activity(202, "Post-allocation failure")
original_ensure <- ensure_published_activity_identities
assign(
  "ensure_published_activity_identities",
  function(connection) {
    result <- original_ensure(connection)
    stop("synthetic post-allocation failure", call. = FALSE)
    result
  },
  envir = .GlobalEnv
)
real_post_allocation_failed <- tryCatch({
  rebuild_silver_activities(connection, activity_ids = bit64::as.integer64("202"))
  FALSE
}, error = function(error) TRUE)
assign("ensure_published_activity_identities", original_ensure,
       envir = .GlobalEnv)
stopifnot(
  real_post_allocation_failed,
  DBI::dbGetQuery(connection, paste(
    "SELECT COUNT(*) n FROM cycling_platform_silver.activities WHERE activity_id = 202"
  ))$n == 0L,
  DBI::dbGetQuery(connection, paste(
    "SELECT COUNT(*) n FROM cycling_platform_silver.activity_source_map",
    "WHERE source_activity_id = '202'"
  ))$n == 0L
)

# Subsequent execution succeeds after each controlled failure.
rebuild_silver_activities(
  connection, activity_ids = bit64::as.integer64(c("200", "201", "202"))
)
real_recovery <- DBI::dbGetQuery(connection, paste(
  "SELECT COUNT(*) activity_count, COUNT(mapping.activity_key) mapping_count",
  "FROM cycling_platform_silver.activities activity",
  "LEFT JOIN cycling_platform_silver.activity_source_map mapping",
  "ON mapping.source_id = activity.source_id",
  "AND mapping.source_activity_id = CAST(CAST(activity.activity_id AS CHAR) AS BINARY)",
  "WHERE activity.activity_id IN (200, 201, 202)"
))
stopifnot(
  real_recovery$activity_count == 3L,
  real_recovery$mapping_count == 3L,
  identical(
    DBI::dbGetQuery(connection, paste(
      "SELECT activity_key FROM cycling_platform_silver.activity_source_map",
      "WHERE source_activity_id = '200'"
    ))$activity_key[[1L]],
    real_key_200
  )
)

# Runtime publication fails closed and does not recreate a missing safeguard.
DBI::dbExecute(connection, paste(
  "DROP TRIGGER cycling_platform_silver.trg_activity_identity_immutable_delete"
))
missing_trigger_failed <- tryCatch({
  rebuild_silver_activities(connection, activity_ids = bit64::as.integer64("200"))
  FALSE
}, error = function(error) grepl(
  "immutability triggers are missing or invalid", conditionMessage(error),
  fixed = TRUE
))
missing_trigger_count <- DBI::dbGetQuery(connection, paste(
  "SELECT COUNT(*) n FROM information_schema.triggers",
  "WHERE trigger_schema = 'cycling_platform_silver'",
  "AND trigger_name = 'trg_activity_identity_immutable_delete'"
))$n[[1L]]
stopifnot(missing_trigger_failed, missing_trigger_count == 0L)
run_statements("sql/silver/090_create_activity_identity_immutability_triggers.sql")
assert_canonical_activity_identity_immutability(connection)

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
  "VALUES (1, 'unexpected-policy', ?, 'STRAVA_BACKFILL')"
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
  diagnostic_count[["historical_mapping_without_published_activity"]] == 3L,
  diagnostic_status[["historical_mapping_without_published_activity"]] ==
    "EXPECTED_HISTORICAL",
  orphan_key > 0
)

# Measure the real full-population publication path with established mappings.
performance_size <- 4000L
performance_ids <- bit64::as.integer64(
  as.character(100000L + seq_len(performance_size))
)
performance_time <- as.POSIXct(
  rep("2026-01-02 10:00:00", performance_size), tz = "UTC"
)
performance_rows <- data.frame(
  activity_id = performance_ids,
  run_id = bit64::as.integer64(rep("1", performance_size)),
  source_id = rep(1L, performance_size),
  retrieved_at = performance_time,
  raw_payload = rep('{"manual":false,"trainer":false}', performance_size),
  activity_name = paste("Performance activity", seq_len(performance_size)),
  sport_type = rep("Ride", performance_size),
  start_datetime_utc = performance_time,
  start_datetime_local = performance_time,
  timezone_name = rep("Europe/London", performance_size),
  distance_metres = rep(10000, performance_size),
  moving_time_seconds = rep(1800L, performance_size),
  elapsed_time_seconds = rep(1900L, performance_size),
  elevation_gain_metres = rep(100, performance_size),
  average_speed_metres_per_second = rep(5.5, performance_size),
  is_device_watts = rep(FALSE, performance_size),
  stringsAsFactors = FALSE
)
DBI::dbAppendTable(
  connection,
  DBI::Id(schema = "cycling_platform_raw", table = "activities"),
  performance_rows
)
# Warm-up establishes all mappings before either measured refresh.
rebuild_silver_activities(connection, activity_ids = NULL)

original_ensure_performance <- ensure_published_activity_identities
assign(
  "ensure_published_activity_identities",
  function(connection) invisible(integer()),
  envir = .GlobalEnv
)
baseline_timing <- system.time(
  rebuild_silver_activities(connection, activity_ids = NULL)
)[["elapsed"]]
assign(
  "ensure_published_activity_identities", original_ensure_performance,
  envir = .GlobalEnv
)

mapping_lookup_count <- 0L
original_resolve_performance <- resolve_or_allocate_canonical_activity_identity
assign(
  "resolve_or_allocate_canonical_activity_identity",
  function(...) {
    mapping_lookup_count <<- mapping_lookup_count + 1L
    original_resolve_performance(...)
  },
  envir = .GlobalEnv
)
identity_timing <- system.time(
  rebuild_silver_activities(connection, activity_ids = NULL)
)[["elapsed"]]
assign(
  "resolve_or_allocate_canonical_activity_identity",
  original_resolve_performance,
  envir = .GlobalEnv
)
performance_version <- DBI::dbGetQuery(connection, "SELECT VERSION() version")$
  version[[1L]]
message(
  "Canonical identity publication performance: mariadb=", performance_version,
  " activities=", mapping_lookup_count,
  " baseline_elapsed_seconds=", round(baseline_timing, 3),
  " identity_elapsed_seconds=", round(identity_timing, 3),
  " identity_overhead_seconds=", round(identity_timing - baseline_timing, 3)
)
stopifnot(
  mapping_lookup_count == performance_size + 3L,
  DBI::dbGetQuery(connection, paste(
    "SELECT COUNT(*) n FROM cycling_platform_silver.activity_source_map mapping",
    "JOIN cycling_platform_silver.activities activity",
    "ON mapping.source_id = activity.source_id",
    "AND mapping.source_activity_id = CAST(CAST(activity.activity_id AS CHAR) AS BINARY)",
    "WHERE activity.activity_id >= 100001 AND activity.activity_id <= 104000"
  ))$n == performance_size
)

# Fresh-bootstrap definitions independently create the same usable contract.
silver_count_before_fresh <- DBI::dbGetQuery(connection, paste(
  "SELECT COUNT(*) n FROM cycling_platform_silver.activities"
))$n[[1L]]
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
stopifnot(
  fresh$mapped_count == silver_count_before_fresh,
  fresh$allocation_count == 0L
)
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

# Disposable logical dump/restore preserves identity state and enforcement.
dump_binary <- Sys.which("mariadb-dump")
if (!nzchar(dump_binary)) dump_binary <- Sys.which("mysqldump")
restore_binary <- Sys.which("mariadb")
if (!nzchar(dump_binary) || !nzchar(restore_binary)) {
  stop("MariaDB dump and restore clients are required for identity integration.")
}
identity_before_restore <- DBI::dbGetQuery(connection, paste(
  "SELECT CAST(activity_key AS CHAR) activity_key, identity_status,",
  "identity_origin, DATE_FORMAT(created_at_utc, '%Y-%m-%d %H:%i:%s') created_at_utc,",
  "DATE_FORMAT(updated_at_utc, '%Y-%m-%d %H:%i:%s') updated_at_utc",
  "FROM cycling_platform_silver.activity_identity ORDER BY activity_key"
))
mapping_before_restore <- DBI::dbGetQuery(connection, paste(
  "SELECT source_id, HEX(source_activity_id) source_activity_id_hex,",
  "CAST(activity_key AS CHAR) activity_key, mapping_method,",
  "DATE_FORMAT(mapped_at_utc, '%Y-%m-%d %H:%i:%s') mapped_at_utc",
  "FROM cycling_platform_silver.activity_source_map",
  "ORDER BY source_id, source_activity_id"
))
dump_file <- tempfile("canonical-identity-", fileext = ".sql")
dump_error <- tempfile("canonical-identity-dump-", fileext = ".log")
restore_error <- tempfile("canonical-identity-restore-", fileext = ".log")
client_environment <- paste0("MYSQL_PWD=", config$password)
dump_status <- system2(
  dump_binary,
  args = c(
    paste0("--host=", config$host), paste0("--port=", config$port),
    paste0("--user=", config$user), "--single-transaction", "--routines",
    "--triggers", "cycling_platform_silver"
  ),
  stdout = dump_file,
  stderr = dump_error,
  env = client_environment
)
stopifnot(identical(dump_status, 0L), file.info(dump_file)$size > 0)
dump_text <- readLines(dump_file, warn = FALSE)
stopifnot(all(vapply(
  CANONICAL_ACTIVITY_IMMUTABILITY_TRIGGERS$trigger_name,
  function(trigger_name) any(grepl(trigger_name, dump_text, fixed = TRUE)),
  logical(1)
)))
current_account <- DBI::dbGetQuery(connection, "SELECT CURRENT_USER() account")$
  account[[1L]]
if (identical(current_account, "@")) {
  message(paste(
    "Skipping restore assertion: disposable server uses --skip-grant-tables",
    "and emits an invalid anonymous trigger definer; named-account restore",
    "remains an acceptance gate."
  ))
} else {
  DBI::dbExecute(connection, "USE cycling_platform_admin")
  DBI::dbExecute(connection, "DROP DATABASE cycling_platform_silver")
  DBI::dbExecute(connection, "CREATE DATABASE cycling_platform_silver")
  restore_status <- system2(
    restore_binary,
    args = c(
      paste0("--host=", config$host), paste0("--port=", config$port),
      paste0("--user=", config$user), "cycling_platform_silver"
    ),
    stdout = TRUE,
    stderr = restore_error,
    input = dump_text,
    env = client_environment
  )
  restore_exit_status <- attr(restore_status, "status") %||% 0L
  if (!identical(restore_exit_status, 0L)) {
    restore_detail <- if (file.exists(restore_error)) {
      paste(readLines(restore_error, warn = FALSE), collapse = "\n")
    } else {
      "No restore diagnostic was produced."
    }
    stop(
      "Disposable canonical identity restore failed: ", restore_detail,
      call. = FALSE
    )
  }
  DBI::dbExecute(connection, "USE cycling_platform_silver")
  identity_after_restore <- DBI::dbGetQuery(connection, paste(
    "SELECT CAST(activity_key AS CHAR) activity_key, identity_status,",
    "identity_origin, DATE_FORMAT(created_at_utc, '%Y-%m-%d %H:%i:%s') created_at_utc,",
    "DATE_FORMAT(updated_at_utc, '%Y-%m-%d %H:%i:%s') updated_at_utc",
    "FROM cycling_platform_silver.activity_identity ORDER BY activity_key"
  ))
  mapping_after_restore <- DBI::dbGetQuery(connection, paste(
    "SELECT source_id, HEX(source_activity_id) source_activity_id_hex,",
    "CAST(activity_key AS CHAR) activity_key, mapping_method,",
    "DATE_FORMAT(mapped_at_utc, '%Y-%m-%d %H:%i:%s') mapped_at_utc",
    "FROM cycling_platform_silver.activity_source_map",
    "ORDER BY source_id, source_activity_id"
  ))
  stopifnot(
    identical(identity_before_restore, identity_after_restore),
    identical(mapping_before_restore, mapping_after_restore)
  )
  assert_canonical_activity_identity_immutability(connection)
  restored_key <- identity_after_restore$activity_key[[1L]]
  stopifnot(expect_db_error(paste(
    "UPDATE cycling_platform_silver.activity_identity",
    "SET activity_key = activity_key + 1 WHERE activity_key = ?"
  ), list(restored_key)))
}
unlink(c(dump_file, dump_error, restore_error))
DBI::dbDisconnect(second_connection)
cleanup()
DBI::dbDisconnect(connection)
message("Canonical activity identity MariaDB integration test passed.")
