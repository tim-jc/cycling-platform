canonical_activity_payload <- function(payload) {
  sort_json <- function(value) {
    if (is.list(value)) {
      if (!is.null(names(value))) value <- value[order(names(value))]
      return(lapply(value, sort_json))
    }
    value
  }
  parsed <- jsonlite::fromJSON(payload, simplifyVector = FALSE)
  jsonlite::toJSON(sort_json(parsed), auto_unbox = TRUE, null = "null", digits = NA)
}

activity_ingestion_mode <- function(config, mode) {
  mode <- match.arg(mode, c("scheduled", "manual", "hygiene", "activity_backfill", "backfill", "streams_only"))
  if (mode == "hygiene") return(list(run_mode = "HYGIENE", refresh_days = as.integer(config$ingestion$activity_hygiene_days), suppress_achievement_notifications = FALSE))
  if (mode == "activity_backfill") return(list(run_mode = "ACTIVITY_BACKFILL", refresh_days = as.integer(config$ingestion$activity_backfill_days), suppress_achievement_notifications = TRUE))
  if (mode == "backfill") return(list(run_mode = "BACKFILL", refresh_days = as.integer(config$ingestion$activity_backfill_days), suppress_achievement_notifications = FALSE))
  if (mode == "streams_only") return(list(run_mode = "STREAMS_ONLY", refresh_days = 0L, suppress_achievement_notifications = FALSE))
  list(run_mode = if (mode == "scheduled") "SCHEDULED" else "MANUAL", refresh_days = as.integer(config$ingestion$activity_refresh_days), suppress_achievement_notifications = FALSE)
}

activity_payload_changed <- function(current_payload, incoming_payload) {
  !identical(
    canonical_activity_payload(current_payload),
    canonical_activity_payload(incoming_payload)
  )
}

get_activity_reconciliation_baseline <- function(connection, refresh_days, now = Sys.time()) {
  DBI::dbGetQuery(
    connection,
    "SELECT activity_id, raw_payload, start_datetime_utc,
            details_status, stream_status, laps_status
       FROM cycling_platform_raw.activities
      WHERE start_datetime_utc >= ?",
    params = list(as.POSIXct(now, tz = "UTC") - as.difftime(refresh_days, units = "days"))
  )
}

classify_activity_summaries <- function(activities, existing) {
  incoming_ids <- as.character(activities$activity_id)
  existing_ids <- as.character(existing$activity_id)
  incoming_map <- match(existing_ids, incoming_ids)
  existing_map <- match(incoming_ids, existing_ids)

  incoming_rows <- lapply(seq_len(nrow(activities)), function(index) {
    old_index <- existing_map[[index]]
    status <- if (is.na(old_index)) "NEW" else if (activity_payload_changed(existing$raw_payload[[old_index]], activities$raw_payload[[index]])) "CHANGED" else "UNCHANGED"
    old_statuses <- if (is.na(old_index)) c("PENDING", "PENDING", "PENDING") else unlist(existing[old_index, c("details_status", "stream_status", "laps_status")], use.names = FALSE)
    effective_statuses <- if (status %in% c("NEW", "CHANGED")) c("PENDING", "PENDING", "PENDING") else old_statuses
    child_status <- if (any(effective_statuses == "FAILED")) "FAILED" else if (all(effective_statuses %in% c("SUCCESS", "NOT_FOUND"))) "COMPLETE" else "INCOMPLETE"
    data.frame(activity_id = as.character(activities$activity_id[[index]]), reconciliation_status = status, child_status = child_status, source_present = 1L, payload_changed = as.integer(status == "CHANGED"), details_repair_required = as.integer(!effective_statuses[[1]] %in% c("SUCCESS", "NOT_FOUND")), streams_repair_required = as.integer(!effective_statuses[[2]] %in% c("SUCCESS", "NOT_FOUND")), laps_repair_required = as.integer(!effective_statuses[[3]] %in% c("SUCCESS", "NOT_FOUND")))
  })
  missing_rows <- lapply(which(is.na(incoming_map)), function(index) {
    statuses <- unlist(existing[index, c("details_status", "stream_status", "laps_status")], use.names = FALSE)
    child_status <- if (any(statuses == "FAILED")) "FAILED" else if (all(statuses %in% c("SUCCESS", "NOT_FOUND"))) "COMPLETE" else "INCOMPLETE"
    data.frame(activity_id = as.character(existing$activity_id[[index]]), reconciliation_status = "MISSING", child_status = child_status, source_present = 0L, payload_changed = 0L, details_repair_required = 0L, streams_repair_required = 0L, laps_repair_required = 0L)
  })
  rows <- c(incoming_rows, missing_rows)
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

record_activity_reconciliation <- function(connection, run_id, reconciliation) {
  if (!nrow(reconciliation)) return(invisible(0L))
  reconciliation$run_id <- run_id
  reconciliation$reconciled_at <- as.POSIXct(Sys.time(), tz = "UTC")
  columns <- c("run_id", "activity_id", "reconciliation_status", "child_status", "source_present", "payload_changed", "details_repair_required", "streams_repair_required", "laps_repair_required", "reconciled_at")
  append_existing_table(connection, DBI::Id(schema = "cycling_platform_admin", table = "activity_reconciliation"), reconciliation[columns], append = TRUE, overwrite = FALSE)
  invisible(nrow(reconciliation))
}

mark_changed_activity_children_pending <- function(connection, activity_ids) {
  if (!length(activity_ids)) return(invisible(0L))
  placeholders <- paste(rep("?", length(activity_ids)), collapse = ", ")
  DBI::dbExecute(connection, paste0("UPDATE cycling_platform_raw.activities SET details_status='PENDING', stream_status='PENDING', laps_status='PENDING' WHERE activity_id IN (", placeholders, ")"), params = as.list(as.character(activity_ids)))
}
