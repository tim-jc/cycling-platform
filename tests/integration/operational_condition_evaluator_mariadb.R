#!/usr/bin/env Rscript

# Disposable MariaDB integration test. The caller must provide a socket for a
# dedicated local test server; this script never uses platform runtime secrets.
socket <- Sys.getenv("CYCLING_PLATFORM_TEST_MARIADB_SOCKET")
if (!nzchar(socket) || !file.exists(socket)) {
  stop("CYCLING_PLATFORM_TEST_MARIADB_SOCKET must name a disposable MariaDB socket.")
}
socket <- normalizePath(socket, winslash = "/", mustWork = TRUE)
if (!grepl("^/private/tmp/cycling-condition-mariadb[.][^/]+/mariadb[.]sock$", socket)) {
  stop("Refusing to run against a socket outside the disposable test directory.")
}

source("R/database/execute_sql_file.R")
source("R/admin/operational_condition_evaluator.R")

root <- DBI::dbConnect(RMariaDB::MariaDB(), username = "root", unix.socket = socket)
server <- DBI::dbGetQuery(root, "SELECT @@skip_networking skip_networking, @@datadir datadir")
datadir <- normalizePath(server$datadir[[1L]], winslash = "/", mustWork = TRUE)
if (server$skip_networking[[1L]] != 1L ||
    !grepl("^/private/tmp/cycling-condition-mariadb[.][^/]+/data/?$", datadir)) {
  DBI::dbDisconnect(root)
  stop("Refusing to alter a MariaDB server that is not the disposable local fixture.")
}
DBI::dbExecute(root, "DROP DATABASE IF EXISTS cycling_platform_admin")
DBI::dbExecute(root, paste(
  "CREATE DATABASE cycling_platform_admin CHARACTER SET utf8mb4",
  "COLLATE utf8mb4_general_ci"
))
# Existing-schema upgrade: migration alone creates the new objects.
execute_sql_file("sql/migrations/019_add_operational_condition_state.sql", root)
DBI::dbExecute(root, "DROP TABLE cycling_platform_admin.operational_condition_event")
DBI::dbExecute(root, "DROP TABLE cycling_platform_admin.operational_condition_incident")
DBI::dbExecute(root, "DROP TABLE cycling_platform_admin.operational_condition_state")
# Fresh bootstrap: canonical DDL followed by the same immutable migration is safe.
execute_sql_file("sql/admin/110_create_operational_condition_state.sql", root)
execute_sql_file("sql/migrations/019_add_operational_condition_state.sql", root)
DBI::dbExecute(root, paste(
  "CREATE TABLE cycling_platform_admin.operational_debt_fixture (",
  "debt_key VARCHAR(100) NOT NULL, debt_domain VARCHAR(50) NOT NULL,",
  "health_status VARCHAR(20) NOT NULL, item_count BIGINT NOT NULL,",
  "summary VARCHAR(500) NOT NULL, observed_at_utc DATETIME NOT NULL,",
  "PRIMARY KEY (debt_domain, debt_key)) ENGINE=InnoDB",
  "DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci"
))
expected <- operational_debt_expected_catalogue()
for (index in seq_len(nrow(expected))) {
  DBI::dbExecute(
    root,
    paste(
      "INSERT INTO cycling_platform_admin.operational_debt_fixture",
      "VALUES (?, ?, 'HEALTHY', 0, ?, '2026-11-10 10:00:00')"
    ),
    params = list(
      expected$debt_key[[index]], expected$debt_domain[[index]],
      paste("fixture", expected$debt_key[[index]])
    )
  )
}
DBI::dbExecute(root, paste(
  "CREATE VIEW cycling_platform_admin.v_operational_debt_latest AS",
  "SELECT debt_key, debt_domain, health_status, item_count, summary,",
  "observed_at_utc FROM cycling_platform_admin.operational_debt_fixture"
))

condition_counts <- function(connection) {
  as.integer(c(
    state = DBI::dbGetQuery(connection, "SELECT COUNT(*) n FROM cycling_platform_admin.operational_condition_state")$n[[1L]],
    incident = DBI::dbGetQuery(connection, "SELECT COUNT(*) n FROM cycling_platform_admin.operational_condition_incident")$n[[1L]],
    event = DBI::dbGetQuery(connection, "SELECT COUNT(*) n FROM cycling_platform_admin.operational_condition_event")$n[[1L]]
  )) |> stats::setNames(c("state", "incident", "event"))
}
set_condition <- function(connection, domain, key, status, count = 1L) {
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE cycling_platform_admin.operational_debt_fixture",
      "SET health_status = ?, item_count = ?, observed_at_utc = observed_at_utc + INTERVAL 1 MINUTE",
      "WHERE debt_domain = ? AND debt_key = ?"
    ),
    params = list(status, count, domain, key)
  )
}

