GEOGRAPHIC_CALIBRATION_EVIDENCE_VERSION <- "gps-track-calibration-evidence-v1"
GEOGRAPHIC_CALIBRATION_SPLIT_VERSION <- "gps-track-calibration-split-v1"

geographic_initial_bearing_degrees <- function(
  latitude_from,
  longitude_from,
  latitude_to,
  longitude_to
) {
  valid <- track_coordinate_is_valid(latitude_from, longitude_from) &
    track_coordinate_is_valid(latitude_to, longitude_to)
  result <- rep(NA_real_, length(latitude_from))
  if (!any(valid)) return(result)

  radians <- pi / 180
  latitude_from_radians <- latitude_from[valid] * radians
  latitude_to_radians <- latitude_to[valid] * radians
  longitude_delta <- (longitude_to[valid] - longitude_from[valid]) * radians
  y <- sin(longitude_delta) * cos(latitude_to_radians)
  x <- cos(latitude_from_radians) * sin(latitude_to_radians) -
    sin(latitude_from_radians) * cos(latitude_to_radians) * cos(longitude_delta)
  result[valid] <- (atan2(y, x) / radians + 360) %% 360
  result
}

geographic_absolute_bearing_change_degrees <- function(inbound, outbound) {
  change <- abs(outbound - inbound) %% 360
  pmin(change, 360 - change)
}

repeated_coordinate_run_evidence <- function(samples) {
  n <- nrow(samples)
  if (!n) {
    return(data.frame(
      sample_index = integer(), repeated_coordinate_run_length = integer(),
      repeated_coordinate_run_elapsed_seconds = numeric()
    ))
  }
  valid <- track_coordinate_is_valid(samples$latitude, samples$longitude)
  same_as_previous <- c(FALSE, valid[-1L] & valid[-n] &
    samples$latitude[-1L] == samples$latitude[-n] &
    samples$longitude[-1L] == samples$longitude[-n])
  run_id <- cumsum(!same_as_previous)
  run_groups <- split(seq_len(n), run_id)
  run_length <- integer(n)
  run_elapsed <- rep(NA_real_, n)
  for (indexes in run_groups) {
    run_length[indexes] <- length(indexes)
    first_time <- samples$time_seconds[indexes[[1L]]]
    last_time <- samples$time_seconds[indexes[[length(indexes)]]]
    elapsed <- if (is.finite(first_time) && is.finite(last_time) && last_time >= first_time) {
      last_time - first_time
    } else {
      NA_real_
    }
    run_elapsed[indexes] <- elapsed
  }
  data.frame(
    sample_index = as.integer(samples$sample_index),
    repeated_coordinate_run_length = run_length,
    repeated_coordinate_run_elapsed_seconds = run_elapsed
  )
}

