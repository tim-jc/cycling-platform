GPS_CONTEXT_FEATURE_CONTRACT_VERSION <- "gps-context-features-v1-experimental"
GPS_QUALIFICATION_BATCH_EXTRACTION_VERSION <- "gps-qualification-batch-v1"

gps_qualification_batch_extra_filenames <- function() {
  c(
    "experimental_observation_context.csv",
    "experimental_segment_context.csv",
    "source_context_completeness.csv",
    "manual_review_worksheet.csv"
  )
}

gps_qualification_batch_root_filenames <- function() {
  c("batch_extraction_manifest.csv", "batch_file_manifest.csv")
}

validate_gps_qualification_batch_requests <- function(
  requests,
  diagnostic_segments,
  activity_manifest
) {
  requests <- validate_governed_gps_reference_window_requests(requests)
  required_diagnostic <- c("activity_id", "from_sample_index", "to_sample_index")
  required_activity <- c("activity_id", "gps_sample_count")
  if (any(!required_diagnostic %in% names(diagnostic_segments))) {
    stop("Diagnostic artifact lacks focus-segment identity columns.", call. = FALSE)
  }
  if (any(!required_activity %in% names(activity_manifest))) {
    stop("Activity manifest lacks activity_id or gps_sample_count.", call. = FALSE)
  }
  diagnostic_segments$activity_id <- as.character(diagnostic_segments$activity_id)
  diagnostic_segments$from_sample_index <- as.integer(diagnostic_segments$from_sample_index)
  diagnostic_segments$to_sample_index <- as.integer(diagnostic_segments$to_sample_index)
  activity_manifest$activity_id <- as.character(activity_manifest$activity_id)
  if (anyDuplicated(activity_manifest$activity_id)) {
    stop("Activity manifest contains duplicate activity IDs.", call. = FALSE)
  }
  activity_position <- match(requests$activity_id, activity_manifest$activity_id)
  if (anyNA(activity_position)) {
    stop(
      "Approved activity is absent from the calibration manifest: ",
      paste(unique(requests$activity_id[is.na(activity_position)]), collapse = ", "),
      call. = FALSE
    )
  }
  sample_count <- suppressWarnings(as.integer(
    activity_manifest$gps_sample_count[activity_position]
  ))
  if (anyNA(sample_count) || any(sample_count < 2L)) {
    stop("Calibration manifest contains invalid GPS sample counts.", call. = FALSE)
  }
  if (any(requests$window_to_sample_index > sample_count)) {
    bad <- requests$case_key[requests$window_to_sample_index > sample_count]
    stop("Requested bounds exceed recorded sample count: ", paste(bad, collapse = ", "), call. = FALSE)
  }
  focus_match <- vapply(seq_len(nrow(requests)), function(index) {
    any(
      diagnostic_segments$activity_id == requests$activity_id[[index]] &
        diagnostic_segments$from_sample_index ==
          requests$focus_segment_from_sample_index[[index]] &
        diagnostic_segments$to_sample_index ==
          requests$focus_segment_to_sample_index[[index]]
    )
  }, logical(1))
  if (any(!focus_match)) {
    stop(
      "Approved focus segment is absent from the diagnostic artifact: ",
      paste(requests$case_key[!focus_match], collapse = ", "),
      call. = FALSE
    )
  }
  partitions <- geographic_activity_partition(requests$activity_id)
  if (any(partitions != "CALIBRATION")) {
    stop(
      "Batch 1 contains a non-CALIBRATION activity: ",
      paste(unique(requests$activity_id[partitions != "CALIBRATION"]), collapse = ", "),
      call. = FALSE
    )
  }
  data.frame(
    requests,
    calibration_partition = partitions,
    recorded_sample_count = sample_count,
    requested_start_is_actual_boundary = requests$window_from_sample_index == 1L,
    requested_end_is_actual_boundary = requests$window_to_sample_index == sample_count,
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

validate_gps_qualification_batch_destinations <- function(
  requests,
  output_directory,
  repository_root = getwd()
) {
  root <- validate_track_evidence_output_destination(
    output_directory,
    gps_qualification_batch_root_filenames(),
    repository_root
  )
  governed <- governed_gps_reference_window_filenames()
  extra <- gps_qualification_batch_extra_filenames()
  cases <- lapply(requests$case_key, function(case_key) {
    validate_track_evidence_output_destination(
      file.path(root$output_directory, case_key),
      c(governed, extra),
      repository_root
    )
  })
  list(root = root, cases = cases)
}

gps_context_circular_resultant_length <- function(bearings) {
  bearings <- bearings[is.finite(bearings)]
  if (length(bearings) < 2L) return(NA_real_)
  radians <- bearings * pi / 180
  sqrt(mean(cos(radians))^2 + mean(sin(radians))^2)
}

gps_context_maximum_bearing_change <- function(bearings) {
  bearings <- bearings[is.finite(bearings)]
  if (length(bearings) < 2L) return(NA_real_)
  max(geographic_absolute_bearing_change_degrees(
    bearings[-length(bearings)], bearings[-1L]
  ))
}

gps_context_ratio <- function(numerator, denominator) {
  if (!is.finite(numerator) || !is.finite(denominator) || denominator == 0) {
    return(NA_real_)
  }
  numerator / denominator
}

gps_context_metric_summary <- function(values, prefix) {
  valid <- values[is.finite(values)]
  stats::setNames(
    list(
      as.integer(length(valid)),
      if (length(valid)) stats::median(valid) else NA_real_,
      if (length(valid)) max(valid) else NA_real_
    ),
    paste0(prefix, c("_valid_count", "_median", "_maximum"))
  )
}

gps_context_segment_bearings <- function(segments) {
  bearings <- geographic_initial_bearing_degrees(
    segments$from_latitude, segments$from_longitude,
    segments$to_latitude, segments$to_longitude
  )
  bearings[!is.finite(segments$geographic_displacement_metres) |
    segments$geographic_displacement_metres <= 1e-9] <- NA_real_
  bearings
}

gps_context_side_summary <- function(segments, expected_count, prefix) {
  bearings <- gps_context_segment_bearings(segments)
  discrepancy <- segments$gps_device_distance_relative_discrepancy
  values <- c(
    list(
      as.integer(nrow(segments)),
      as.integer(sum(
        is.finite(segments$elapsed_time_difference_seconds) &
          is.finite(segments$geographic_displacement_metres)
      )),
      nrow(segments) == expected_count,
      as.integer(sum(
        is.finite(segments$elapsed_time_difference_seconds) &
          segments$elapsed_time_difference_seconds <= 0
      )),
      as.integer(sum(
        is.finite(segments$device_distance_difference_metres) &
          segments$device_distance_difference_metres < 0
      )),
      gps_context_circular_resultant_length(bearings),
      gps_context_maximum_bearing_change(bearings)
    ),
    gps_context_metric_summary(
      segments$geographic_displacement_metres,
      "displacement_metres"
    ),
    gps_context_metric_summary(
      segments$elapsed_time_difference_seconds,
      "elapsed_seconds"
    ),
    gps_context_metric_summary(discrepancy, "relative_discrepancy")
  )
  names(values)[seq_len(7L)] <- c(
    "available_segment_count", "usable_segment_count", "context_complete",
    "nonpositive_elapsed_count", "device_distance_regression_count",
    "heading_resultant_length", "maximum_bearing_change_degrees"
  )
  names(values) <- paste0(prefix, "_", names(values))
  values
}

gps_exact_stationary_run_evidence <- function(samples) {
  count <- nrow(samples)
  if (!count) return(data.frame())
  valid <- track_coordinate_is_valid(samples$latitude, samples$longitude)
  same_previous <- c(FALSE, valid[-1L] & valid[-count] &
    samples$latitude[-1L] == samples$latitude[-count] &
    samples$longitude[-1L] == samples$longitude[-count] &
    is.finite(samples$distance_metres[-1L]) &
    is.finite(samples$distance_metres[-count]) &
    samples$distance_metres[-1L] == samples$distance_metres[-count])
  run_id <- cumsum(!same_previous)
  groups <- split(seq_len(count), run_id)
  result <- data.frame(
    sample_index = as.integer(samples$sample_index),
    exact_stationary_run_length = integer(count),
    exact_stationary_run_elapsed_seconds = rep(NA_real_, count),
    exact_stationary_run_position = character(count),
    stringsAsFactors = FALSE
  )
  for (indexes in groups) {
    result$exact_stationary_run_length[indexes] <- length(indexes)
    first_time <- samples$time_seconds[indexes[[1L]]]
    last_time <- samples$time_seconds[indexes[[length(indexes)]]]
    if (is.finite(first_time) && is.finite(last_time) && last_time >= first_time) {
      result$exact_stationary_run_elapsed_seconds[indexes] <- last_time - first_time
    }
    positions <- rep("INTERIOR", length(indexes))
    if (length(indexes) == 1L) {
      positions <- "SINGLETON"
    } else {
      positions[[1L]] <- "START"
      positions[[length(indexes)]] <- "END"
    }
    result$exact_stationary_run_position[indexes] <- positions
  }
  result
}

gps_context_observation_path_metrics <- function(samples, segments, sample_index, n) {
  position <- match(sample_index, samples$sample_index)
  if (is.na(position)) return(list(
    path_to_bridge_ratio = NA_real_, bridge_distance_zero = NA,
    maximum_local_detour_ratio = NA_real_
  ))
  lower <- max(1L, position - n)
  upper <- min(nrow(samples), position + n)
  path_segments <- segments[
    segments$from_sample_index >= samples$sample_index[[lower]] &
      segments$to_sample_index <= samples$sample_index[[upper]],
    , drop = FALSE
  ]
  path_values <- path_segments$geographic_displacement_metres
  path_distance <- if (length(path_values) && all(is.finite(path_values))) {
    sum(path_values)
  } else {
    NA_real_
  }
  endpoint_valid <- track_coordinate_is_valid(
    samples$latitude[[lower]], samples$longitude[[lower]]
  ) && track_coordinate_is_valid(
    samples$latitude[[upper]], samples$longitude[[upper]]
  )
  bridge <- if (endpoint_valid) haversine_distance_metres(
    samples$latitude[[lower]], samples$longitude[[lower]],
    samples$latitude[[upper]], samples$longitude[[upper]]
  ) else NA_real_
  detours <- numeric()
  if (upper - lower >= 2L) {
    for (middle in seq.int(lower + 1L, upper - 1L)) {
      local <- segments[
        (segments$from_sample_index == samples$sample_index[[middle - 1L]] &
          segments$to_sample_index == samples$sample_index[[middle]]) |
          (segments$from_sample_index == samples$sample_index[[middle]] &
            segments$to_sample_index == samples$sample_index[[middle + 1L]]),
        , drop = FALSE
      ]
      if (nrow(local) != 2L || any(!is.finite(local$geographic_displacement_metres))) next
      local_bridge <- haversine_distance_metres(
        samples$latitude[[middle - 1L]], samples$longitude[[middle - 1L]],
        samples$latitude[[middle + 1L]], samples$longitude[[middle + 1L]]
      )
      ratio <- gps_context_ratio(sum(local$geographic_displacement_metres), local_bridge)
      if (is.finite(ratio)) detours <- c(detours, ratio)
    }
  }
  list(
    path_to_bridge_ratio = gps_context_ratio(path_distance, bridge),
    bridge_distance_zero = is.finite(bridge) && bridge == 0,
    maximum_local_detour_ratio = if (length(detours)) max(detours) else NA_real_
  )
}

gps_context_observation_row <- function(
  samples,
  segments,
  stationary,
  sample_index,
  case_key,
  n
) {
  preceding <- tail(segments[segments$to_sample_index <= sample_index, , drop = FALSE], n)
  following <- head(segments[segments$from_sample_index >= sample_index, , drop = FALSE], n)
  stationary_row <- stationary[stationary$sample_index == sample_index, , drop = FALSE]
  path <- gps_context_observation_path_metrics(samples, segments, sample_index, n)
  values <- c(
    list(
      case_key = case_key, activity_id = as.character(samples$activity_id[[1L]]),
      sample_index = as.integer(sample_index), context_window_segments = as.integer(n)
    ),
    gps_context_side_summary(preceding, n, "preceding"),
    gps_context_side_summary(following, n, "following"),
    path,
    as.list(stationary_row[, setdiff(names(stationary_row), "sample_index"), drop = FALSE])
  )
  as.data.frame(values, stringsAsFactors = FALSE, check.names = FALSE)
}

gps_context_segment_row <- function(segments, from_index, to_index, case_key, n) {
  focus <- segments[
    segments$from_sample_index == from_index & segments$to_sample_index == to_index,
    , drop = FALSE
  ]
  if (nrow(focus) != 1L) stop("Context focus segment is missing or duplicated.", call. = FALSE)
  preceding <- tail(segments[segments$to_sample_index <= from_index, , drop = FALSE], n)
  following <- head(segments[segments$from_sample_index >= to_index, , drop = FALSE], n)
  neighbour_displacement <- c(
    preceding$geographic_displacement_metres,
    following$geographic_displacement_metres
  )
  neighbour_elapsed <- c(
    preceding$elapsed_time_difference_seconds,
    following$elapsed_time_difference_seconds
  )
  displacement_median <- stats::median(
    neighbour_displacement[is.finite(neighbour_displacement)], na.rm = TRUE
  )
  elapsed_median <- stats::median(
    neighbour_elapsed[is.finite(neighbour_elapsed) & neighbour_elapsed > 0], na.rm = TRUE
  )
  if (!is.finite(displacement_median)) displacement_median <- NA_real_
  if (!is.finite(elapsed_median)) elapsed_median <- NA_real_
  values <- c(
    list(
      case_key = case_key, activity_id = as.character(focus$activity_id[[1L]]),
      from_sample_index = as.integer(from_index), to_sample_index = as.integer(to_index),
      context_window_segments = as.integer(n),
      focus_displacement_metres = focus$geographic_displacement_metres[[1L]],
      focus_elapsed_seconds = focus$elapsed_time_difference_seconds[[1L]],
      focus_device_distance_increment_metres = focus$device_distance_difference_metres[[1L]],
      focus_relative_discrepancy = focus$gps_device_distance_relative_discrepancy[[1L]],
      focus_displacement_to_neighbour_median_ratio = gps_context_ratio(
        focus$geographic_displacement_metres[[1L]], displacement_median
      ),
      focus_elapsed_to_neighbour_median_ratio = gps_context_ratio(
        focus$elapsed_time_difference_seconds[[1L]], elapsed_median
      ),
      neighbour_displacement_median_zero = is.finite(displacement_median) &&
        displacement_median == 0,
      neighbour_elapsed_median_zero = is.finite(elapsed_median) && elapsed_median == 0
    ),
    gps_context_side_summary(preceding, n, "preceding"),
    gps_context_side_summary(following, n, "following")
  )
  as.data.frame(values, stringsAsFactors = FALSE, check.names = FALSE)
}

bind_gps_context_rows <- function(rows) {
  if (!length(rows)) return(data.frame())
  columns <- unique(unlist(lapply(rows, names), use.names = FALSE))
  rows <- lapply(rows, function(row) {
    for (column in setdiff(columns, names(row))) row[[column]] <- NA
    row[, columns, drop = FALSE]
  })
  result <- do.call(rbind, rows)
  rownames(result) <- NULL
  result
}

build_gps_qualification_context_diagnostics <- function(
  source,
  request,
  governed_evidence
) {
  samples <- source$silver_samples[order(source$silver_samples$sample_index), , drop = FALSE]
  profile <- profile_activity_track_integrity(samples, include_segments = TRUE)
  segments <- profile$segments
  stationary <- gps_exact_stationary_run_evidence(samples)
  focus_observations <- c(
    request$focus_from_sample_index[[1L]], request$focus_to_sample_index[[1L]]
  )
  focus_segment <- c(
    request$focus_segment_from_sample_index[[1L]],
    request$focus_segment_to_sample_index[[1L]]
  )
  review_segments <- rbind(
    c(focus_segment[[1L]] - 1L, focus_segment[[1L]]),
    focus_segment,
    c(focus_segment[[2L]], focus_segment[[2L]] + 1L)
  )
  review_segments <- review_segments[
    review_segments[, 1L] >= min(samples$sample_index) &
      review_segments[, 2L] <= max(samples$sample_index),
    , drop = FALSE
  ]
  observation_rows <- list()
  segment_rows <- list()
  for (n in c(3L, 5L)) {
    observation_rows <- c(observation_rows, lapply(focus_observations, function(index) {
      gps_context_observation_row(
        samples, segments, stationary, index, request$case_key[[1L]], n
      )
    }))
    segment_rows <- c(segment_rows, lapply(seq_len(nrow(review_segments)), function(index) {
      gps_context_segment_row(
        segments, review_segments[index, 1L], review_segments[index, 2L],
        request$case_key[[1L]], n
      )
    }))
  }
  observation_context <- bind_gps_context_rows(observation_rows)
  segment_context <- bind_gps_context_rows(segment_rows)
  minimum_index <- min(samples$sample_index)
  maximum_index <- max(samples$sample_index)
  source_context <- data.frame(
    case_key = request$case_key[[1L]],
    activity_id = request$activity_id[[1L]],
    requested_from_sample_index = request$window_from_sample_index[[1L]],
    requested_to_sample_index = request$window_to_sample_index[[1L]],
    returned_from_sample_index = min(
      governed_evidence$reference_window_observations$sample_index
    ),
    returned_to_sample_index = max(
      governed_evidence$reference_window_observations$sample_index
    ),
    activity_first_sample_index = minimum_index,
    activity_last_sample_index = maximum_index,
    requested_start_is_actual_boundary =
      request$window_from_sample_index[[1L]] == minimum_index,
    requested_end_is_actual_boundary =
      request$window_to_sample_index[[1L]] == maximum_index,
    requested_start_is_artificial_boundary =
      request$window_from_sample_index[[1L]] > minimum_index,
    requested_end_is_artificial_boundary =
      request$window_to_sample_index[[1L]] < maximum_index,
    raw_silver_mismatch_count = sum(
      governed_evidence$raw_silver_positional_comparison$any_mismatch
    ),
    source_validation_status = "RAW_SILVER_POSITIONALLY_VERIFIED",
    device_distance_provenance = "UNKNOWN",
    device_distance_provenance_detail = paste(
      "The current Raw/Silver stream contracts do not establish whether",
      "distance is wheel/sensor-measured, GPS-derived, or mixed."
    ),
    stringsAsFactors = FALSE
  )
  list(
    observation_context = observation_context,
    segment_context = segment_context,
    source_context = source_context,
    review_segments = review_segments
  )
}

build_gps_qualification_manual_review_worksheet <- function(
  request,
  source,
  diagnostics
) {
  focus_from <- request$focus_segment_from_sample_index[[1L]]
  focus_to <- request$focus_segment_to_sample_index[[1L]]
  first_index <- min(source$silver_samples$sample_index)
  last_index <- max(source$silver_samples$sample_index)
  rows <- list(
    list("OBSERVATION", "FOCUS_OBSERVATION_FIRST", focus_from, NA, NA, TRUE, NA),
    list("OBSERVATION", "FOCUS_OBSERVATION_SECOND", focus_to, NA, NA, TRUE, NA),
    list("SEGMENT", "FOCUS_SEGMENT", NA, focus_from, focus_to, TRUE, NA),
    list(
      "SEGMENT", "IMMEDIATELY_PRECEDING_SEGMENT", NA, focus_from - 1L, focus_from,
      focus_from > first_index,
      if (focus_from > first_index) NA else "TRUE_ACTIVITY_START"
    ),
    list(
      "SEGMENT", "IMMEDIATELY_FOLLOWING_SEGMENT", NA, focus_to, focus_to + 1L,
      focus_to < last_index,
      if (focus_to < last_index) NA else "TRUE_ACTIVITY_END"
    )
  )
  do.call(rbind, lapply(seq_along(rows), function(index) {
    row <- rows[[index]]
    data.frame(
      case_key = request$case_key[[1L]], activity_id = request$activity_id[[1L]],
      calibration_partition = "CALIBRATION", review_order = as.integer(index),
      entity_type = row[[1L]], review_role = row[[2L]],
      sample_index = as.integer(row[[3L]]),
      from_sample_index = as.integer(row[[4L]]),
      to_sample_index = as.integer(row[[5L]]),
      availability_status = if (isTRUE(row[[6L]])) "AVAILABLE" else "NOT_APPLICABLE",
      not_applicable_reason = as.character(row[[7L]]),
      device_distance_provenance = diagnostics$source_context$device_distance_provenance,
      manual_label = "UNREVIEWED", reviewer = NA_character_,
      reviewed_at_utc = NA_character_, reviewer_rationale = NA_character_,
      evidence_version = GEOGRAPHIC_CALIBRATION_EVIDENCE_VERSION,
      feature_contract_version = GPS_CONTEXT_FEATURE_CONTRACT_VERSION,
      stringsAsFactors = FALSE
    )
  }))
}

extract_gps_qualification_batch <- function(
  connection,
  requests,
  get_evidence = fetch_gps_raw_silver_evidence
) {
  evidence_by_activity <- list()
  results <- vector("list", nrow(requests))
  names(results) <- requests$case_key
  for (index in seq_len(nrow(requests))) {
    request <- requests[index, , drop = FALSE]
    activity_id <- request$activity_id[[1L]]
    if (is.null(evidence_by_activity[[activity_id]])) {
      evidence_by_activity[[activity_id]] <- get_evidence(connection, activity_id)
    }
    source <- evidence_by_activity[[activity_id]]
    governed <- build_governed_gps_reference_window(
      raw_streams = source$raw_streams,
      silver_samples = source$silver_samples,
      window_from_sample_index = request$window_from_sample_index,
      window_to_sample_index = request$window_to_sample_index,
      focus_from_sample_index = request$focus_from_sample_index,
      focus_to_sample_index = request$focus_to_sample_index,
      focus_segment_from_sample_index = request$focus_segment_from_sample_index,
      focus_segment_to_sample_index = request$focus_segment_to_sample_index,
      case_key = request$case_key,
      evidence_note = request$evidence_note
    )
    diagnostics <- build_gps_qualification_context_diagnostics(
      source, request, governed
    )
    review <- build_gps_qualification_manual_review_worksheet(
      request, source, diagnostics
    )
    results[[index]] <- list(
      governed = governed,
      observation_context = diagnostics$observation_context,
      segment_context = diagnostics$segment_context,
      source_context = diagnostics$source_context,
      manual_review_worksheet = review
    )
  }
  results
}

gps_sha256_file <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required.", call. = FALSE)
  digest::digest(path, algo = "sha256", file = TRUE)
}

write_gps_qualification_batch <- function(
  results,
  requests,
  output_directory,
  request_path,
  diagnostic_path,
  activity_manifest_path,
  repository_commit_sha,
  repository_root = getwd()
) {
  destinations <- validate_gps_qualification_batch_destinations(
    requests, output_directory, repository_root
  )
  dir.create(destinations$root$output_directory, recursive = TRUE, showWarnings = FALSE)
  extraction_timestamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  manifest_rows <- list()
  written_paths <- character()
  for (index in seq_along(results)) {
    result <- results[[index]]
    case_directory <- destinations$cases[[index]]$output_directory
    governed_paths <- write_governed_gps_reference_window(
      result$governed, case_directory, repository_root
    )
    extra_paths <- file.path(case_directory, gps_qualification_batch_extra_filenames())
    utils::write.csv(result$observation_context, extra_paths[[1L]], row.names = FALSE, na = "")
    utils::write.csv(result$segment_context, extra_paths[[2L]], row.names = FALSE, na = "")
    utils::write.csv(result$source_context, extra_paths[[3L]], row.names = FALSE, na = "")
    utils::write.csv(result$manual_review_worksheet, extra_paths[[4L]], row.names = FALSE, na = "")
    written_paths <- c(written_paths, unname(governed_paths), extra_paths)
    source_context <- result$source_context
    manifest_rows[[index]] <- data.frame(
      case_key = requests$case_key[[index]],
      activity_id = requests$activity_id[[index]],
      calibration_partition = "CALIBRATION",
      requested_from_sample_index = requests$window_from_sample_index[[index]],
      requested_to_sample_index = requests$window_to_sample_index[[index]],
      returned_from_sample_index = source_context$returned_from_sample_index,
      returned_to_sample_index = source_context$returned_to_sample_index,
      focus_segment_from_sample_index = requests$focus_segment_from_sample_index[[index]],
      focus_segment_to_sample_index = requests$focus_segment_to_sample_index[[index]],
      observation_count = nrow(result$governed$reference_window_observations),
      segment_count = nrow(result$governed$reference_window_segments),
      review_row_count = nrow(result$manual_review_worksheet),
      raw_silver_mismatch_count = source_context$raw_silver_mismatch_count,
      source_validation_status = source_context$source_validation_status,
      device_distance_provenance = source_context$device_distance_provenance,
      extraction_status = "SUCCESS",
      extraction_implementation_version = GPS_QUALIFICATION_BATCH_EXTRACTION_VERSION,
      feature_contract_version = GPS_CONTEXT_FEATURE_CONTRACT_VERSION,
      repository_commit_sha = repository_commit_sha,
      extracted_at_utc = extraction_timestamp,
      stringsAsFactors = FALSE
    )
  }
  batch_manifest <- do.call(rbind, manifest_rows)
  root_paths <- destinations$root$paths
  utils::write.csv(batch_manifest, root_paths[[1L]], row.names = FALSE, na = "")
  written_paths <- c(written_paths, root_paths[[1L]])
  input_paths <- normalizePath(
    c(request_path, diagnostic_path, activity_manifest_path),
    winslash = "/", mustWork = TRUE
  )
  file_manifest <- data.frame(
    file_role = c(rep("INPUT", length(input_paths)), rep("OUTPUT", length(written_paths))),
    path = c(input_paths, normalizePath(written_paths, winslash = "/", mustWork = TRUE)),
    sha256 = vapply(c(input_paths, written_paths), gps_sha256_file, character(1)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(file_manifest, root_paths[[2L]], row.names = FALSE, na = "")
  invisible(list(batch_manifest = batch_manifest, file_manifest = file_manifest))
}
