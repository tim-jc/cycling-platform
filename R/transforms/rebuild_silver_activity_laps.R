silver_activity_laps_transform_version <- function() "strava_activity_laps_v2"

lap_scalar <- function(payload, path) {
  value <- payload
  for (part in strsplit(path, ".", fixed = TRUE)[[1]]) {
    if (is.null(value) || !is.list(value) || is.null(value[[part]])) return(NULL)
    value <- value[[part]]
  }
  if (is.null(value) || length(value) != 1L) NULL else value[[1]]
}

lap_nullable_character <- function(payload, path, blank_is_null = FALSE) {
  value <- lap_scalar(payload, path)
  if (is.null(value) || length(value) == 0L || is.na(value)) return(NA_character_)
  value <- as.character(value)
  if (blank_is_null && !nzchar(trimws(value))) NA_character_ else value
}

lap_nullable_numeric <- function(payload, path, integer = FALSE) {
  value <- lap_scalar(payload, path)
  if (is.null(value) || length(value) == 0L || is.na(value)) {
    return(if (integer) NA_integer_ else NA_real_)
  }
  number <- suppressWarnings(as.numeric(value))
  if (is.na(number)) stop("Lap field '", path, "' is not numeric.", call. = FALSE)
  if (integer) as.integer(number) else number
}

lap_nullable_logical <- function(payload, path) {
  value <- lap_scalar(payload, path)
  if (is.null(value) || length(value) == 0L || is.na(value)) return(NA)
  normalised <- tolower(as.character(value))
  if (normalised %in% c("true", "1")) return(TRUE)
  if (normalised %in% c("false", "0")) return(FALSE)
  stop("Lap field '", path, "' is not a recognised logical value.", call. = FALSE)
}

lap_nullable_datetime <- function(payload, path, local = FALSE) {
  value <- lap_nullable_character(payload, path)
  if (is.na(value)) return(as.POSIXct(NA, tz = "UTC"))
  if (local) value <- sub("Z$", "", value)
  parsed <- as.POSIXct(value, tz = "UTC", tryFormats = c(
    "%Y-%m-%dT%H:%M:%OSZ", "%Y-%m-%dT%H:%M:%OS", "%Y-%m-%d %H:%M:%OS"
  ))
  if (is.na(parsed)) stop("Lap field '", path, "' is not a valid datetime.", call. = FALSE)
  parsed
}

