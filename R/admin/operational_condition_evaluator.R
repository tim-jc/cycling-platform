OPERATIONAL_DEBT_CATALOGUE_VERSION <- "operational-debt-v1"
OPERATIONAL_CONDITION_EVALUATOR_LOCK <-
  "cycling-platform-operational-condition-evaluator"

operational_debt_expected_catalogue <- function() {
  data.frame(
    debt_domain = c(
      "BACKUP", "EXECUTION", "EXECUTION", "EXECUTION", "GOLD",
      "NOTIFICATION", "NOTIFICATION", "NOTIFICATION", "RAW", "RAW",
      "RAW", "RAW", "VALIDATION"
    ),
    debt_key = c(
      "backup", "latest_daily_pipeline", "stale_child_execution",
      "stale_pipeline_execution", "achievement_evaluation",
      "notification_pending", "notification_retry_or_failed",
      "notification_stale_sending", "google_health_daily_ingestion_coverage",
      "raw_activity_details", "raw_activity_laps", "raw_activity_streams",
      "latest_validation"
    ),
    stringsAsFactors = FALSE
  )
}

read_operational_debt_catalogue <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT debt_key, debt_domain, health_status, item_count, summary,",
      "observed_at_utc",
      "FROM cycling_platform_admin.v_operational_debt_latest"
    )
  )
}

validate_operational_debt_catalogue <- function(
  catalogue,
  expected = operational_debt_expected_catalogue()
) {
  required <- c(
    "debt_key", "debt_domain", "health_status", "item_count", "summary",
    "observed_at_utc"
  )
  missing_columns <- setdiff(required, names(catalogue))
  if (length(missing_columns)) {
    stop(
      "Operational debt catalogue is missing column(s): ",
      paste(missing_columns, collapse = ", "),
      call. = FALSE
    )
  }
  catalogue <- catalogue[, required, drop = FALSE]
  text_columns <- c("debt_key", "debt_domain", "health_status", "summary")
  for (column in text_columns) catalogue[[column]] <- as.character(catalogue[[column]])
  catalogue$item_count <- suppressWarnings(as.numeric(catalogue$item_count))
  if (!inherits(catalogue$observed_at_utc, "POSIXt")) {
    catalogue$observed_at_utc <- as.POSIXct(
      catalogue$observed_at_utc, tz = "UTC"
    )
  }
  invalid_required <- is.na(catalogue$debt_key) | !nzchar(catalogue$debt_key) |
    is.na(catalogue$debt_domain) | !nzchar(catalogue$debt_domain) |
    is.na(catalogue$health_status) | !nzchar(catalogue$health_status) |
    is.na(catalogue$item_count) | catalogue$item_count < 0 |
    catalogue$item_count != floor(catalogue$item_count) |
    is.na(catalogue$summary) | !nzchar(catalogue$summary) |
    is.na(catalogue$observed_at_utc)
  if (any(invalid_required)) {
    stop("Operational debt catalogue contains malformed row(s).", call. = FALSE)
  }
  allowed_status <- c("HEALTHY", "INFO", "UNKNOWN", "WARNING", "CRITICAL")
  unexpected_status <- setdiff(unique(catalogue$health_status), allowed_status)
  if (length(unexpected_status)) {
    stop(
      "Operational debt catalogue contains unsupported health status: ",
      paste(unexpected_status, collapse = ", "),
      call. = FALSE
    )
  }
  identity <- paste(catalogue$debt_domain, catalogue$debt_key, sep = "|")
  if (anyDuplicated(identity)) {
    stop(
      "Operational debt catalogue contains duplicate condition identity: ",
      paste(unique(identity[duplicated(identity) | duplicated(identity, fromLast = TRUE)]),
            collapse = ", "),
      call. = FALSE
    )
  }
  expected_identity <- paste(expected$debt_domain, expected$debt_key, sep = "|")
  missing_identity <- setdiff(expected_identity, identity)
  unexpected_identity <- setdiff(identity, expected_identity)
  if (length(missing_identity) || length(unexpected_identity)) {
    stop(
      "Operational debt catalogue identity mismatch. Missing: ",
      if (length(missing_identity)) paste(missing_identity, collapse = ", ") else "none",
      "; unexpected: ",
      if (length(unexpected_identity)) paste(unexpected_identity, collapse = ", ") else "none",
      call. = FALSE
    )
  }
  catalogue$item_count <- as.integer(catalogue$item_count)
  catalogue[order(catalogue$debt_domain, catalogue$debt_key), , drop = FALSE]
}

