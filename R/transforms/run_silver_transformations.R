#' Run Silver Transformations
#'
#' Execute silver-layer SQL files in sequence.
#'
#' @param connection Database connection.
#' @param sql_dir Directory containing silver SQL scripts.
#' @param config Platform configuration.
#' @param stream_rebuild_mode Use `full` to truncate/rebuild streams, or
#'   `repair` to rebuild only missing or incomplete stream activities.
#'
silver_activity_gold_snapshot <- function(connection, activity_ids) {
  activity_ids <- unique(as.character(activity_ids))
  if (length(activity_ids) == 0L) return(data.frame())

  DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT activity_id, start_date_local, distance_metres, moving_time_seconds, ",
      "elevation_gain_metres, power_source_type, is_power_record_eligible, ",
      "power_record_exclusion_reason, power_classification_version ",
      "FROM cycling_platform_silver.activities WHERE activity_id IN (",
      format_activity_id_filter(activity_ids), ") ORDER BY activity_id"
    )
  )
}

silver_snapshot_hashes <- function(snapshot, activity_ids) {
  activity_ids <- unique(as.character(activity_ids))
  missing_hash <- digest::digest(NULL, algo = "sha256")
  result <- stats::setNames(rep(missing_hash, length(activity_ids)), activity_ids)
  if (nrow(snapshot) == 0L) return(result)

  groups <- split(snapshot, as.character(snapshot$activity_id))
  result[names(groups)] <- vapply(groups, digest::digest, character(1), algo = "sha256")
  result
}

power_classification_control_snapshot <- function(connection) {
  DBI::dbGetQuery(
    connection,
    "SELECT effective_cutover_at, rule_version, manual_cutover_at, is_active
       FROM cycling_platform_admin.power_source_classification
      WHERE classification_name = 'strava_power_meter_cutover'
      LIMIT 1"
  )
}

snapshots_identical <- function(before, after) {
  identical(
    digest::digest(before, algo = "sha256"),
    digest::digest(after, algo = "sha256")
  )
}

latest_silver_transform_run_ids <- function(connection) {
  runs <- DBI::dbGetQuery(
    connection,
    "SELECT entity_name, MAX(transform_run_id) AS transform_run_id
       FROM cycling_platform_admin.transform_run
      WHERE layer_name = 'silver'
        AND entity_name IN ('activities', 'gear', 'activity_streams', 'activity_laps')
      GROUP BY entity_name"
  )
  if (nrow(runs) == 0L) return(integer())
  stats::setNames(runs$transform_run_id, runs$entity_name)
}

build_gold_change_rows <- function(
  activity_ids,
  activities_before,
  activities_after,
  stream_changed_ids
) {
  activity_ids <- unique(as.character(activity_ids))
  before_hashes <- silver_snapshot_hashes(activities_before, activity_ids)
  after_hashes <- silver_snapshot_hashes(activities_after, activity_ids)
  activities_changed <- before_hashes != after_hashes
  stream_changed <- activity_ids %in% as.character(stream_changed_ids)

  before_ids <- as.character(activities_before$activity_id)
  after_ids <- as.character(activities_after$activity_id)
  change_type <- ifelse(
    !activity_ids %in% before_ids & activity_ids %in% after_ids,
    "insert",
    ifelse(activity_ids %in% before_ids & !activity_ids %in% after_ids, "delete_or_exclude", "update")
  )

  date_for <- function(snapshot, id) {
    value <- snapshot$start_date_local[as.character(snapshot$activity_id) == id]
    if (length(value) == 0L || is.na(value[[1]])) as.Date(NA) else as.Date(value[[1]])
  }
  before_dates <- as.Date(vapply(activity_ids, function(id) as.character(date_for(activities_before, id)), character(1)))
  after_dates <- as.Date(vapply(activity_ids, function(id) as.character(date_for(activities_after, id)), character(1)))
  dependency_dates <- as.Date(vapply(seq_along(activity_ids), function(index) {
    values <- c(before_dates[[index]], after_dates[[index]])
    values <- values[!is.na(values)]
    if (length(values) == 0L) NA_character_ else as.character(min(values))
  }, character(1)))

  power_columns <- c(
    "activity_id", "power_source_type", "is_power_record_eligible",
    "power_record_exclusion_reason", "power_classification_version"
  )
  power_before <- activities_before[, intersect(power_columns, names(activities_before)), drop = FALSE]
  power_after <- activities_after[, intersect(power_columns, names(activities_after)), drop = FALSE]
  power_changed <- silver_snapshot_hashes(power_before, activity_ids) !=
    silver_snapshot_hashes(power_after, activity_ids)

  rows <- data.frame(
    activity_id = bit64::as.integer64(activity_ids),
    change_type = change_type,
    activity_date_before = before_dates,
    activity_date_after = after_dates,
    silver_activities_changed = unname(activities_changed),
    silver_streams_changed = stream_changed,
    power_classification_changed = unname(power_changed),
    dependency_start_date = dependency_dates
  )

  material <- rows$silver_activities_changed | rows$silver_streams_changed |
    rows$power_classification_changed | rows$change_type != "update"
  rows[material, , drop = FALSE]
}

