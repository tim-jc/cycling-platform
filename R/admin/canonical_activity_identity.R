CANONICAL_ACTIVITY_BACKFILL_LOCK <-
  "cycling-platform-canonical-activity-identity-backfill"
CANONICAL_ACTIVITY_BACKFILL_OWNER <- "canonical-activity-identity-backfill"
CANONICAL_ACTIVITY_IMMUTABILITY_TRIGGERS <- data.frame(
  trigger_name = c(
    "trg_activity_identity_immutable_delete",
    "trg_activity_identity_immutable_update",
    "trg_activity_source_map_immutable_delete",
    "trg_activity_source_map_immutable_update"
  ),
  event_manipulation = c("DELETE", "UPDATE", "DELETE", "UPDATE"),
  event_object_table = c(
    "activity_identity", "activity_identity",
    "activity_source_map", "activity_source_map"
  ),
  stringsAsFactors = FALSE
)

assert_canonical_activity_identity_immutability <- function(connection) {
  actual <- DBI::dbGetQuery(connection, paste(
    "SELECT trigger_name, event_manipulation, event_object_table,",
    "action_timing, action_statement",
    "FROM information_schema.triggers",
    "WHERE trigger_schema = 'cycling_platform_silver'",
    "AND trigger_name IN (",
    paste0(
      "'", CANONICAL_ACTIVITY_IMMUTABILITY_TRIGGERS$trigger_name, "'",
      collapse = ", "
    ),
    ") ORDER BY trigger_name"
  ))
  expected <- CANONICAL_ACTIVITY_IMMUTABILITY_TRIGGERS[order(
    CANONICAL_ACTIVITY_IMMUTABILITY_TRIGGERS$trigger_name
  ), , drop = FALSE]
  actual_contract <- actual[, names(expected), drop = FALSE]
  contract_matches <- nrow(actual) == nrow(expected) &&
    identical(as.character(actual_contract$trigger_name), expected$trigger_name) &&
    identical(
      as.character(actual_contract$event_manipulation),
      expected$event_manipulation
    ) &&
    identical(
      as.character(actual_contract$event_object_table),
      expected$event_object_table
    ) &&
    all(as.character(actual$action_timing) == "BEFORE") &&
    all(grepl("SIGNAL SQLSTATE", as.character(actual$action_statement), fixed = TRUE))
  if (!contract_matches) {
    stop(
      "Canonical activity identity immutability triggers are missing or invalid; ",
      "refusing Silver activity publication. Run governed schema recovery.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

read_canonical_activity_backfill_candidates <- function(connection) {
  DBI::dbGetQuery(connection, paste(
    "SELECT a.source_id, CAST(a.activity_id AS CHAR) AS source_activity_id,",
    "m.activity_key, ds.source_name",
    "FROM cycling_platform_silver.activities a",
    "JOIN cycling_platform_admin.data_source ds ON ds.source_id = a.source_id",
    "LEFT JOIN cycling_platform_silver.activity_source_map m",
    "ON m.source_id = a.source_id",
    "AND m.source_activity_id = CAST(CAST(a.activity_id AS CHAR) AS BINARY)",
    "ORDER BY a.activity_id"
  ))
}

validate_canonical_activity_backfill_candidates <- function(candidates) {
  required <- c("source_id", "source_activity_id", "activity_key", "source_name")
  missing <- setdiff(required, names(candidates))
  if (length(missing)) {
    stop("Canonical activity backfill candidates are missing: ",
         paste(missing, collapse = ", "), call. = FALSE)
  }
  if (anyNA(candidates$source_id) || anyNA(candidates$source_activity_id) ||
      any(!nzchar(as.character(candidates$source_activity_id)))) {
    stop("Canonical activity backfill contains an invalid source identity.",
         call. = FALSE)
  }
  if (any(as.character(candidates$source_name) != "strava")) {
    stop("Initial canonical activity backfill only supports Strava Silver activities.",
         call. = FALSE)
  }
  identity <- paste(candidates$source_id, candidates$source_activity_id, sep = "|")
  if (anyDuplicated(identity)) {
    stop("Canonical activity backfill contains duplicate source identities.",
         call. = FALSE)
  }
  candidates
}

preview_canonical_activity_identity_backfill <- function(connection) {
  candidates <- validate_canonical_activity_backfill_candidates(
    read_canonical_activity_backfill_candidates(connection)
  )
  data.frame(
    silver_activity_count = nrow(candidates),
    mapped_count = sum(!is.na(candidates$activity_key)),
    allocation_count = sum(is.na(candidates$activity_key)),
    stringsAsFactors = FALSE
  )
}

acquire_canonical_activity_backfill_lock <- function(connection, timeout_seconds) {
  result <- DBI::dbGetQuery(
    connection, "SELECT GET_LOCK(?, ?) AS acquired",
    params = list(CANONICAL_ACTIVITY_BACKFILL_LOCK, as.integer(timeout_seconds))
  )
  if (!identical(as.integer(result$acquired[[1L]]), 1L)) {
    stop("Could not acquire canonical activity backfill lock.", call. = FALSE)
  }
}

release_named_advisory_lock <- function(connection, lock_name) {
  result <- DBI::dbGetQuery(
    connection, "SELECT RELEASE_LOCK(?) AS released", params = list(lock_name)
  )
  if (nrow(result) != 1L || !identical(as.integer(result$released[[1L]]), 1L)) {
    stop("Advisory lock release was not confirmed for ", lock_name, ".",
         call. = FALSE)
  }
  invisible(TRUE)
}

release_canonical_activity_backfill_lock <- function(connection) {
  release_named_advisory_lock(connection, CANONICAL_ACTIVITY_BACKFILL_LOCK)
}

release_canonical_activity_platform_locks <- function(connection) {
  owner_lock <- paste0(
    "cycling-platform-",
    gsub("[^a-z0-9]+", "-", tolower(CANONICAL_ACTIVITY_BACKFILL_OWNER)),
    "-run"
  )
  errors <- character()
  for (lock_name in c(owner_lock, "cycling-platform-exclusive-run")) {
    tryCatch(
      release_named_advisory_lock(connection, lock_name),
      error = function(error) {
        errors <<- c(errors, conditionMessage(error))
      }
    )
  }
  if (length(errors)) {
    stop(paste(errors, collapse = "; "), call. = FALSE)
  }
  invisible(TRUE)
}

resolve_or_allocate_canonical_activity_identity <- function(
  connection,
  source_id,
  source_activity_id,
  allocation_provenance
) {
  allowed_provenance <- c("STRAVA_BACKFILL", "SOURCE_ALLOCATION")
  if (!allocation_provenance %in% allowed_provenance) {
    stop("Unsupported canonical activity allocation provenance.", call. = FALSE)
  }
  source_activity_id <- as.character(source_activity_id)
  if (length(source_activity_id) != 1L || is.na(source_activity_id) ||
      !nzchar(source_activity_id)) {
    stop("Canonical activity source identity is invalid.", call. = FALSE)
  }

  existing <- DBI::dbGetQuery(connection, paste(
    "SELECT activity_key FROM cycling_platform_silver.activity_source_map",
    "WHERE source_id = ? AND source_activity_id = ? FOR UPDATE"
  ), params = list(source_id, source_activity_id))
  if (nrow(existing)) return(existing$activity_key[[1L]])

  DBI::dbExecute(connection, paste(
    "INSERT INTO cycling_platform_silver.activity_identity",
    "(identity_status, identity_origin) VALUES ('ACTIVE', ?)"
  ), params = list(allocation_provenance))
  key <- DBI::dbGetQuery(
    connection, "SELECT LAST_INSERT_ID() AS activity_key"
  )$activity_key[[1L]]
  DBI::dbExecute(connection, paste(
    "INSERT INTO cycling_platform_silver.activity_source_map",
    "(source_id, source_activity_id, activity_key, mapping_method)",
    "VALUES (?, ?, ?, ?)"
  ), params = list(source_id, source_activity_id, key, allocation_provenance))
  key
}

allocate_canonical_activity_identity <- function(
  connection,
  source_id,
  source_activity_id,
  allocation_provenance = "STRAVA_BACKFILL"
) {
  DBI::dbWithTransaction(connection, {
    resolve_or_allocate_canonical_activity_identity(
      connection,
      source_id,
      source_activity_id,
      allocation_provenance
    )
  })
}

ensure_published_activity_identities <- function(connection) {
  published <- DBI::dbGetQuery(connection, paste(
    "SELECT activity.source_id,",
    "CAST(activity.activity_id AS CHAR) AS source_activity_id,",
    "source.source_name",
    "FROM cycling_platform_silver.activities activity",
    "INNER JOIN activity_refresh_ids refresh_ids",
    "ON refresh_ids.activity_id = activity.activity_id",
    "LEFT JOIN cycling_platform_admin.data_source source",
    "ON source.source_id = activity.source_id",
    "ORDER BY activity.activity_id"
  ))
  if (!nrow(published)) return(invisible(integer()))
  if (any(is.na(published$source_name) |
          as.character(published$source_name) != "strava")) {
    stop(
      "Continuous canonical activity allocation only supports Strava publication.",
      call. = FALSE
    )
  }

  keys <- lapply(seq_len(nrow(published)), function(index) {
    resolve_or_allocate_canonical_activity_identity(
      connection,
      published$source_id[[index]],
      published$source_activity_id[[index]],
      "SOURCE_ALLOCATION"
    )
  })
  invisible(keys)
}

perform_canonical_activity_identity_backfill <- function(connection) {
  candidates <- validate_canonical_activity_backfill_candidates(
    read_canonical_activity_backfill_candidates(connection)
  )
  pending <- candidates[is.na(candidates$activity_key), , drop = FALSE]
  if (nrow(pending)) {
    for (index in seq_len(nrow(pending))) {
      allocate_canonical_activity_identity(
        connection,
        pending$source_id[[index]],
        pending$source_activity_id[[index]],
        "STRAVA_BACKFILL"
      )
    }
  }
  result <- preview_canonical_activity_identity_backfill(connection)
  if (result$allocation_count[[1L]] != 0L) {
    stop("Canonical activity identity backfill verification is incomplete.",
         call. = FALSE)
  }
  result
}

backfill_canonical_activity_identity <- function(connection, lock_timeout = 5L) {
  platform_lock_acquired <- FALSE
  backfill_lock_acquired <- FALSE
  execution_error <- NULL
  result <- NULL

  tryCatch({
    acquire_platform_run_lock(
      connection, CANONICAL_ACTIVITY_BACKFILL_OWNER, lock_timeout
    )
    platform_lock_acquired <- TRUE
    acquire_canonical_activity_backfill_lock(connection, lock_timeout)
    backfill_lock_acquired <- TRUE
    result <- perform_canonical_activity_identity_backfill(connection)
  }, error = function(error) {
    execution_error <<- error
  })

  release_errors <- character()
  capture_release <- function(expression) {
    tryCatch(
      force(expression),
      error = function(error) {
        release_errors <<- c(release_errors, conditionMessage(error))
        invisible(FALSE)
      }
    )
  }
  if (backfill_lock_acquired) {
    capture_release(release_canonical_activity_backfill_lock(connection))
  }
  if (platform_lock_acquired) {
    capture_release(release_canonical_activity_platform_locks(connection))
  }

  if (!is.null(execution_error)) {
    if (length(release_errors)) {
      warning(
        "Canonical identity backfill also encountered lock-release failure: ",
        paste(release_errors, collapse = "; "),
        call. = FALSE
      )
    }
    stop(execution_error)
  }
  if (length(release_errors)) {
    stop(
      "Canonical identity backfill completed but lock release failed: ",
      paste(release_errors, collapse = "; "),
      call. = FALSE
    )
  }
  result
}

read_canonical_activity_identity_integrity <- function(connection) {
  DBI::dbGetQuery(connection, paste(
    "SELECT 'published_activity_without_mapping' AS diagnostic_key,",
    "CASE WHEN COUNT(*) = 0 THEN 'HEALTHY' ELSE 'VIOLATION' END AS diagnostic_status,",
    "COUNT(*) AS item_count,",
    "'Published Silver activities without canonical source mappings' AS summary",
    "FROM cycling_platform_silver.activities activity",
    "LEFT JOIN cycling_platform_silver.activity_source_map mapping",
    "ON mapping.source_id = activity.source_id",
    "AND mapping.source_activity_id = CAST(CAST(activity.activity_id AS CHAR) AS BINARY)",
    "WHERE mapping.activity_key IS NULL",
    "UNION ALL",
    "SELECT 'identity_without_source_mapping',",
    "CASE WHEN COUNT(*) = 0 THEN 'HEALTHY' ELSE 'VIOLATION' END, COUNT(*),",
    "'Canonical identities without any source mapping'",
    "FROM cycling_platform_silver.activity_identity identity_row",
    "LEFT JOIN cycling_platform_silver.activity_source_map mapping",
    "ON mapping.activity_key = identity_row.activity_key",
    "WHERE mapping.activity_key IS NULL",
    "UNION ALL",
    "SELECT 'historical_mapping_without_published_activity',",
    "CASE WHEN COUNT(*) = 0 THEN 'HEALTHY' ELSE 'EXPECTED_HISTORICAL' END, COUNT(*),",
    "'Established Strava mappings without a currently published Silver activity'",
    "FROM cycling_platform_silver.activity_source_map mapping",
    "JOIN cycling_platform_admin.data_source source ON source.source_id = mapping.source_id",
    "LEFT JOIN cycling_platform_silver.activities activity",
    "ON activity.source_id = mapping.source_id",
    "AND CAST(CAST(activity.activity_id AS CHAR) AS BINARY) = mapping.source_activity_id",
    "WHERE source.source_name = 'strava' AND activity.activity_id IS NULL",
    "UNION ALL",
    "SELECT 'multiple_strava_records_per_identity',",
    "CASE WHEN COUNT(*) = 0 THEN 'HEALTHY' ELSE 'VIOLATION' END, COUNT(*),",
    "'Canonical identities linked to multiple Strava source records'",
    "FROM (SELECT mapping.activity_key",
    "FROM cycling_platform_silver.activity_source_map mapping",
    "JOIN cycling_platform_admin.data_source source ON source.source_id = mapping.source_id",
    "WHERE source.source_name = 'strava'",
    "GROUP BY mapping.activity_key HAVING COUNT(*) > 1) duplicate_identity",
    "UNION ALL",
    "SELECT 'mapping_provenance_inconsistent',",
    "CASE WHEN COUNT(*) = 0 THEN 'HEALTHY' ELSE 'VIOLATION' END, COUNT(*),",
    "'Mappings inconsistent with the authorized Strava allocation policy'",
    "FROM cycling_platform_silver.activity_source_map mapping",
    "JOIN cycling_platform_silver.activity_identity identity_row",
    "ON identity_row.activity_key = mapping.activity_key",
    "JOIN cycling_platform_admin.data_source source ON source.source_id = mapping.source_id",
    "WHERE source.source_name <> 'strava'",
    "OR (mapping.mapping_method, identity_row.identity_origin) NOT IN (",
    "('STRAVA_BACKFILL', 'STRAVA_BACKFILL'),",
    "('SOURCE_ALLOCATION', 'SOURCE_ALLOCATION'))",
    "ORDER BY diagnostic_key"
  ))
}

with_canonical_activity_identity_connection <- function(
  operation,
  database_name = "cycling_platform_silver",
  connect = get_connection,
  is_valid = DBI::dbIsValid,
  disconnect = DBI::dbDisconnect
) {
  connection <- connect(database_name)
  primary_error <- NULL
  result <- tryCatch(
    operation(connection),
    error = function(error) {
      primary_error <<- error
      NULL
    }
  )
  cleanup_error <- tryCatch({
    if (is_valid(connection)) disconnect(connection)
    NULL
  }, error = function(error) error)

  if (!is.null(primary_error)) {
    if (!is.null(cleanup_error)) {
      warning(
        "Canonical identity connection cleanup also failed: ",
        conditionMessage(cleanup_error),
        call. = FALSE
      )
    }
    stop(primary_error)
  }
  if (!is.null(cleanup_error)) {
    stop(
      "Canonical identity operation completed but connection cleanup failed: ",
      conditionMessage(cleanup_error),
      call. = FALSE
    )
  }
  result
}