operational_condition_evidence_signature <- function(observation) {
  digest::digest(
    paste(
      OPERATIONAL_DEBT_CATALOGUE_VERSION,
      observation$debt_domain[[1L]], observation$debt_key[[1L]],
      observation$health_status[[1L]], observation$item_count[[1L]],
      observation$summary[[1L]], sep = "\x1f"
    ),
    algo = "sha256", serialize = FALSE
  )
}

operational_condition_is_actionable <- function(status) {
  status %in% c("WARNING", "CRITICAL")
}

derive_operational_condition_transition <- function(observation, state = NULL) {
  status <- as.character(observation$health_status[[1L]])
  if (!status %in% c("HEALTHY", "INFO", "UNKNOWN", "WARNING", "CRITICAL")) {
    stop("Cannot derive a transition for unsupported health status.", call. = FALSE)
  }
  state_exists <- !is.null(state) && nrow(state) == 1L
  active <- state_exists && !is.na(state$active_incident_id[[1L]])
  last_actionable <- if (state_exists) {
    as.character(state$last_actionable_severity[[1L]])
  } else {
    NA_character_
  }
  if (!state_exists) {
    event <- if (operational_condition_is_actionable(status)) "INCIDENT_OPENED" else "NONE"
  } else if (!active) {
    event <- if (operational_condition_is_actionable(status)) "INCIDENT_OPENED" else "NONE"
  } else if (identical(status, "HEALTHY")) {
    event <- "INCIDENT_RECOVERED"
  } else if (!operational_condition_is_actionable(status)) {
    event <- "NONE"
  } else if (identical(status, last_actionable)) {
    event <- "NONE"
  } else if (identical(last_actionable, "WARNING") && identical(status, "CRITICAL")) {
    event <- "SEVERITY_ESCALATED"
  } else {
    event <- "SEVERITY_CHANGED"
  }
  data.frame(
    transition_event = event,
    from_severity = if (active) last_actionable else NA_character_,
    to_severity = status,
    opens_incident = identical(event, "INCIDENT_OPENED"),
    closes_incident = identical(event, "INCIDENT_RECOVERED"),
    updates_actionable_severity = operational_condition_is_actionable(status),
    stringsAsFactors = FALSE
  )
}

read_operational_condition_state <- function(
  connection,
  catalogue_version,
  debt_domain,
  debt_key,
  for_update = FALSE
) {
  sql <- paste(
    "SELECT catalogue_version, debt_domain, debt_key,",
    "last_observed_health_status, last_observed_item_count,",
    "last_observed_summary, last_observed_at_utc, evidence_signature,",
    "active_incident_id, last_actionable_severity,",
    "first_evaluated_at_utc, last_evaluated_at_utc",
    "FROM cycling_platform_admin.operational_condition_state",
    "WHERE catalogue_version = ? AND debt_domain = ? AND debt_key = ?",
    if (isTRUE(for_update)) "FOR UPDATE" else ""
  )
  DBI::dbGetQuery(
    connection, sql,
    params = list(catalogue_version, debt_domain, debt_key)
  )
}

read_all_operational_condition_state <- function(connection) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT catalogue_version, debt_domain, debt_key,",
      "last_observed_health_status, last_observed_item_count,",
      "last_observed_summary, last_observed_at_utc, evidence_signature,",
      "active_incident_id, last_actionable_severity,",
      "first_evaluated_at_utc, last_evaluated_at_utc",
      "FROM cycling_platform_admin.operational_condition_state",
      "WHERE catalogue_version = ?"
    ),
    params = list(OPERATIONAL_DEBT_CATALOGUE_VERSION)
  )
}