#' @return Invisibly returns a `gold_change_context`.
run_silver_transformations <- function(
  connection,
  sql_dir = file.path("sql", "silver"),
  config = list(),
  stream_rebuild_mode = "full",
  activity_ids = NULL,
  raw_run_id = NA_integer_,
  status_callback = NULL
) {
  emit_status <- function(event = list(), force = FALSE) {
    if (!is.null(status_callback)) status_callback(event, force = force)
    invisible(NULL)
  }
  silver_stream_batch_size <- config$transforms$silver_stream_activity_batch_size
  silver_stream_batch_max_expected_rows <-
    config$transforms$silver_stream_batch_max_expected_rows
  silver_stream_insert_chunk_size <-
    config$transforms$silver_stream_insert_chunk_size
  silver_stream_progress_every_batches <-
    config$transforms$silver_stream_progress_every_batches
  silver_stream_progress_every_seconds <-
    config$transforms$silver_stream_progress_every_seconds
  log_level <- config$logging$level

  if (is.null(silver_stream_batch_size)) {
    silver_stream_batch_size <- 10L
  }

  if (is.null(silver_stream_batch_max_expected_rows)) {
    silver_stream_batch_max_expected_rows <- 5000L
  }

  if (is.null(silver_stream_insert_chunk_size)) {
    silver_stream_insert_chunk_size <- 500L
  }
  if (is.null(silver_stream_progress_every_batches)) {
    silver_stream_progress_every_batches <- 10L
  }
  if (is.null(silver_stream_progress_every_seconds)) {
    silver_stream_progress_every_seconds <- 60
  }
  if (is.null(log_level)) log_level <- "INFO"

  emit_status(list(current_phase = "table_creation", current_entity = "silver"), force = TRUE)
  run_sql_directory(
    connection = connection,
    sql_dir = sql_dir,
    layer_name = "silver table creation",
    pattern = "^[0-9]+_create_.*\\.sql$"
  )

  explicit_activity_ids <- if (is.null(activity_ids)) NULL else unique(activity_ids)
  ensure_power_source_classification_schema(connection)
  classification_before <- power_classification_control_snapshot(connection)
  activities_before <- if (is.null(explicit_activity_ids)) data.frame() else {
    silver_activity_gold_snapshot(connection, explicit_activity_ids)
  }

  emit_status(list(current_phase = "classification", current_entity = "power_source"), force = TRUE)
  refresh_power_source_classification(
    connection = connection,
    config = config
  )
  classification_after <- power_classification_control_snapshot(connection)
  classification_globally_changed <- !snapshots_identical(
    classification_before,
    classification_after
  )

  emit_status(list(current_phase = "silver_transforms", current_entity = "activities"), force = TRUE)
  rebuild_silver_activities(
    connection = connection,
    sql_dir = sql_dir,
    mode = if (is.null(activity_ids)) "full" else "incremental",
    activity_ids = activity_ids
  )

  emit_status(list(current_phase = "silver_transforms", current_entity = "gear"), force = TRUE)
  rebuild_silver_gear(
    connection = connection,
    sql_dir = sql_dir,
    mode = "full"
  )

  emit_status(list(current_phase = "silver_transforms", current_entity = "activity_streams"), force = TRUE)
  stream_result <- rebuild_silver_activity_streams(
    connection = connection,
    batch_size = silver_stream_batch_size,
    max_expected_rows = silver_stream_batch_max_expected_rows,
    insert_chunk_size = silver_stream_insert_chunk_size,
    progress_every_batches = silver_stream_progress_every_batches,
    progress_every_seconds = silver_stream_progress_every_seconds,
    log_level = log_level,
    status_callback = status_callback,
    activity_ids = explicit_activity_ids,
    mode = stream_rebuild_mode
  )

  emit_status(list(current_phase = "silver_transforms", current_entity = "activity_laps"), force = TRUE)
  rebuild_silver_activity_laps(
    connection = connection,
    sql_dir = sql_dir,
    mode = if (!is.null(activity_ids)) "incremental" else stream_rebuild_mode,
    activity_ids = activity_ids
  )

  if (is.null(explicit_activity_ids)) {
    return(invisible(unavailable_gold_change_context(
      "Silver was run without an authoritative affected-activity worklist."
    )))
  }

  activities_after <- silver_activity_gold_snapshot(connection, explicit_activity_ids)
  change_rows <- build_gold_change_rows(
    activity_ids = explicit_activity_ids,
    activities_before = activities_before,
    activities_after = activities_after,
    stream_changed_ids = stream_result$materially_changed_activity_ids
  )

  deletion_detected <- any(change_rows$change_type == "delete_or_exclude")
  context_status <- if (classification_globally_changed || deletion_detected) "UNTRUSTED" else "COMPLETE"
  context_reason <- if (classification_globally_changed) {
    "Global power-classification control changed; run explicit Gold repair/rebuild."
  } else if (deletion_detected) {
    "Silver activity deletion/exclusion is not authoritative for incremental Gold; run explicit repair/rebuild."
  } else {
    NA_character_
  }

  context <- new_gold_change_context(
    status = context_status,
    activities = change_rows,
    raw_run_id = raw_run_id,
    silver_transform_run_ids = latest_silver_transform_run_ids(connection),
    reason = context_reason
  )
  message(
    "Silver to Gold change context: status=", context$status,
    "; affected=", nrow(context$activities),
    if (!is.na(context$reason)) paste0("; reason=", context$reason) else ""
  )

  invisible(context)
}
