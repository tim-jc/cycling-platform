TRACK_CALIBRATION_VERSION <- "gps-track-calibration-v1"
TRACK_CALIBRATION_CUTOFF_UTC <- "2026-10-29 23:59:59"
TRACK_CALIBRATION_TARGET_SIZE <- 45L

track_calibration_references <- function() {
  data.frame(
    activity_id = c("20445541114", "3057187825", "2705450947"),
    reference_subtype = c(
      "LEGITIMATE_CAFE_STOP", "CORRUPTED_GPS", "MISSING_ROUTE_GEOMETRY"
    ),
    stringsAsFactors = FALSE
  )
}

track_calibration_reference_segments <- function() {
  data.frame(
    activity_id = c(
      "20445541114", "3057187825", "3057187825", "3057187825",
      "3057187825", "2705450947"
    ),
    from_sample_index = c(7251L, 2537L, 2527L, 2519L, 2526L, 7639L),
    to_sample_index = c(7252L, 2538L, 2528L, 2520L, 2527L, 7640L),
    reference_segment = c(
      "LEGITIMATE_CAFE_STOP", "CORRUPTED_GPS", "CORRUPTED_GPS",
      "CORRUPTED_GPS", "CORRUPTED_GPS", "MISSING_ROUTE_GEOMETRY"
    ),
    stringsAsFactors = FALSE
  )
}

track_calibration_candidate_sql <- function() {
  paste0(
    "SELECT CAST(a.activity_id AS CHAR) AS activity_id, a.activity_name, ",
    "a.sport_type, a.is_manual, a.start_datetime_utc, a.start_datetime_local, ",
    "a.start_date_local, a.distance_metres, a.moving_time_seconds, ",
    "a.elapsed_time_seconds, latlng.original_size AS gps_sample_count, ",
    "time_stream.original_size AS time_sample_count, ",
    "distance_stream.original_size AS distance_sample_count, ",
    "latlng.retrieved_at AS gps_retrieved_at, ",
    "LOWER(COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.trainer')), ",
    "JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$[0].trainer')), 'false')) ",
    "AS source_trainer, ",
    "LOWER(CONCAT_WS(' ', COALESCE(a.activity_name, ''), ",
    "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.external_id')), ''), ",
    "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$[0].external_id')), ''), ",
    "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$.device_name')), ''), ",
    "COALESCE(JSON_UNQUOTE(JSON_EXTRACT(raw.raw_payload, '$[0].device_name')), ''))) ",
    "AS provenance_text, ",
    "SHA2(CONCAT(CAST(a.activity_id AS CHAR), '|", TRACK_CALIBRATION_VERSION,
    "'), 256) AS deterministic_rank ",
    "FROM cycling_platform_silver.activities a ",
    "INNER JOIN cycling_platform_raw.activities raw ON raw.activity_id = a.activity_id ",
    "INNER JOIN cycling_platform_raw.activity_streams latlng ",
    "ON latlng.activity_id = a.activity_id AND latlng.stream_type = 'latlng' ",
    "LEFT JOIN cycling_platform_raw.activity_streams time_stream ",
    "ON time_stream.activity_id = a.activity_id AND time_stream.stream_type = 'time' ",
    "LEFT JOIN cycling_platform_raw.activity_streams distance_stream ",
    "ON distance_stream.activity_id = a.activity_id AND distance_stream.stream_type = 'distance' ",
    "WHERE a.start_datetime_utc <= ? AND latlng.original_size IS NOT NULL ",
    "AND latlng.original_size > 0 ORDER BY a.start_datetime_utc, a.activity_id"
  )
}

fetch_track_calibration_candidates <- function(
  connection,
  cutoff_utc = TRACK_CALIBRATION_CUTOFF_UTC,
  get_query = DBI::dbGetQuery
) {
  get_query(connection, track_calibration_candidate_sql(), params = list(cutoff_utc))
}