# Initial HEALTHY catalogue creates baseline state only.
initial <- evaluate_operational_conditions(root)
stopifnot(nrow(initial) == 13L, all(condition_counts(root) == c(state = 13, incident = 0, event = 0)))

# Preview is genuinely read-only.
before_preview <- condition_counts(root)
preview <- preview_operational_condition_evaluation(root)
stopifnot(nrow(preview) == 13L, all(condition_counts(root) == before_preview))

# Open, repeat, UNKNOWN, downgrade, recover, and recur.
set_condition(root, "EXECUTION", "latest_daily_pipeline", "CRITICAL")
invisible(evaluate_operational_conditions(root))
stopifnot(all(condition_counts(root) == c(state = 13, incident = 1, event = 1)))
invisible(evaluate_operational_conditions(root))
stopifnot(all(condition_counts(root) == c(state = 13, incident = 1, event = 1)))
set_condition(root, "EXECUTION", "latest_daily_pipeline", "UNKNOWN")
invisible(evaluate_operational_conditions(root))
stopifnot(all(condition_counts(root) == c(state = 13, incident = 1, event = 1)))
set_condition(root, "EXECUTION", "latest_daily_pipeline", "WARNING")
invisible(evaluate_operational_conditions(root))
set_condition(root, "EXECUTION", "latest_daily_pipeline", "HEALTHY", 0L)
invisible(evaluate_operational_conditions(root))
set_condition(root, "EXECUTION", "latest_daily_pipeline", "WARNING")
invisible(evaluate_operational_conditions(root))
stopifnot(all(condition_counts(root) == c(state = 13, incident = 2, event = 4)))
events <- DBI::dbGetQuery(root, paste(
  "SELECT incident_id, incident_event_sequence, event_type",
  "FROM cycling_platform_admin.operational_condition_event ORDER BY event_id"
))
stopifnot(
  identical(events$event_type, c(
    "INCIDENT_OPENED", "SEVERITY_CHANGED", "INCIDENT_RECOVERED", "INCIDENT_OPENED"
  )),
  identical(events$incident_event_sequence, c(1L, 2L, 3L, 1L))
)

# A second evaluator cannot pass the named lock and cannot persist anything.
second <- DBI::dbConnect(RMariaDB::MariaDB(), username = "root", unix.socket = socket)
acquire_operational_condition_evaluator_lock(root, 0L)
before_locked_attempt <- condition_counts(root)
lock_error <- try(evaluate_operational_conditions(second, 0L), silent = TRUE)
release_operational_condition_evaluator_lock(root)
stopifnot(inherits(lock_error, "try-error"), all(condition_counts(root) == before_locked_attempt))

# Force an inconsistent active incident after another condition would have been
# observed. The evaluator must roll the whole transaction back.
set_condition(root, "RAW", "raw_activity_details", "WARNING")
invisible(evaluate_operational_conditions(root))
DBI::dbExecute(root, paste(
  "UPDATE cycling_platform_admin.operational_condition_state",
  "SET active_incident_id = 999999, last_actionable_severity = 'WARNING'",
  "WHERE debt_domain = 'RAW' AND debt_key = 'raw_activity_details'"
))
set_condition(root, "RAW", "raw_activity_details", "CRITICAL")
state_before_failure <- DBI::dbGetQuery(root, paste(
  "SELECT * FROM cycling_platform_admin.operational_condition_state",
  "ORDER BY debt_domain, debt_key"
))
failure <- try(evaluate_operational_conditions(root), silent = TRUE)
state_after_failure <- DBI::dbGetQuery(root, paste(
  "SELECT * FROM cycling_platform_admin.operational_condition_state",
  "ORDER BY debt_domain, debt_key"
))
stopifnot(inherits(failure, "try-error"), identical(state_after_failure, state_before_failure))

DBI::dbDisconnect(second)
DBI::dbDisconnect(root)
cat("Disposable MariaDB operational-condition integration tests passed.\n")