activity_observation_local_context <- function(samples, segments, sample_indexes) {
  sample_indexes <- unique(as.integer(sample_indexes))
  sample_indexes <- sample_indexes[!is.na(sample_indexes)]
  positions <- match(sample_indexes, samples$sample_index)
  found <- !is.na(positions)
  sample_indexes <- sample_indexes[found]
  positions <- positions[found]
  if (!length(positions)) return(data.frame())

  repeated <- repeated_coordinate_run_evidence(samples)
  rows <- lapply(seq_along(positions), function(i) {
    position <- positions[[i]]
    previous_position <- if (position > 1L) position - 1L else NA_integer_
    next_position <- if (position < nrow(samples)) position + 1L else NA_integer_
    previous_segment <- if (!is.na(previous_position)) position - 1L else NA_integer_
    next_segment <- if (!is.na(next_position)) position else NA_integer_

    bridge_displacement <- NA_real_
    inbound_bearing <- outbound_bearing <- bearing_change <- NA_real_
    if (!is.na(previous_position) && !is.na(next_position)) {
      endpoints_valid <- track_coordinate_is_valid(
        samples$latitude[previous_position], samples$longitude[previous_position]
      ) && track_coordinate_is_valid(
        samples$latitude[next_position], samples$longitude[next_position]
      )
      if (endpoints_valid) {
        bridge_displacement <- haversine_distance_metres(
          samples$latitude[previous_position], samples$longitude[previous_position],
          samples$latitude[next_position], samples$longitude[next_position]
        )
      }
      if (track_coordinate_is_valid(samples$latitude[position], samples$longitude[position])) {
        inbound_bearing <- geographic_initial_bearing_degrees(
          samples$latitude[previous_position], samples$longitude[previous_position],
          samples$latitude[position], samples$longitude[position]
        )
        outbound_bearing <- geographic_initial_bearing_degrees(
          samples$latitude[position], samples$longitude[position],
          samples$latitude[next_position], samples$longitude[next_position]
        )
        inbound_displacement <- segments$geographic_displacement_metres[previous_segment]
        outbound_displacement <- segments$geographic_displacement_metres[next_segment]
        if (is.finite(inbound_displacement) && inbound_displacement > 1e-9 &&
            is.finite(outbound_displacement) && outbound_displacement > 1e-9) {
          bearing_change <- geographic_absolute_bearing_change_degrees(
            inbound_bearing, outbound_bearing
          )
        }
      }
    }

    segment_value <- function(segment_position, column) {
      if (is.na(segment_position) || segment_position < 1L ||
          segment_position > nrow(segments)) return(NA_real_)
      as.numeric(segments[[column]][segment_position])
    }

    data.frame(
      activity_id = as.character(samples$activity_id[position]),
      sample_index = as.integer(samples$sample_index[position]),
      latitude = as.numeric(samples$latitude[position]),
      longitude = as.numeric(samples$longitude[position]),
      time_seconds = as.numeric(samples$time_seconds[position]),
      distance_metres = as.numeric(samples$distance_metres[position]),
      previous_sample_index = if (is.na(previous_position)) NA_integer_ else
        as.integer(samples$sample_index[previous_position]),
      next_sample_index = if (is.na(next_position)) NA_integer_ else
        as.integer(samples$sample_index[next_position]),
      previous_to_current_displacement_metres = segment_value(
        previous_segment, "geographic_displacement_metres"
      ),
      current_to_next_displacement_metres = segment_value(
        next_segment, "geographic_displacement_metres"
      ),
      previous_to_next_displacement_metres = bridge_displacement,
      previous_to_current_elapsed_seconds = segment_value(
        previous_segment, "elapsed_time_difference_seconds"
      ),
      current_to_next_elapsed_seconds = segment_value(
        next_segment, "elapsed_time_difference_seconds"
      ),
      previous_to_current_device_distance_metres = segment_value(
        previous_segment, "device_distance_difference_metres"
      ),
      current_to_next_device_distance_metres = segment_value(
        next_segment, "device_distance_difference_metres"
      ),
      previous_to_current_implied_speed_mps = segment_value(
        previous_segment, "implied_geographic_speed_metres_per_second"
      ),
      current_to_next_implied_speed_mps = segment_value(
        next_segment, "implied_geographic_speed_metres_per_second"
      ),
      inbound_bearing_degrees = inbound_bearing,
      outbound_bearing_degrees = outbound_bearing,
      absolute_bearing_change_degrees = bearing_change,
      repeated_coordinate_run_length = repeated$repeated_coordinate_run_length[position],
      repeated_coordinate_run_elapsed_seconds =
        repeated$repeated_coordinate_run_elapsed_seconds[position],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

calibration_candidate_observation_indexes <- function(
  samples,
  profile,
  maximum_observations = 30L
) {
  diagnostic_indexes <- unique(c(
    profile$diagnostics$from_sample_index,
    profile$diagnostics$to_sample_index
  ))
  repeated <- repeated_coordinate_run_evidence(samples)
  repeated <- repeated[repeated$repeated_coordinate_run_length > 1L, , drop = FALSE]
  if (nrow(repeated)) {
    repeated <- repeated[order(
      -repeated$repeated_coordinate_run_length,
      -ifelse(is.na(repeated$repeated_coordinate_run_elapsed_seconds),
        -Inf, repeated$repeated_coordinate_run_elapsed_seconds),
      repeated$sample_index
    ), , drop = FALSE]
  }
  indexes <- unique(c(diagnostic_indexes, repeated$sample_index))
  head(indexes[!is.na(indexes)], as.integer(maximum_observations))
}

profile_activity_geographic_calibration_evidence <- function(
  samples,
  diagnostic_limit = 3L,
  context_limit = 30L,
  context_sample_indexes = NULL
) {
  profile <- profile_activity_track_integrity(
    samples,
    diagnostic_limit = diagnostic_limit,
    include_segments = TRUE
  )
  if (is.null(context_sample_indexes)) {
    context_sample_indexes <- calibration_candidate_observation_indexes(
      samples, profile, context_limit
    )
  } else {
    context_sample_indexes <- head(unique(context_sample_indexes), context_limit)
  }
  list(
    profile = profile,
    local_context = activity_observation_local_context(
      samples, profile$segments, context_sample_indexes
    )
  )
}

geographic_sport_family <- function(sport_type) {
  sport <- tolower(trimws(ifelse(is.na(sport_type), "", sport_type)))
  result <- rep("OTHER", length(sport))
  result[grepl("ride|cycling|bike|handcycle|velomobile", sport)] <- "CYCLING"
  result[grepl("run", sport)] <- "RUNNING"
  result[grepl("walk|hike|mountaineer", sport)] <- "WALKING_HIKING"
  result[grepl("sail|kayak|canoe|row|surf|swim|water", sport)] <- "WATER"
  result[grepl("ski|snow|skate", sport)] <- "WINTER"
  result[!nzchar(sport)] <- "UNKNOWN"
  result
}

geographic_elapsed_time_band <- function(values) {
  result <- rep("MISSING", length(values))
  result[!is.na(values) & !is.finite(values)] <- "INVALID"
  finite <- is.finite(values)
  result[finite & values <= 0] <- "NON_POSITIVE"
  result[finite & values > 0 & values <= 1] <- "GT_0_TO_1S"
  result[finite & values > 1 & values <= 2] <- "GT_1_TO_2S"
  result[finite & values > 2 & values <= 5] <- "GT_2_TO_5S"
  result[finite & values > 5 & values <= 10] <- "GT_5_TO_10S"
  result[finite & values > 10 & values <= 30] <- "GT_10_TO_30S"
  result[finite & values > 30 & values <= 60] <- "GT_30_TO_60S"
  result[finite & values > 60 & values <= 300] <- "GT_60_TO_300S"
  result[finite & values > 300 & values <= 900] <- "GT_300_TO_900S"
  result[finite & values > 900 & values <= 3600] <- "GT_900_TO_3600S"
  result[finite & values > 3600] <- "GT_3600S"
  result
}

geographic_population_histogram_spec <- function() {
  list(
    elapsed_time_difference_seconds = c(-Inf, 0, 1, 2, 5, 10, 30, 60, 300, 900, 3600, Inf),
    geographic_displacement_metres = c(-Inf, 0, 0.1, 1, 5, 10, 25, 50, 100, 250, 500, 1000, 5000, Inf),
    implied_geographic_speed_metres_per_second = c(-Inf, 0, 0.5, 1, 2, 3, 5, 8, 12, 20, 30, 50, 100, Inf),
    device_distance_difference_metres = c(-Inf, -100, -10, -1, 0, 0.1, 1, 5, 10, 25, 50, 100, 250, 500, 1000, Inf),
    gps_device_distance_signed_difference_metres = c(-Inf, -1000, -250, -100, -25, -5, -1, 0, 1, 5, 25, 100, 250, 1000, Inf),
    gps_device_distance_absolute_difference_metres = c(-Inf, 0, 0.1, 1, 5, 10, 25, 50, 100, 250, 500, 1000, 5000, Inf),
    gps_device_distance_relative_discrepancy = c(-Inf, 0, 0.01, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99, 1, Inf)
  )
}

new_geographic_population_aggregator <- function() {
  state <- new.env(parent = emptyenv())
  state$histogram_counts <- numeric()
  state$summary_counts <- numeric()
  state$activity_count <- 0L
  state$segment_count <- 0L
  state$sample_count <- 0L
  state
}

geographic_add_named_counts <- function(current, keys, values = rep(1, length(keys))) {
  if (!length(keys)) return(current)
  additions <- tapply(values, keys, sum)
  missing <- setdiff(names(additions), names(current))
  if (length(missing)) current[missing] <- 0
  current[names(additions)] <- current[names(additions)] + as.numeric(additions)
  current
}

geographic_population_key <- function(...) paste(..., sep = "\034")

add_activity_to_geographic_population <- function(
  state,
  segments,
  sport_family,
  recording_density_band,
  sample_count = nrow(segments) + as.integer(nrow(segments) > 0L)
) {
  stopifnot(is.environment(state), length(sport_family) == 1L,
    length(recording_density_band) == 1L)
  state$activity_count <- state$activity_count + 1L
  state$segment_count <- state$segment_count + nrow(segments)
  state$sample_count <- state$sample_count + as.integer(sample_count)
  if (!nrow(segments)) return(invisible(state))

  elapsed_band <- geographic_elapsed_time_band(
    segments$elapsed_time_difference_seconds
  )
  specification <- geographic_population_histogram_spec()
  for (metric in names(specification)) {
    values <- as.numeric(segments[[metric]])
    missing <- is.na(values)
    invalid <- !missing & !is.finite(values)
    valid <- is.finite(values)
    stratum_key <- geographic_population_key(
      sport_family, recording_density_band, elapsed_band, metric
    )
    for (type in c("denominator", "valid", "missing", "invalid")) {
      selector <- switch(type,
        denominator = rep(TRUE, length(values)), valid = valid,
        missing = missing, invalid = invalid
      )
      if (!any(selector)) next
      state$summary_counts <- geographic_add_named_counts(
        state$summary_counts,
        geographic_population_key(stratum_key[selector], type)
      )
    }
    if (any(valid)) {
      bin <- cut(
        values[valid], breaks = specification[[metric]], labels = FALSE,
        include.lowest = TRUE, right = TRUE
      )
      state$histogram_counts <- geographic_add_named_counts(
        state$histogram_counts,
        geographic_population_key(stratum_key[valid], bin)
      )
    }
  }
  invisible(state)
}

geographic_split_key <- function(keys, expected_fields) {
  values <- strsplit(keys, "\034", fixed = TRUE)
  matrix <- do.call(rbind, values)
  if (ncol(matrix) != expected_fields) stop("Malformed population aggregation key.", call. = FALSE)
  matrix
}

geographic_population_aggregation_result <- function(state) {
  specification <- geographic_population_histogram_spec()
  histogram <- data.frame()
  if (length(state$histogram_counts)) {
    keys <- geographic_split_key(names(state$histogram_counts), 5L)
    histogram <- data.frame(
      sport_family = keys[, 1], recording_density_band = keys[, 2],
      elapsed_time_band = keys[, 3], metric = keys[, 4],
      bin_index = as.integer(keys[, 5]),
      segment_count = as.numeric(state$histogram_counts),
      stringsAsFactors = FALSE
    )
    histogram$bin_lower_exclusive <- mapply(function(metric, index) {
      specification[[metric]][index]
    }, histogram$metric, histogram$bin_index)
    histogram$bin_upper_inclusive <- mapply(function(metric, index) {
      specification[[metric]][index + 1L]
    }, histogram$metric, histogram$bin_index)
  }

  summary <- data.frame()
  if (length(state$summary_counts)) {
    keys <- geographic_split_key(names(state$summary_counts), 5L)
    long <- data.frame(
      sport_family = keys[, 1], recording_density_band = keys[, 2],
      elapsed_time_band = keys[, 3], metric = keys[, 4],
      count_type = keys[, 5], count = as.numeric(state$summary_counts),
      stringsAsFactors = FALSE
    )
    identity <- long[, 1:4, drop = FALSE]
    identity$key <- do.call(geographic_population_key, identity)
    rows <- split(seq_len(nrow(long)), identity$key)
    summary <- do.call(rbind, lapply(rows, function(indexes) {
      values <- stats::setNames(long$count[indexes], long$count_type[indexes])
      count_or_zero <- function(name) {
        if (!name %in% names(values)) 0 else unname(values[[name]])
      }
      data.frame(
        long[indexes[[1]], 1:4, drop = FALSE],
        segment_denominator = count_or_zero("denominator"),
        valid_count = count_or_zero("valid"),
        missing_count = count_or_zero("missing"),
        invalid_count = count_or_zero("invalid"),
        stringsAsFactors = FALSE
      )
    }))
    rownames(summary) <- NULL
  }
  list(
    histogram = histogram,
    stratum_summary = summary,
    activity_count = state$activity_count,
    sample_count = state$sample_count,
    segment_count = state$segment_count
  )
}

prepare_geographic_population_candidates <- function(candidates) {
  candidates <- prepare_track_calibration_candidates(candidates)
  candidates <- candidates[candidates$eligibility_status == "ELIGIBLE", , drop = FALSE]
  candidates <- candidates[!duplicated(candidates$activity_id), , drop = FALSE]
  candidates$sport_family <- geographic_sport_family(candidates$sport_type)
  candidates$recording_density_band_number <- rank_quantile_band(
    candidates$samples_per_elapsed_hour, 3L, candidates$deterministic_rank
  )
  candidates$recording_density_band <- c("LOW", "MIDDLE", "HIGH")[
    candidates$recording_density_band_number
  ]
  candidates
}

select_geographic_population_pilot <- function(candidates, maximum_activities) {
  if (is.null(maximum_activities)) {
    return(candidates[order(candidates$deterministic_rank), , drop = FALSE])
  }
  maximum_activities <- as.integer(maximum_activities)
  group <- interaction(
    candidates$sport_family, candidates$recording_density_band,
    drop = TRUE, lex.order = TRUE
  )
  rank_in_group <- ave(
    seq_len(nrow(candidates)), group,
    FUN = function(indexes) rank(candidates$deterministic_rank[indexes], ties.method = "first")
  )
  ordered <- order(rank_in_group, group, candidates$deterministic_rank)
  candidates[head(ordered, maximum_activities), , drop = FALSE]
}

run_geographic_population_calibration <- function(
  connection,
  candidates,
  maximum_activities = NULL,
  get_samples = fetch_one_activity_track_samples
) {
  candidates <- prepare_geographic_population_candidates(candidates)
  eligible_population_count <- nrow(candidates)
  candidates <- select_geographic_population_pilot(candidates, maximum_activities)
  state <- new_geographic_population_aggregator()
  execution <- vector("list", nrow(candidates))
  started <- proc.time()[["elapsed"]]
  maximum_samples <- 0L
  for (i in seq_len(nrow(candidates))) {
    activity_id <- candidates$activity_id[[i]]
    activity_started <- proc.time()[["elapsed"]]
    samples <- tryCatch(get_samples(connection, activity_id), error = identity)
    query_seconds <- proc.time()[["elapsed"]] - activity_started
    if (inherits(samples, "error") || !nrow(samples)) {
      execution[[i]] <- data.frame(
        activity_id = activity_id, sport_family = candidates$sport_family[[i]],
        recording_density_band = candidates$recording_density_band[[i]],
        processing_status = "FAILED",
        error_message = if (inherits(samples, "error")) conditionMessage(samples) else
          "No Silver track samples returned.",
        sample_count = 0L, segment_count = 0L,
        query_duration_seconds = query_seconds, profile_duration_seconds = NA_real_,
        stringsAsFactors = FALSE
      )
      next
    }
    maximum_samples <- max(maximum_samples, nrow(samples))
    profile_started <- proc.time()[["elapsed"]]
    profile <- tryCatch(
      profile_activity_track_integrity(samples, diagnostic_limit = 3L, include_segments = TRUE),
      error = identity
    )
    profile_seconds <- proc.time()[["elapsed"]] - profile_started
    if (inherits(profile, "error")) {
      execution[[i]] <- data.frame(
        activity_id = activity_id, sport_family = candidates$sport_family[[i]],
        recording_density_band = candidates$recording_density_band[[i]],
        processing_status = "FAILED", error_message = conditionMessage(profile),
        sample_count = nrow(samples), segment_count = 0L,
        query_duration_seconds = query_seconds,
        profile_duration_seconds = profile_seconds, stringsAsFactors = FALSE
      )
      next
    }
    add_activity_to_geographic_population(
      state, profile$segments, candidates$sport_family[[i]],
      candidates$recording_density_band[[i]], sample_count = nrow(samples)
    )
    execution[[i]] <- data.frame(
      activity_id = activity_id, sport_family = candidates$sport_family[[i]],
      recording_density_band = candidates$recording_density_band[[i]],
      processing_status = "SUCCESS", error_message = NA_character_,
      sample_count = nrow(samples), segment_count = nrow(profile$segments),
      query_duration_seconds = query_seconds,
      profile_duration_seconds = profile_seconds, stringsAsFactors = FALSE
    )
    rm(samples, profile)
  }
  aggregation <- geographic_population_aggregation_result(state)
  aggregation$activity_execution <- if (length(execution)) do.call(rbind, execution) else data.frame()
  aggregation$complete <- nrow(aggregation$activity_execution) == 0L ||
    all(aggregation$activity_execution$processing_status == "SUCCESS")
  aggregation$elapsed_seconds <- proc.time()[["elapsed"]] - started
  aggregation$maximum_activity_sample_count <- maximum_samples
  aggregation$eligible_population_count <- eligible_population_count
  aggregation
}

write_geographic_population_calibration_outputs <- function(
  result,
  output_directory,
  repository_root = getwd()
) {
  names <- c(
    "population_segment_histogram.csv", "population_stratum_summary.csv",
    "population_activity_execution.csv", "population_failures.csv"
  )
  destination <- validate_track_evidence_output_destination(
    output_directory, names, repository_root
  )
  dir.create(destination$output_directory, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    result$histogram,
    destination$paths[[1L]],
    row.names = FALSE, na = ""
  )
  utils::write.csv(
    result$stratum_summary,
    destination$paths[[2L]],
    row.names = FALSE, na = ""
  )
  utils::write.csv(
    result$activity_execution,
    destination$paths[[3L]],
    row.names = FALSE, na = ""
  )
  failures <- result$activity_execution[
    result$activity_execution$processing_status != "SUCCESS", , drop = FALSE
  ]
  utils::write.csv(
    failures,
    destination$paths[[4L]],
    row.names = FALSE, na = ""
  )
  invisible(output_directory)
}

geographic_reference_window_requests <- function() {
  data.frame(
    case_key = c(
      "CAFE_STOP", rep("CORRUPTED_GPS_EXCURSION", 4), "MISSING_ROUTE",
      "DUPLICATE_TIMESTAMPS", "CROPPED_CONTINUATION_TUNNEL", "MISSING_SAILING_PASSAGE",
      "READING_GAP_TUNNEL", "CROPPED_MULTI_DAY_CONTINUATION"
    ),
    activity_id = c(
      "20445541114", rep("3057187825", 4), "2705450947", "31709557",
      "659466921", "9283774065", "15562928333", "227124704"
    ),
    focus_from_sample_index = c(7251L, 2537L, 2527L, 2519L, 2526L, 7639L,
      NA, NA, NA, NA, NA),
    focus_to_sample_index = c(7252L, 2538L, 2528L, 2520L, 2527L, 7640L,
      NA, NA, NA, NA, NA),
    window_radius = 3L,
    evidence_provenance = c(
      rep("CURRENT_SOURCE_REFERENCE", 6), "CURRENT_SOURCE_LOOKUP_REQUIRED",
      "HISTORICAL_EVIDENCE_REQUIRED", "CURRENT_SOURCE_LOOKUP_REQUIRED",
      "CURRENT_SOURCE_LOOKUP_REQUIRED", "HISTORICAL_EVIDENCE_REQUIRED"
    ),
    evidence_note = c(
      "Known genuine stationary interval", rep("Known erroneous GPS excursion", 4),
      "Known missing intervening route", "Locate duplicate timestamp window",
      "Current source is post-crop; do not treat it as the historical incident",
      "Locate the missing-passage window", "Locate recording-gap/tunnel window",
      "Current source is post-crop; do not treat it as the historical incident"
    ),
    stringsAsFactors = FALSE
  )
}

write_geographic_reference_window_requests <- function(path) {
  if (file.exists(path)) stop("Refusing to overwrite reference-window request file.", call. = FALSE)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(geographic_reference_window_requests(), path, row.names = FALSE, na = "")
  invisible(path)
}

geographic_activity_partition <- function(activity_ids, holdout_fraction = 0.2) {
  vapply(as.character(activity_ids), function(activity_id) {
    hash <- digest::digest(
      paste(GEOGRAPHIC_CALIBRATION_SPLIT_VERSION, activity_id, sep = "|"),
      algo = "sha256", serialize = FALSE
    )
    value <- strtoi(substr(hash, 1L, 7L), base = 16L) / (16^7 - 1)
    if (value < holdout_fraction) "HOLDOUT" else "CALIBRATION"
  }, character(1))
}

extract_geographic_reference_windows <- function(
  connection,
  requests,
  get_samples = fetch_one_activity_track_samples
) {
  required <- c(
    "case_key", "activity_id", "focus_from_sample_index", "focus_to_sample_index",
    "window_radius", "evidence_provenance", "evidence_note"
  )
  missing <- setdiff(required, names(requests))
  if (length(missing)) stop("Reference-window requests missing: ", paste(missing, collapse = ", "), call. = FALSE)
  observations <- segments <- statuses <- list()
  for (activity_id in unique(as.character(requests$activity_id))) {
    activity_requests <- requests[as.character(requests$activity_id) == activity_id, , drop = FALSE]
    located <- !is.na(activity_requests$focus_from_sample_index) &
      !is.na(activity_requests$focus_to_sample_index)
    if (!any(located)) {
      statuses[[length(statuses) + 1L]] <- data.frame(
        activity_id = activity_id, extraction_status = "WINDOW_NOT_LOCATED",
        detail = paste(unique(activity_requests$evidence_note), collapse = "; "),
        stringsAsFactors = FALSE
      )
      next
    }
    samples <- tryCatch(get_samples(connection, activity_id), error = identity)
    if (inherits(samples, "error") || !nrow(samples)) {
      statuses[[length(statuses) + 1L]] <- data.frame(
        activity_id = activity_id, extraction_status = "FAILED",
        detail = if (inherits(samples, "error")) conditionMessage(samples) else
          "No Silver track samples returned.", stringsAsFactors = FALSE
      )
      next
    }
    profile <- profile_activity_track_integrity(samples, diagnostic_limit = 3L, include_segments = TRUE)
    for (request_index in which(located)) {
      request <- activity_requests[request_index, , drop = FALSE]
      lower <- request$focus_from_sample_index - request$window_radius
      upper <- request$focus_to_sample_index + request$window_radius
      observation_indexes <- samples$sample_index[
        samples$sample_index >= lower & samples$sample_index <= upper
      ]
      context <- activity_observation_local_context(
        samples, profile$segments, observation_indexes
      )
      if (nrow(context)) {
        context$case_key <- request$case_key
        context$evidence_provenance <- request$evidence_provenance
        context$is_focus_observation <- context$sample_index >= request$focus_from_sample_index &
          context$sample_index <= request$focus_to_sample_index
        observations[[length(observations) + 1L]] <- context
      }
      segment_rows <- profile$segments[
        profile$segments$from_sample_index >= lower &
          profile$segments$to_sample_index <= upper, , drop = FALSE
      ]
      if (nrow(segment_rows)) {
        segment_rows$case_key <- request$case_key
        segment_rows$evidence_provenance <- request$evidence_provenance
        segment_rows$is_focus_segment <-
          segment_rows$from_sample_index == request$focus_from_sample_index &
          segment_rows$to_sample_index == request$focus_to_sample_index
        segments[[length(segments) + 1L]] <- segment_rows
      }
    }
    statuses[[length(statuses) + 1L]] <- data.frame(
      activity_id = activity_id, extraction_status = "SUCCESS",
      detail = paste0(sum(located), " located window(s) extracted."), stringsAsFactors = FALSE
    )
  }
  bind <- function(rows) if (length(rows)) do.call(rbind, rows) else data.frame()
  list(observations = bind(observations), segments = bind(segments), status = bind(statuses))
}

geographic_manual_label_template <- function(observations, segments) {
  observation_rows <- if (nrow(observations)) data.frame(
    entity_type = "OBSERVATION", activity_id = as.character(observations$activity_id),
    sample_index = as.integer(observations$sample_index),
    from_sample_index = NA_integer_, to_sample_index = NA_integer_,
    case_key = observations$case_key,
    evidence_provenance = observations$evidence_provenance,
    stringsAsFactors = FALSE
  ) else data.frame()
  segment_rows <- if (nrow(segments)) data.frame(
    entity_type = "SEGMENT", activity_id = as.character(segments$activity_id),
    sample_index = NA_integer_,
    from_sample_index = as.integer(segments$from_sample_index),
    to_sample_index = as.integer(segments$to_sample_index),
    case_key = segments$case_key,
    evidence_provenance = segments$evidence_provenance,
    stringsAsFactors = FALSE
  ) else data.frame()
  rows <- rbind(observation_rows, segment_rows)
  if (!nrow(rows)) return(rows)
  rows <- unique(rows)
  rows$calibration_partition <- geographic_activity_partition(rows$activity_id)
  rows$manual_label <- "UNREVIEWED"
  rows$reviewer <- NA_character_
  rows$reviewed_at_utc <- NA_character_
  rows$reviewer_rationale <- NA_character_
  rows$evidence_version <- GEOGRAPHIC_CALIBRATION_EVIDENCE_VERSION
  rows
}

validate_geographic_manual_labels <- function(labels) {
  allowed <- c("ACCEPTED", "UNCERTAIN", "REJECTED", "UNREVIEWED")
  if (any(!labels$manual_label %in% allowed)) stop("Unsupported manual calibration label.", call. = FALSE)
  partitions <- split(labels$calibration_partition, labels$activity_id)
  if (any(vapply(partitions, function(x) length(unique(x)) != 1L, logical(1)))) {
    stop("An activity cannot appear in both calibration and holdout partitions.", call. = FALSE)
  }
  invisible(TRUE)
}

write_geographic_reference_window_outputs <- function(
  result,
  output_directory,
  repository_root = getwd()
) {
  names <- c(
    "reference_window_observations.csv", "reference_window_segments.csv",
    "reference_window_status.csv", "manual_label_template.csv"
  )
  destination <- validate_track_evidence_output_destination(
    output_directory, names, repository_root
  )
  dir.create(destination$output_directory, recursive = TRUE, showWarnings = FALSE)
  labels <- geographic_manual_label_template(result$observations, result$segments)
  utils::write.csv(result$observations,
    destination$paths[[1L]],
    row.names = FALSE, na = "")
  utils::write.csv(result$segments,
    destination$paths[[2L]],
    row.names = FALSE, na = "")
  utils::write.csv(result$status,
    destination$paths[[3L]],
    row.names = FALSE, na = "")
  utils::write.csv(labels,
    destination$paths[[4L]],
    row.names = FALSE, na = "")
  invisible(output_directory)
}