parse_silver_activity_lap <- function(raw_row, transformed_at = Sys.time()) {
  payload_text <- as.character(raw_row$lap_payload[[1]])
  payload <- tryCatch(
    jsonlite::fromJSON(payload_text, simplifyVector = FALSE, bigint_as_char = TRUE),
    error = function(e) stop(
      "Malformed lap payload for activity ", raw_row$activity_id[[1]],
      ", promoted lap index ", raw_row$lap_index[[1]], ": ", conditionMessage(e),
      call. = FALSE
    )
  )

  lap_id <- lap_nullable_character(payload, "id")
  payload_activity_id <- lap_nullable_character(payload, "activity.id")
  payload_lap_index <- lap_nullable_numeric(payload, "lap_index", integer = TRUE)
  promoted_activity_id <- as.character(raw_row$activity_id[[1]])
  promoted_lap_index <- as.integer(raw_row$lap_index[[1]])

  if (is.na(lap_id) || !grepl("^[0-9]+$", lap_id)) {
    stop("Missing or invalid payload lap ID for activity ", promoted_activity_id,
         ", promoted lap index ", promoted_lap_index, ".", call. = FALSE)
  }
  if (is.na(payload_activity_id) || payload_activity_id != promoted_activity_id) {
    stop("Lap activity ID mismatch: promoted activity ", promoted_activity_id,
         ", promoted lap index ", promoted_lap_index,
         ", payload lap ID ", lap_id, ", payload activity ",
         ifelse(is.na(payload_activity_id), "<missing>", payload_activity_id), ".",
         call. = FALSE)
  }
  if (is.na(payload_lap_index) || payload_lap_index < 0L) {
    stop("Missing or invalid payload lap index: activity ", promoted_activity_id,
         ", promoted response index ", promoted_lap_index,
         ", payload lap ID ", lap_id, ".", call. = FALSE)
  }

  data.frame(
    lap_id = bit64::as.integer64(lap_id),
    activity_id = bit64::as.integer64(promoted_activity_id),
    lap_index = payload_lap_index,
    raw_response_index = promoted_lap_index,
    source_id = as.integer(raw_row$source_id[[1]]),
    lap_name = lap_nullable_character(payload, "name", blank_is_null = TRUE),
    start_datetime_utc = lap_nullable_datetime(payload, "start_date"),
    start_datetime_local = lap_nullable_datetime(payload, "start_date_local", local = TRUE),
    elapsed_time_seconds = lap_nullable_numeric(payload, "elapsed_time", integer = TRUE),
    moving_time_seconds = lap_nullable_numeric(payload, "moving_time", integer = TRUE),
    distance_metres = lap_nullable_numeric(payload, "distance"),
    start_sample_index = lap_nullable_numeric(payload, "start_index", integer = TRUE),
    end_sample_index = lap_nullable_numeric(payload, "end_index", integer = TRUE),
    average_speed_metres_per_second = lap_nullable_numeric(payload, "average_speed"),
    average_cadence_rpm = lap_nullable_numeric(payload, "average_cadence"),
    average_power_watts = lap_nullable_numeric(payload, "average_watts"),
    average_heartrate_bpm = lap_nullable_numeric(payload, "average_heartrate"),
    maximum_heartrate_bpm = lap_nullable_numeric(payload, "max_heartrate"),
    elevation_gain_metres = lap_nullable_numeric(payload, "total_elevation_gain"),
    is_device_watts = lap_nullable_logical(payload, "device_watts"),
    raw_run_id = bit64::as.integer64(raw_row$run_id[[1]]),
    raw_retrieved_at = as.POSIXct(raw_row$retrieved_at[[1]], tz = "UTC"),
    raw_payload_hash = digest::digest(payload_text, algo = "sha256", serialize = FALSE),
    transform_version = silver_activity_laps_transform_version(),
    transformed_at = as.POSIXct(transformed_at, tz = "UTC"),
    stringsAsFactors = FALSE
  )
}

build_silver_activity_lap_rows <- function(raw_laps, transformed_at = Sys.time()) {
  if (!nrow(raw_laps)) return(data.frame())
  rows <- lapply(seq_len(nrow(raw_laps)), function(i) {
    parse_silver_activity_lap(raw_laps[i, , drop = FALSE], transformed_at)
  })
  result <- do.call(rbind, rows)
  if (anyDuplicated(as.character(result$lap_id))) {
    stop("Raw lap payloads contain duplicate lap_id values.", call. = FALSE)
  }
  if (anyDuplicated(paste(result$activity_id, result$lap_index))) {
    stop("Raw lap payloads contain duplicate activity_id and lap_index values.", call. = FALSE)
  }
  result
}

fetch_raw_activity_laps_for_silver <- function(connection, activity_ids = NULL) {
  query <- "SELECT activity_id, lap_index, run_id, source_id, retrieved_at, lap_payload
            FROM cycling_platform_raw.activity_laps"
  if (!is.null(activity_ids)) {
    if (!length(activity_ids)) return(data.frame())
    query <- paste0(query, " WHERE activity_id IN (",
                    format_activity_id_filter(activity_ids), ")")
  }
  DBI::dbGetQuery(connection, paste(query, "ORDER BY activity_id, lap_index"))
}

