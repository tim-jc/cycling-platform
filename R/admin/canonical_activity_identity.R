CANONICAL_ACTIVITY_BACKFILL_LOCK <-
  "cycling-platform-canonical-activity-identity-backfill"
CANONICAL_ACTIVITY_BACKFILL_OWNER <- "canonical-activity-identity-backfill"

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

allocate_canonical_activity_identity <- function(connection, source_id,
                                                  source_activity_id) {
  DBI::dbWithTransaction(connection, {
    existing <- DBI::dbGetQuery(connection, paste(
      "SELECT activity_key FROM cycling_platform_silver.activity_source_map",
      "WHERE source_id = ? AND source_activity_id = ? FOR UPDATE"
    ), params = list(source_id, source_activity_id))
    if (nrow(existing)) {
      existing$activity_key[[1L]]
    } else {
      DBI::dbExecute(connection, paste(
        "INSERT INTO cycling_platform_silver.activity_identity",
        "(identity_status, identity_origin) VALUES ('ACTIVE', 'STRAVA_BACKFILL')"
      ))
      key <- DBI::dbGetQuery(connection, "SELECT LAST_INSERT_ID() AS activity_key")$
        activity_key[[1L]]
      DBI::dbExecute(connection, paste(
        "INSERT INTO cycling_platform_silver.activity_source_map",
        "(source_id, source_activity_id, activity_key, mapping_method)",
        "VALUES (?, ?, ?, 'STRAVA_BACKFILL')"
      ), params = list(source_id, source_activity_id, key))
      key
    }
  })
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
        pending$source_activity_id[[index]]
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
    "'Mappings inconsistent with the foundation Strava backfill allocation policy'",
    "FROM cycling_platform_silver.activity_source_map mapping",
    "JOIN cycling_platform_silver.activity_identity identity_row",
    "ON identity_row.activity_key = mapping.activity_key",
    "JOIN cycling_platform_admin.data_source source ON source.source_id = mapping.source_id",
    "WHERE source.source_name <> 'strava'",
    "OR mapping.mapping_method <> 'STRAVA_BACKFILL'",
    "OR identity_row.identity_origin <> 'STRAVA_BACKFILL'",
    "ORDER BY diagnostic_key"
  ))
}