preview_operational_condition_evaluation <- function(connection) {
  catalogue <- validate_operational_debt_catalogue(
    read_operational_debt_catalogue(connection)
  )
  states <- read_all_operational_condition_state(connection)
  plans <- lapply(seq_len(nrow(catalogue)), function(index) {
    observation <- catalogue[index, , drop = FALSE]
    state <- states[
      states$debt_domain == observation$debt_domain[[1L]] &
        states$debt_key == observation$debt_key[[1L]],
      , drop = FALSE
    ]
    transition <- derive_operational_condition_transition(observation, state)
    data.frame(
      catalogue_version = OPERATIONAL_DEBT_CATALOGUE_VERSION,
      observation,
      active_incident_id = if (nrow(state)) state$active_incident_id[[1L]] else NA,
      last_actionable_severity = if (nrow(state)) {
        state$last_actionable_severity[[1L]]
      } else {
        NA_character_
      },
      evidence_signature = operational_condition_evidence_signature(observation),
      transition,
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  })
  result <- do.call(rbind, plans)
  rownames(result) <- NULL
  result
}

acquire_operational_condition_evaluator_lock <- function(connection, timeout_seconds) {
  result <- DBI::dbGetQuery(
    connection,
    "SELECT GET_LOCK(?, ?) AS acquired",
    params = list(OPERATIONAL_CONDITION_EVALUATOR_LOCK, as.integer(timeout_seconds))
  )
  if (nrow(result) != 1L || is.na(result$acquired[[1L]]) || result$acquired[[1L]] != 1L) {
    stop("Could not acquire the operational-condition evaluator lock.", call. = FALSE)
  }
  invisible(TRUE)
}

release_operational_condition_evaluator_lock <- function(connection) {
  try(
    DBI::dbGetQuery(
      connection,
      "SELECT RELEASE_LOCK(?) AS released",
      params = list(OPERATIONAL_CONDITION_EVALUATOR_LOCK)
    ),
    silent = TRUE
  )
  invisible(NULL)
}

insert_operational_condition_incident <- function(connection, observation) {
  next_number <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT COALESCE(MAX(incident_number), 0) + 1 AS incident_number",
      "FROM cycling_platform_admin.operational_condition_incident",
      "WHERE catalogue_version = ? AND debt_domain = ? AND debt_key = ?"
    ),
    params = list(
      OPERATIONAL_DEBT_CATALOGUE_VERSION,
      observation$debt_domain[[1L]], observation$debt_key[[1L]]
    )
  )$incident_number[[1L]]
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO cycling_platform_admin.operational_condition_incident (",
      "catalogue_version, debt_domain, debt_key, incident_number,",
      "incident_status, opening_severity, last_actionable_severity, opened_at_utc",
      ") VALUES (?, ?, ?, ?, 'ACTIVE', ?, ?, ?)"
    ),
    params = list(
      OPERATIONAL_DEBT_CATALOGUE_VERSION,
      observation$debt_domain[[1L]], observation$debt_key[[1L]],
      as.integer(next_number), observation$health_status[[1L]],
      observation$health_status[[1L]], observation$observed_at_utc[[1L]]
    )
  )
  as.numeric(DBI::dbGetQuery(connection, "SELECT LAST_INSERT_ID() AS incident_id")$incident_id[[1L]])
}

insert_operational_condition_event <- function(
  connection,
  incident_id,
  transition,
  observation,
  evidence_signature
) {
  next_sequence <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT COALESCE(MAX(incident_event_sequence), 0) + 1 AS event_sequence",
      "FROM cycling_platform_admin.operational_condition_event",
      "WHERE incident_id = ?"
    ),
    params = list(incident_id)
  )$event_sequence[[1L]]
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO cycling_platform_admin.operational_condition_event (",
      "incident_id, incident_event_sequence, event_type, from_severity,",
      "to_severity, observed_at_utc, item_count, summary, evidence_signature",
      ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
    ),
    params = list(
      incident_id, as.integer(next_sequence), transition$transition_event[[1L]],
      transition$from_severity[[1L]], transition$to_severity[[1L]],
      observation$observed_at_utc[[1L]], observation$item_count[[1L]],
      observation$summary[[1L]], evidence_signature
    )
  )
  invisible(as.integer(next_sequence))
}