classify_track_calibration_eligibility <- function(candidates) {
  required <- c(
    "activity_id", "sport_type", "is_manual", "start_datetime_utc",
    "distance_metres", "moving_time_seconds", "elapsed_time_seconds",
    "gps_sample_count", "source_trainer", "provenance_text", "deterministic_rank"
  )
  missing <- setdiff(required, names(candidates))
  if (length(missing)) {
    stop("Candidate metadata missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  }

  result <- candidates
  sport <- tolower(trimws(ifelse(is.na(result$sport_type), "", result$sport_type)))
  text <- tolower(ifelse(is.na(result$provenance_text), "", result$provenance_text))
  trainer <- tolower(trimws(ifelse(is.na(result$source_trainer), "", result$source_trainer)))
  manual <- suppressWarnings(as.integer(result$is_manual))
  reason <- rep("ELIGIBLE", nrow(result))
  reason[is.na(manual) | !nzchar(sport)] <- "UNKNOWN_PROVENANCE"
  reason[!is.na(manual) & manual == 1L] <- "INELIGIBLE_MANUAL"
  reason[grepl("^virtual|simulat", sport)] <- "INELIGIBLE_VIRTUAL_SPORT"
  reason[trainer %in% c("true", "1")] <- "INELIGIBLE_SOURCE_TRAINER"
  reason[grepl("trainerroad|zwift", text)] <- "INELIGIBLE_SYNTHETIC_CONTEXT"
  reason[is.na(result$gps_sample_count) | result$gps_sample_count < 1] <- "INELIGIBLE_NO_GPS"
  reason[is.na(result$start_datetime_utc)] <- "UNKNOWN_PROVENANCE"
  result$eligibility_status <- reason
  result
}

rank_quantile_band <- function(values, bands, tie_breaker, missing_last = TRUE) {
  n <- length(values)
  if (!n) return(integer())
  missing <- is.na(values) | !is.finite(as.numeric(values))
  order_values <- values
  if (missing_last) order_values[missing] <- Inf
  ordered <- order(order_values, tie_breaker, na.last = TRUE)
  ranks <- integer(n)
  ranks[ordered] <- seq_len(n)
  pmin(bands, floor((ranks - 1L) * bands / n) + 1L)
}

prepare_track_calibration_candidates <- function(candidates) {
  candidates <- classify_track_calibration_eligibility(candidates)
  candidates$activity_id <- as.character(candidates$activity_id)
  candidates$activity_year <- as.integer(format(
    as.POSIXct(candidates$start_datetime_utc, tz = "UTC"), "%Y", tz = "UTC"
  ))
  candidates$distance_kilometres <- as.numeric(candidates$distance_metres) / 1000
  candidates$non_moving_time_seconds <- pmax(
    0, as.numeric(candidates$elapsed_time_seconds) - as.numeric(candidates$moving_time_seconds)
  )
  candidates$samples_per_elapsed_hour <- ifelse(
    candidates$elapsed_time_seconds > 0,
    as.numeric(candidates$gps_sample_count) * 3600 / candidates$elapsed_time_seconds,
    NA_real_
  )
  candidates$samples_per_moving_hour <- ifelse(
    candidates$moving_time_seconds > 0,
    as.numeric(candidates$gps_sample_count) * 3600 / candidates$moving_time_seconds,
    NA_real_
  )
  candidates$samples_per_kilometre <- ifelse(
    candidates$distance_metres > 0,
    as.numeric(candidates$gps_sample_count) * 1000 / candidates$distance_metres,
    NA_real_
  )
  candidates
}

choose_density_diverse <- function(cell, count = 2L) {
  if (!nrow(cell)) return(character())
  low <- cell[order(cell$sampling_density_band, cell$deterministic_rank), , drop = FALSE]
  high <- cell[order(-cell$sampling_density_band, cell$deterministic_rank), , drop = FALSE]
  ordered <- unique(c(low$activity_id[[1]], high$activity_id[[1]], cell$activity_id[order(cell$deterministic_rank)]))
  head(ordered, count)
}

select_track_calibration_manifest <- function(
  candidates,
  selected_at_utc = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
  target_size = TRACK_CALIBRATION_TARGET_SIZE
) {
  candidates <- prepare_track_calibration_candidates(candidates)
  eligible <- candidates[candidates$eligibility_status == "ELIGIBLE", , drop = FALSE]
  eligible <- eligible[!duplicated(eligible$activity_id), , drop = FALSE]
  references <- track_calibration_references()
  reference_rows <- merge(references, candidates, by = "activity_id", all.x = TRUE, sort = FALSE)
  bad_refs <- reference_rows$activity_id[
    is.na(reference_rows$eligibility_status) | reference_rows$eligibility_status != "ELIGIBLE"
  ]
  if (length(bad_refs)) {
    stop("Reference activities are missing or ineligible: ", paste(bad_refs, collapse = ", "), call. = FALSE)
  }

  if (!nrow(eligible)) stop("No eligible GPS activities were found.", call. = FALSE)
  eligible$chronology_band <- rank_quantile_band(
    as.numeric(as.POSIXct(eligible$start_datetime_utc, tz = "UTC")),
    5L, eligible$deterministic_rank
  )
  eligible$distance_band <- rank_quantile_band(
    as.numeric(eligible$distance_metres), 3L, eligible$deterministic_rank
  )
  eligible$sampling_density_band <- rank_quantile_band(
    as.numeric(eligible$samples_per_elapsed_hour), 3L, eligible$deterministic_rank
  )

  selection <- data.frame(
    activity_id = references$activity_id,
    cohort = "REFERENCE",
    reference_subtype = references$reference_subtype,
    selection_reason = "KNOWN_REFERENCE_ACTIVITY",
    stringsAsFactors = FALSE
  )
  add <- function(ids, cohort, reason) {
    ids <- setdiff(as.character(ids), selection$activity_id)
    if (!length(ids)) return(invisible(NULL))
    selection <<- rbind(selection, data.frame(
      activity_id = ids, cohort = cohort, reference_subtype = NA_character_,
      selection_reason = reason, stringsAsFactors = FALSE
    ))
  }

  available <- eligible[!eligible$activity_id %in% selection$activity_id, , drop = FALSE]
  for (chronology in 1:5) for (distance in 1:3) {
    cell <- available[
      available$chronology_band == chronology & available$distance_band == distance,
      , drop = FALSE
    ]
    ids <- choose_density_diverse(cell, 2L)
    add(ids, "B_CHRONOLOGY_DISTANCE", sprintf("CHRONOLOGY_%d_DISTANCE_%d", chronology, distance))
    available <- available[!available$activity_id %in% ids, , drop = FALSE]
  }

  available <- eligible[!eligible$activity_id %in% selection$activity_id, , drop = FALSE]
  add(head(available$activity_id[order(-available$gps_sample_count, available$deterministic_rank)], 2),
      "C_SAMPLING_EXTREME", "HIGHEST_GPS_SAMPLE_COUNT")
  available <- eligible[!eligible$activity_id %in% selection$activity_id & eligible$gps_sample_count > 1, , drop = FALSE]
  add(head(available$activity_id[order(available$gps_sample_count, available$deterministic_rank)], 2),
      "C_SAMPLING_EXTREME", "LOWEST_NONTRIVIAL_GPS_SAMPLE_COUNT")
  available <- eligible[
    !eligible$activity_id %in% selection$activity_id &
      is.finite(eligible$samples_per_elapsed_hour) & eligible$samples_per_elapsed_hour > 0,
    , drop = FALSE
  ]
  add(head(available$activity_id[order(available$samples_per_elapsed_hour, available$deterministic_rank)], 2),
      "C_SAMPLING_EXTREME", "LOWEST_SAMPLES_PER_ELAPSED_HOUR")

  for (i in seq_len(4L)) {
    available <- eligible[!eligible$activity_id %in% selection$activity_id, , drop = FALSE]
    if (!nrow(available)) break
    current_counts <- table(eligible$sport_type[match(selection$activity_id, eligible$activity_id)])
    sport_count <- function(x) if (x %in% names(current_counts)) unname(current_counts[[x]]) else 0L
    available$current_sport_count <- vapply(as.character(available$sport_type), sport_count, integer(1))
    available <- available[order(available$current_sport_count, available$sport_type, available$deterministic_rank), , drop = FALSE]
    add(available$activity_id[[1]], "D_SPORT_DIVERSITY", "UNDERREPRESENTED_OUTDOOR_SPORT")
  }

  available <- eligible[!eligible$activity_id %in% selection$activity_id, , drop = FALSE]
  add(head(available$activity_id[order(-available$non_moving_time_seconds, available$deterministic_rank)], 2),
      "E_ELAPSED_MOVING_DELTA", "LARGEST_ELAPSED_MOVING_DELTA")

  expected_size <- min(as.integer(target_size), nrow(eligible))
  if (nrow(selection) < expected_size) {
    available <- eligible[!eligible$activity_id %in% selection$activity_id, , drop = FALSE]
    add(head(available$activity_id[order(available$deterministic_rank)], expected_size - nrow(selection)),
        "F_DETERMINISTIC_FILL", "COHORT_SHORTFALL_FILL")
  }
  selection <- head(selection, expected_size)
  manifest <- merge(selection, eligible, by = "activity_id", all.x = TRUE, sort = FALSE)
  manifest <- manifest[match(selection$activity_id, manifest$activity_id), , drop = FALSE]
  manifest$sample_definition_version <- TRACK_CALIBRATION_VERSION
  manifest$cutoff_utc <- TRACK_CALIBRATION_CUTOFF_UTC
  manifest$selected_at_utc <- selected_at_utc
  manifest$eligible_population_count <- nrow(eligible)
  manifest$manifest_position <- seq_len(nrow(manifest))
  manifest
}

validate_track_calibration_manifest <- function(manifest) {
  required <- c(
    "activity_id", "cohort", "selection_reason", "sample_definition_version",
    "cutoff_utc", "eligible_population_count", "manifest_position", "eligibility_status"
  )
  missing <- setdiff(required, names(manifest))
  if (length(missing)) stop("Manifest missing column(s): ", paste(missing, collapse = ", "), call. = FALSE)
  ids <- validate_track_audit_activity_ids(manifest$activity_id, maximum_ids = TRACK_CALIBRATION_TARGET_SIZE)
  if (length(ids) != nrow(manifest)) stop("Manifest activity IDs must be unique.", call. = FALSE)
  if (any(manifest$sample_definition_version != TRACK_CALIBRATION_VERSION) ||
      any(manifest$cutoff_utc != TRACK_CALIBRATION_CUTOFF_UTC)) {
    stop("Manifest version or cutoff does not match the governed calibration definition.", call. = FALSE)
  }
  population_counts <- unique(manifest$eligible_population_count)
  if (length(population_counts) != 1L || is.na(population_counts)) {
    stop("Manifest has inconsistent eligible-population metadata.", call. = FALSE)
  }
  expected <- min(TRACK_CALIBRATION_TARGET_SIZE, population_counts)
  if (nrow(manifest) != expected) stop("Manifest size is inconsistent with its eligible population.", call. = FALSE)
  if (any(manifest$eligibility_status != "ELIGIBLE")) stop("Manifest contains an ineligible activity.", call. = FALSE)
  missing_refs <- setdiff(track_calibration_references()$activity_id, ids)
  if (length(missing_refs)) stop("Manifest is missing reference activity ID(s): ", paste(missing_refs, collapse = ", "), call. = FALSE)
  manifest[order(as.integer(manifest$manifest_position)), , drop = FALSE]
}

write_track_calibration_manifest <- function(manifest, path) {
  manifest <- validate_track_calibration_manifest(manifest)
  if (file.exists(path)) stop("Refusing to overwrite authoritative manifest: ", path, call. = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(manifest, path, row.names = FALSE, na = "")
  invisible(path)
}

read_track_calibration_manifest <- function(path) {
  validate_track_calibration_manifest(utils::read.csv(
    path, stringsAsFactors = FALSE, colClasses = c(activity_id = "character")
  ))
}

fetch_one_activity_track_samples <- function(connection, activity_id, get_query = DBI::dbGetQuery) {
  activity_id <- validate_track_audit_activity_ids(activity_id, maximum_ids = 1L)
  get_query(connection, paste0(
    "SELECT CAST(activity_id AS CHAR) AS activity_id, sample_index, latitude, longitude, ",
    "time_seconds, distance_metres FROM cycling_platform_silver.activity_streams ",
    "WHERE activity_id = ? ORDER BY sample_index"
  ), params = list(activity_id[[1]]))
}

track_calibration_distributions <- function(result, segment_count) {
  metrics <- c(
    "elapsed_time_interval_seconds", "geographic_displacement_metres",
    "implied_geographic_speed_metres_per_second", "device_distance_increment_metres",
    "gps_device_distance_signed_difference_metres",
    "gps_device_distance_absolute_difference_metres",
    "gps_device_distance_relative_discrepancy"
  )
  do.call(rbind, lapply(metrics, function(metric) {
    distribution <- result$summary[[metric]]
    data.frame(
      activity_id = result$summary$activity_id, metric = metric,
      valid_count = as.integer(distribution[["count"]]),
      missing_count = as.integer(segment_count - distribution[["count"]]),
      minimum = unname(distribution[["minimum"]]), mean = unname(distribution[["mean"]]),
      p50 = unname(distribution[["p50"]]), p90 = unname(distribution[["p90"]]),
      p95 = unname(distribution[["p95"]]), p99 = unname(distribution[["p99"]]),
      maximum = unname(distribution[["maximum"]]), stringsAsFactors = FALSE
    )
  }))
}

calibration_extra_diagnostics <- function(result, limit = 3L) {
  segments <- result$segments
  if (!nrow(segments)) return(empty_track_diagnostics())
  finite_speed <- which(is.finite(segments$implied_geographic_speed_metres_per_second) &
    segments$implied_geographic_speed_metres_per_second > 0)
  plausible <- integer()
  if (length(finite_speed)) {
    ceiling <- stats::quantile(
      segments$implied_geographic_speed_metres_per_second[finite_speed], 0.95,
      names = FALSE, type = 7
    )
    plausible <- finite_speed[
      segments$implied_geographic_speed_metres_per_second[finite_speed] <= ceiling &
        is.finite(segments$gps_device_distance_absolute_difference_metres[finite_speed])
    ]
    plausible <- plausible[order(
      segments$gps_device_distance_absolute_difference_metres[plausible], decreasing = TRUE
    )]
  }
  zero_device_movement <- which(
    is.finite(segments$device_distance_difference_metres) &
      abs(segments$device_distance_difference_metres) <= 1e-9 &
      is.finite(segments$geographic_displacement_metres) &
      segments$geographic_displacement_metres > 0
  )
  zero_device_movement <- zero_device_movement[order(
    segments$geographic_displacement_metres[zero_device_movement], decreasing = TRUE
  )]
  rbind(
    track_segment_diagnostic_rows(segments, plausible,
      "GPS_DEVICE_DISAGREEMENT_WITHIN_ACTIVITY_P95_SPEED", limit),
    track_segment_diagnostic_rows(segments, zero_device_movement,
      "ZERO_DEVICE_INCREMENT_WITH_GEOGRAPHIC_MOVEMENT", limit)
  )
}

calibration_reference_diagnostics <- function(result) {
  references <- track_calibration_reference_segments()
  references <- references[references$activity_id == result$summary$activity_id, , drop = FALSE]
  if (!nrow(references)) return(empty_track_diagnostics())
  if (!nrow(result$segments)) indexes <- rep(NA_integer_, nrow(references)) else {
  indexes <- match(
    paste(references$from_sample_index, references$to_sample_index),
    paste(result$segments$from_sample_index, result$segments$to_sample_index)
  )
  }
  rows <- track_segment_diagnostic_rows(
    result$segments, indexes[!is.na(indexes)], "REFERENCE_SEGMENT", nrow(references)
  )
  if (nrow(rows)) rows$reference_segment <- references$reference_segment[!is.na(indexes)]
  missing <- which(is.na(indexes))
  if (length(missing)) {
    placeholders <- empty_track_diagnostics()[rep(NA_integer_, length(missing)), , drop = FALSE]
    placeholders$diagnostic_type <- "REFERENCE_SEGMENT_MISSING"
    placeholders$activity_id <- result$summary$activity_id
    placeholders$from_sample_index <- references$from_sample_index[missing]
    placeholders$to_sample_index <- references$to_sample_index[missing]
    placeholders$reference_segment <- references$reference_segment[missing]
    rows <- rbind(rows, placeholders)
  }
  rows
}

bound_track_calibration_diagnostics <- function(diagnostics, per_category_limit = 30L) {
  if (!nrow(diagnostics)) return(diagnostics)
  groups <- split(seq_len(nrow(diagnostics)), diagnostics$diagnostic_type)
  retained <- unlist(lapply(groups, function(indexes) {
    reference <- indexes[diagnostics$is_reference_segment[indexes] %in% TRUE]
    ordinary <- setdiff(indexes, reference)
    c(reference, head(ordinary, max(0L, per_category_limit - length(reference))))
  }), use.names = FALSE)
  diagnostics[sort(unique(retained)), , drop = FALSE]
}

flatten_track_calibration_summary <- function(result, manifest_row, query_seconds, profile_seconds) {
  base <- track_integrity_summary_row(result)
  distributions <- result$summary[c(
    "elapsed_time_interval_seconds", "geographic_displacement_metres",
    "implied_geographic_speed_metres_per_second", "device_distance_increment_metres",
    "gps_device_distance_signed_difference_metres",
    "gps_device_distance_absolute_difference_metres",
    "gps_device_distance_relative_discrepancy"
  )]
  for (metric in names(distributions)) for (statistic in c("mean", "p50", "p90", "p95", "p99", "maximum")) {
    base[[paste(metric, statistic, sep = "_")]] <- unname(distributions[[metric]][[statistic]])
  }
  metadata <- manifest_row[, c(
    "cohort", "reference_subtype", "selection_reason", "start_datetime_utc",
    "activity_year",
    "start_date_local", "sport_type", "is_manual", "distance_metres",
    "moving_time_seconds", "elapsed_time_seconds", "gps_sample_count",
    "samples_per_elapsed_hour", "samples_per_moving_hour", "samples_per_kilometre",
    "non_moving_time_seconds", "chronology_band", "distance_band",
    "sampling_density_band"
  ), drop = FALSE]
  base$duplicate_timestamp_count <- result$summary$duplicate_timestamp_count
  base$decreasing_timestamp_count <- result$summary$decreasing_timestamp_count
  base$repeated_cumulative_distance_count <-
    result$summary$repeated_cumulative_distance_count
  cbind(metadata, base, processing_status = "SUCCESS", error_message = NA_character_,
        query_duration_seconds = query_seconds, profile_duration_seconds = profile_seconds,
        stringsAsFactors = FALSE)
}

run_track_calibration <- function(
  connection,
  manifest,
  get_samples = fetch_one_activity_track_samples,
  diagnostic_limit = 3L
) {
  manifest <- validate_track_calibration_manifest(manifest)
  summaries <- distributions <- diagnostics <- list()
  failures <- character()
  started <- proc.time()[["elapsed"]]
  maximum_samples <- 0L
  total_samples <- 0L
  for (i in seq_len(nrow(manifest))) {
    activity_id <- manifest$activity_id[[i]]
    query_started <- proc.time()[["elapsed"]]
    samples <- tryCatch(get_samples(connection, activity_id), error = identity)
    query_seconds <- proc.time()[["elapsed"]] - query_started
    if (inherits(samples, "error") || !nrow(samples)) {
      message_text <- if (inherits(samples, "error")) conditionMessage(samples) else "No Silver track samples returned."
      failures <- c(failures, activity_id)
      summaries[[i]] <- data.frame(
        cohort = manifest$cohort[[i]], reference_subtype = manifest$reference_subtype[[i]],
        selection_reason = manifest$selection_reason[[i]], activity_id = activity_id,
        processing_status = "FAILED", error_message = message_text,
        query_duration_seconds = query_seconds, profile_duration_seconds = NA_real_,
        stringsAsFactors = FALSE
      )
      next
    }
    maximum_samples <- max(maximum_samples, nrow(samples))
    total_samples <- total_samples + nrow(samples)
    profile_started <- proc.time()[["elapsed"]]
    result <- tryCatch(
      profile_activity_track_integrity(samples, diagnostic_limit, include_segments = TRUE),
      error = identity
    )
    profile_seconds <- proc.time()[["elapsed"]] - profile_started
    if (inherits(result, "error")) {
      failures <- c(failures, activity_id)
      summaries[[i]] <- data.frame(
        cohort = manifest$cohort[[i]], reference_subtype = manifest$reference_subtype[[i]],
        selection_reason = manifest$selection_reason[[i]], activity_id = activity_id,
        processing_status = "FAILED", error_message = conditionMessage(result),
        query_duration_seconds = query_seconds, profile_duration_seconds = profile_seconds,
        stringsAsFactors = FALSE
      )
      next
    }
    summaries[[i]] <- flatten_track_calibration_summary(
      result, manifest[i, , drop = FALSE], query_seconds, profile_seconds
    )
    distributions[[i]] <- track_calibration_distributions(result, max(0L, nrow(samples) - 1L))
    ordinary <- result$diagnostics
    ordinary$is_reference_segment <- rep(FALSE, nrow(ordinary))
    ordinary$reference_segment <- rep(NA_character_, nrow(ordinary))
    extra <- calibration_extra_diagnostics(result, diagnostic_limit)
    extra$is_reference_segment <- rep(FALSE, nrow(extra))
    extra$reference_segment <- rep(NA_character_, nrow(extra))
    reference <- calibration_reference_diagnostics(result)
    reference$is_reference_segment <- rep(TRUE, nrow(reference))
    if (!"reference_segment" %in% names(reference)) {
      reference$reference_segment <- rep(NA_character_, nrow(reference))
    }
    if (any(reference$diagnostic_type == "REFERENCE_SEGMENT_MISSING")) {
      failures <- c(failures, activity_id)
      summaries[[i]]$processing_status <- "FAILED"
      summaries[[i]]$error_message <-
        "One or more governed reference segment pairs were not present."
    }
    diagnostics[[i]] <- rbind(ordinary, extra, reference)
    rm(samples, result)
  }
  bind_rows <- function(rows) {
    rows <- rows[!vapply(rows, is.null, logical(1))]
    if (!length(rows)) return(data.frame())
    all_names <- unique(unlist(lapply(rows, names)))
    rows <- lapply(rows, function(row) {
      for (name in setdiff(all_names, names(row))) row[[name]] <- NA
      row[, all_names, drop = FALSE]
    })
    do.call(rbind, rows)
  }
  diagnostics_frame <- bind_rows(diagnostics)
  if (nrow(diagnostics_frame)) {
    diagnostics_frame <- bound_track_calibration_diagnostics(diagnostics_frame)
    diagnostics_frame <- diagnostics_frame[
      order(!diagnostics_frame$is_reference_segment, diagnostics_frame$diagnostic_type,
            diagnostics_frame$activity_id, diagnostics_frame$from_sample_index), , drop = FALSE
    ]
  }
  list(
    activity_summary = bind_rows(summaries),
    segment_distribution_summary = bind_rows(distributions),
    diagnostic_segments = diagnostics_frame,
    complete = length(failures) == 0L,
    failed_activity_ids = unique(failures),
    elapsed_seconds = proc.time()[["elapsed"]] - started,
    maximum_activity_sample_count = maximum_samples,
    total_sample_rows_processed = total_samples
  )
}

write_track_calibration_outputs <- function(result, manifest, output_directory) {
  dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(manifest, file.path(output_directory, "gps_track_calibration_v1_manifest.csv"), row.names = FALSE, na = "")
  utils::write.csv(result$activity_summary, file.path(output_directory, "activity_summary.csv"), row.names = FALSE, na = "")
  utils::write.csv(result$segment_distribution_summary, file.path(output_directory, "segment_distribution_summary.csv"), row.names = FALSE, na = "")
  utils::write.csv(result$diagnostic_segments, file.path(output_directory, "diagnostic_segments.csv"), row.names = FALSE, na = "")
  invisible(output_directory)
}
