gold_transform_metric_catalogue <- function() {
  data.frame(
    entity_name = c(
      rep("activity_best_efforts", 3L),
      rep("activity_achievements", 7L)
    ),
    metric_name = c(
      "upstream_affected_count", "output_changed_activity_count",
      "repair_candidate_count", "direct_affected_count",
      "evaluation_debt_count", "closure_activity_count",
      "zero_achievement_evaluations", "evaluation_state_rows_invalidated",
      "evaluation_state_rows_current", "remaining_invalidated_count"
    ),
    metric_unit = "COUNT",
    stringsAsFactors = FALSE
  )
}

gold_transform_dimension_catalogue <- function() {
  list(
    discovery_mode = c("skipped", "affected_set", "repair_scan"),
    candidate_mode = c(
      "conservative", "evaluation_state", "latest_append",
      "historical_closure", "repair", "repair_closure", "rebuild",
      "conservative_fallback"
    ),
    invalidation_action = c("none", "latest_append", "historical_closure"),
    invalidation_reason = c(
      "HISTORICAL_ACTIVITY_CHANGE", "HISTORICAL_INSERT",
      "BEST_EFFORT_CHANGE", "POWER_ELIGIBILITY_CHANGE", "DATE_CHANGE",
      "REPAIR", "explicit_backfill"
    )
  )
}

normalise_gold_transform_dimension <- function(name, value) {
  value <- telemetry_value_or_na(value, "character")
  if (is.na(value)) return(value)
  allowed <- gold_transform_dimension_catalogue()[[name]]
  if (is.null(allowed) || !value %in% allowed) {
    stop("Unsupported Gold transform dimension ", name, ": ", value, call. = FALSE)
  }
  value
}

telemetry_value_or_na <- function(value, type = c("numeric", "character")) {
  type <- match.arg(type)
  if (is.null(value) || length(value) == 0L || is.na(value[[1]])) {
    return(if (type == "numeric") NA_real_ else NA_character_)
  }
  if (type == "numeric") as.numeric(value[[1]]) else as.character(value[[1]])
}

normalise_gold_transform_metrics <- function(entity_name, metrics) {
  if (length(metrics) == 0L) return(data.frame())
  catalogue <- gold_transform_metric_catalogue()
  allowed <- catalogue[catalogue$entity_name == entity_name, , drop = FALSE]
  unknown <- setdiff(names(metrics), allowed$metric_name)
  if (length(unknown) > 0L) {
    stop("Unsupported Gold transform metric(s): ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  values <- suppressWarnings(as.numeric(unlist(metrics, use.names = FALSE)))
  keep <- !is.na(values)
  data.frame(
    metric_name = names(metrics)[keep],
    metric_value = values[keep],
    metric_unit = allowed$metric_unit[match(names(metrics)[keep], allowed$metric_name)],
    stringsAsFactors = FALSE
  )
}

persist_gold_transform_observability <- function(
  connection, transform_run_id, entity_name, timing, metrics = list()
) {
  if (is.null(transform_run_id)) return(invisible(NULL))
  DBI::dbExecute(
    connection,
    "UPDATE cycling_platform_admin.transform_run
        SET setup_seconds = ?, discovery_seconds = ?,
            source_preparation_seconds = ?, processing_seconds = ?,
            finalisation_seconds = ?, discovery_mode = ?, candidate_mode = ?,
            invalidation_action = ?, invalidation_reason = ?,
            dependency_start_date = ?
      WHERE transform_run_id = ?",
    params = list(
      telemetry_value_or_na(timing$setup_seconds),
      telemetry_value_or_na(timing$candidate_discovery_seconds),
      telemetry_value_or_na(timing$source_preparation_seconds),
      telemetry_value_or_na(timing$processing_seconds),
      telemetry_value_or_na(timing$finalisation_seconds),
      normalise_gold_transform_dimension("discovery_mode", timing$discovery_mode),
      normalise_gold_transform_dimension("candidate_mode", timing$candidate_mode),
      normalise_gold_transform_dimension("invalidation_action", timing$invalidation_action),
      normalise_gold_transform_dimension("invalidation_reason", timing$invalidation_reason),
      if (is.null(timing$dependency_start_date) || is.na(timing$dependency_start_date)) as.Date(NA) else as.Date(timing$dependency_start_date),
      transform_run_id
    )
  )
  rows <- normalise_gold_transform_metrics(entity_name, metrics)
  if (nrow(rows) > 0L) {
    for (index in seq_len(nrow(rows))) {
      DBI::dbExecute(
        connection,
        "INSERT INTO cycling_platform_admin.transform_run_metric
           (transform_run_id, metric_name, metric_value, metric_unit)
         VALUES (?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE metric_value = VALUES(metric_value),
                                 metric_unit = VALUES(metric_unit)",
        params = list(transform_run_id, rows$metric_name[[index]], rows$metric_value[[index]], rows$metric_unit[[index]])
      )
    }
  }
  invisible(NULL)
}

update_achievement_notification_phase_workload <- function(
  connection, pipeline_run_id, queued, attempted, sent, failed, deferred
) {
  workload <- normalise_achievement_notification_workload(
    queued, attempted, sent, failed, deferred
  )
  DBI::dbExecute(
    connection,
    "UPDATE cycling_platform_admin.pipeline_phase_run
        SET notifications_queued = ?, notifications_attempted = ?,
            notifications_sent = ?, notifications_failed = ?,
            notifications_deferred = ?
      WHERE pipeline_run_id = ? AND phase_name = 'achievement_notifications'",
    params = c(unname(workload), list(pipeline_run_id))
  )
  invisible(NULL)
}

normalise_achievement_notification_workload <- function(
  queued, attempted, sent, failed, deferred
) {
  values <- c(
    queued = queued, attempted = attempted, sent = sent,
    failed = failed, deferred = deferred
  )
  if (length(values) != 5L || any(is.na(values)) || any(values < 0) ||
      any(values != as.integer(values))) {
    stop("Achievement notification workload must contain non-negative integer counts.", call. = FALSE)
  }
  as.list(as.integer(values)) |> stats::setNames(names(values))
}

record_api_request_attempt <- function(
  connection, endpoint_run_id, request_sequence, request_name,
  source_reference, attempt_number, attempt_status, retry_decision,
  http_status = NULL, failure_class = NULL, error_summary = NULL,
  started_at, completed_at
) {
  DBI::dbExecute(
    connection,
    "INSERT INTO cycling_platform_admin.api_request_attempt (
       endpoint_run_id, request_sequence, request_name, source_reference,
       attempt_number, attempt_status, retry_decision, http_status,
       failure_class, error_summary, started_at, completed_at, duration_seconds
     ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    params = list(
      endpoint_run_id, request_sequence, request_name,
      if (is.null(source_reference)) NA_character_ else source_reference,
      attempt_number, attempt_status, retry_decision,
      if (is.null(http_status) || is.na(http_status)) NA_integer_ else as.integer(http_status),
      if (is.null(failure_class)) NA_character_ else sanitize_operational_text(failure_class, 100L),
      sanitize_operational_text(error_summary, 1000L),
      as.POSIXct(started_at, tz = "UTC"), as.POSIXct(completed_at, tz = "UTC"),
      max(0, as.numeric(difftime(completed_at, started_at, units = "secs")))
    )
  )
  invisible(NULL)
}