persist_operational_condition_observation <- function(connection, observation) {
  state <- read_operational_condition_state(
    connection, OPERATIONAL_DEBT_CATALOGUE_VERSION,
    observation$debt_domain[[1L]], observation$debt_key[[1L]],
    for_update = TRUE
  )
  transition <- derive_operational_condition_transition(observation, state)
  signature <- operational_condition_evidence_signature(observation)
  if (!nrow(state)) {
    DBI::dbExecute(
      connection,
      paste(
        "INSERT INTO cycling_platform_admin.operational_condition_state (",
        "catalogue_version, debt_domain, debt_key, last_observed_health_status,",
        "last_observed_item_count, last_observed_summary, last_observed_at_utc,",
        "evidence_signature, active_incident_id, last_actionable_severity",
        ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)"
      ),
      params = list(
        OPERATIONAL_DEBT_CATALOGUE_VERSION,
        observation$debt_domain[[1L]], observation$debt_key[[1L]],
        observation$health_status[[1L]], observation$item_count[[1L]],
        observation$summary[[1L]], observation$observed_at_utc[[1L]], signature,
        if (operational_condition_is_actionable(observation$health_status[[1L]])) {
          observation$health_status[[1L]]
        } else {
          NA_character_
        }
      )
    )
  }
  incident_id <- if (nrow(state)) state$active_incident_id[[1L]] else NA
  event <- transition$transition_event[[1L]]
  if (identical(event, "INCIDENT_OPENED")) {
    incident_id <- insert_operational_condition_incident(connection, observation)
    insert_operational_condition_event(
      connection, incident_id, transition, observation, signature
    )
  } else if (event %in% c("SEVERITY_ESCALATED", "SEVERITY_CHANGED")) {
    incident <- DBI::dbGetQuery(
      connection,
      paste(
        "SELECT incident_id, incident_status",
        "FROM cycling_platform_admin.operational_condition_incident",
        "WHERE incident_id = ? FOR UPDATE"
      ),
      params = list(incident_id)
    )
    if (nrow(incident) != 1L || incident$incident_status[[1L]] != "ACTIVE") {
      stop("Active operational incident state is inconsistent.", call. = FALSE)
    }
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE cycling_platform_admin.operational_condition_incident",
        "SET last_actionable_severity = ? WHERE incident_id = ?"
      ),
      params = list(observation$health_status[[1L]], incident_id)
    )
    insert_operational_condition_event(
      connection, incident_id, transition, observation, signature
    )
  } else if (identical(event, "INCIDENT_RECOVERED")) {
    incident <- DBI::dbGetQuery(
      connection,
      paste(
        "SELECT incident_id, incident_status",
        "FROM cycling_platform_admin.operational_condition_incident",
        "WHERE incident_id = ? FOR UPDATE"
      ),
      params = list(incident_id)
    )
    if (nrow(incident) != 1L || incident$incident_status[[1L]] != "ACTIVE") {
      stop("Active operational incident state is inconsistent.", call. = FALSE)
    }
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE cycling_platform_admin.operational_condition_incident",
        "SET incident_status = 'CLOSED', closed_at_utc = ?",
        "WHERE incident_id = ?"
      ),
      params = list(observation$observed_at_utc[[1L]], incident_id)
    )
    insert_operational_condition_event(
      connection, incident_id, transition, observation, signature
    )
    incident_id <- NA
  }
  last_actionable <- if (nrow(state)) state$last_actionable_severity[[1L]] else NA_character_
  if (operational_condition_is_actionable(observation$health_status[[1L]])) {
    last_actionable <- observation$health_status[[1L]]
  }
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE cycling_platform_admin.operational_condition_state SET",
      "last_observed_health_status = ?, last_observed_item_count = ?,",
      "last_observed_summary = ?, last_observed_at_utc = ?, evidence_signature = ?,",
      "active_incident_id = ?, last_actionable_severity = ?,",
      "last_evaluated_at_utc = UTC_TIMESTAMP()",
      "WHERE catalogue_version = ? AND debt_domain = ? AND debt_key = ?"
    ),
    params = list(
      observation$health_status[[1L]], observation$item_count[[1L]],
      observation$summary[[1L]], observation$observed_at_utc[[1L]], signature,
      incident_id, last_actionable, OPERATIONAL_DEBT_CATALOGUE_VERSION,
      observation$debt_domain[[1L]], observation$debt_key[[1L]]
    )
  )
  data.frame(
    debt_domain = observation$debt_domain[[1L]],
    debt_key = observation$debt_key[[1L]],
    health_status = observation$health_status[[1L]],
    transition_event = event,
    active_incident_id = incident_id,
    stringsAsFactors = FALSE
  )
}

evaluate_operational_conditions <- function(connection, lock_timeout_seconds = 5L) {
  acquire_operational_condition_evaluator_lock(connection, lock_timeout_seconds)
  on.exit(release_operational_condition_evaluator_lock(connection), add = TRUE)

  # Catalogue retrieval and complete-contract validation happen before any write.
  catalogue <- validate_operational_debt_catalogue(
    read_operational_debt_catalogue(connection)
  )
  DBI::dbBegin(connection)
  committed <- FALSE
  on.exit({
    if (!committed) try(DBI::dbRollback(connection), silent = TRUE)
  }, add = TRUE)
  results <- lapply(seq_len(nrow(catalogue)), function(index) {
    persist_operational_condition_observation(
      connection, catalogue[index, , drop = FALSE]
    )
  })
  DBI::dbCommit(connection)
  committed <- TRUE
  result <- do.call(rbind, results)
  rownames(result) <- NULL
  result
}