lap_refresh_activity_ids <- function(connection, rows, mode, activity_ids = NULL) {
  if (mode == "full") return(unique(rows$activity_id))
  if (!is.null(activity_ids)) {
    # Raw does not record complete lap snapshots. An affected activity with no
    # retained Raw lap row is therefore not authoritative evidence of removal.
    return(bit64::as.integer64(unique(as.character(rows$activity_id))))
  }
  existing <- DBI::dbGetQuery(connection, "
    SELECT lap_id, activity_id, lap_index, raw_payload_hash, transform_version
    FROM cycling_platform_silver.activity_laps")
  if (!nrow(rows) && !nrow(existing)) return(bit64::integer64())
  raw_signature <- paste(rows$lap_id, rows$activity_id, rows$lap_index,
                         rows$raw_payload_hash, rows$transform_version)
  silver_signature <- paste(existing$lap_id, existing$activity_id, existing$lap_index,
                            existing$raw_payload_hash, existing$transform_version)
  changed <- c(rows$activity_id[!raw_signature %in% silver_signature],
               existing$activity_id[!silver_signature %in% raw_signature])
  bit64::as.integer64(unique(as.character(changed)))
}

replace_silver_activity_laps <- function(connection, rows, activity_ids, full = FALSE) {
  deleted <- if (full) {
    DBI::dbExecute(connection, "DELETE FROM cycling_platform_silver.activity_laps")
  } else if (length(activity_ids)) {
    DBI::dbExecute(connection, paste0(
      "DELETE FROM cycling_platform_silver.activity_laps WHERE activity_id IN (",
      format_activity_id_filter(activity_ids), ")"
    ))
  } else 0L
  if (nrow(rows)) {
    append_existing_table(
      connection,
      DBI::Id(schema = "cycling_platform_silver", table = "activity_laps"),
      rows, append = TRUE, overwrite = FALSE
    )
  }
  list(rows_inserted = nrow(rows), rows_deleted = deleted)
}

rebuild_silver_activity_laps <- function(
  connection,
  sql_dir = file.path("sql", "silver"),
  mode = c("full", "repair", "incremental"),
  activity_ids = NULL
) {
  mode <- match.arg(mode)
  started_at <- Sys.time()
  ensure_transform_logging_tables(connection)
  execute_sql_file(file.path(sql_dir, "060_create_activity_laps.sql"), connection)

  raw_scope <- if (mode == "incremental") activity_ids else NULL
  raw <- fetch_raw_activity_laps_for_silver(connection, raw_scope)
  planned_activities <- length(unique(raw$activity_id))
  run_id <- create_transform_run(
    connection, "silver", "activity_laps", mode,
    total_batches = if (nrow(raw)) 1L else 0L,
    activities_planned = planned_activities,
    expected_rows_planned = nrow(raw),
    max_batch_activities = planned_activities,
    max_batch_expected_rows = nrow(raw)
  )

  outcome <- tryCatch({
    parsed <- build_silver_activity_lap_rows(raw, transformed_at = started_at)
    refresh_ids <- lap_refresh_activity_ids(connection, parsed, mode, activity_ids)
    publish_rows <- if (!length(refresh_ids)) parsed[0, , drop = FALSE] else {
      parsed[as.character(parsed$activity_id) %in% as.character(refresh_ids), , drop = FALSE]
    }
    existing <- DBI::dbGetQuery(connection,
      "SELECT lap_id, raw_payload_hash, transform_version FROM cycling_platform_silver.activity_laps")
    existing_ids <- as.character(existing$lap_id)
    inserted <- sum(!as.character(publish_rows$lap_id) %in% existing_ids)
    updated <- sum(as.character(publish_rows$lap_id) %in% existing_ids)
    unchanged <- nrow(parsed) - nrow(publish_rows)
    write_result <- DBI::dbWithTransaction(connection, replace_silver_activity_laps(
      connection, publish_rows, refresh_ids, full = mode == "full"
    ))
    list(
      refresh_ids = refresh_ids, inserted = inserted, updated = updated,
      unchanged = unchanged, deleted = write_result$rows_deleted
    )
  }, error = function(e) e)

  if (inherits(outcome, "error")) {
    update_transform_run(connection, run_id, "FAILED", error_message = conditionMessage(outcome))
    stop(outcome)
  }
  update_transform_run(
    connection, run_id, "SUCCESS",
    completed_batches = if (length(outcome$refresh_ids)) 1L else 0L,
    activities_completed = length(outcome$refresh_ids),
    rows_inserted = outcome$inserted,
    rows_updated = outcome$updated,
    rows_deleted = outcome$deleted
  )
  message(glue::glue(
    "Silver activity laps {mode} complete: {length(outcome$refresh_ids)} activities; ",
    "{outcome$inserted} inserted, {outcome$updated} updated, ",
    "{outcome$unchanged} unchanged, {outcome$deleted} replaced/deleted; ",
    "version {silver_activity_laps_transform_version()}; ",
    "{round(as.numeric(difftime(Sys.time(), started_at, units = 'secs')), 1)}s."
  ))
  invisible(list(
    activities = length(outcome$refresh_ids), rows_inserted = outcome$inserted,
    rows_updated = outcome$updated, rows_unchanged = outcome$unchanged,
    rows_deleted = outcome$deleted
  ))
}
