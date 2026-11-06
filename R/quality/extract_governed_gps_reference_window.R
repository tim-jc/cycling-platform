#' Build one governed GPS reference window from positionally aligned Raw/Silver evidence.
#'
#' @param raw_streams Raw time, latlng, and distance stream rows.
#' @param silver_samples Full ordered Silver samples for one activity.
#' @param window_from_sample_index First observation to retain.
#' @param window_to_sample_index Last observation to retain.
#' @param focus_from_sample_index First focus observation.
#' @param focus_to_sample_index Last focus observation.
#' @param focus_segment_from_sample_index Start of the primary focus segment.
#' @param focus_segment_to_sample_index End of the primary focus segment.
#' @param case_key Governed case identifier.
#' @param evidence_note Human-readable evidence request note.
#' @return Named governed evidence tables ready for CSV output.
build_governed_gps_reference_window <- function(
  raw_streams,
  silver_samples,
  window_from_sample_index,
  window_to_sample_index,
  focus_from_sample_index,
  focus_to_sample_index,
  focus_segment_from_sample_index,
  focus_segment_to_sample_index,
  case_key,
  evidence_note
) {
  indexes <- as.integer(c(
    window_from_sample_index, window_to_sample_index,
    focus_from_sample_index, focus_to_sample_index,
    focus_segment_from_sample_index, focus_segment_to_sample_index
  ))
  if (anyNA(indexes) || indexes[[1L]] > indexes[[2L]] ||
      indexes[[3L]] > indexes[[4L]] || indexes[[5L]] >= indexes[[6L]]) {
    stop("Reference-window sample indexes are invalid.", call. = FALSE)
  }
  if (indexes[[3L]] < indexes[[1L]] || indexes[[4L]] > indexes[[2L]] ||
      indexes[[5L]] < indexes[[1L]] || indexes[[6L]] > indexes[[2L]]) {
    stop("Focus evidence must lie inside the requested reference window.", call. = FALSE)
  }

  positional_result <- build_duplicate_timestamp_evidence(
    raw_streams = raw_streams,
    silver_samples = silver_samples,
    context_observations = 0L
  )
  positional <- positional_result$positional_comparison
  expected_sample_indexes <- seq.int(indexes[[1L]], indexes[[2L]])
  silver_window_indexes <- sort(as.integer(silver_samples$sample_index[
    silver_samples$sample_index >= indexes[[1L]] &
      silver_samples$sample_index <= indexes[[2L]]
  ]))
  if (!identical(silver_window_indexes, expected_sample_indexes)) {
    stop("Requested reference-window observations are missing or out of order.", call. = FALSE)
  }
  positional_window <- positional[
    positional$sample_index >= indexes[[1L]] &
      positional$sample_index <= indexes[[2L]],
    , drop = FALSE
  ]
  if (!identical(as.integer(positional_window$sample_index), expected_sample_indexes)) {
    stop("Requested reference-window observations are missing or out of order.", call. = FALSE)
  }
  if (any(positional_window$any_mismatch)) {
    mismatches <- positional_window$sample_index[positional_window$any_mismatch]
    stop(
      "Raw/Silver positional mismatch in requested reference window at sample(s): ",
      paste(mismatches, collapse = ", "),
      call. = FALSE
    )
  }

  ordered_silver <- silver_samples[
    order(silver_samples$sample_index),
    c("activity_id", "sample_index", "latitude", "longitude", "time_seconds", "distance_metres"),
    drop = FALSE
  ]
  profile <- profile_activity_track_integrity(
    ordered_silver,
    diagnostic_limit = 3L,
    include_segments = TRUE
  )
  segments <- profile$segments
  observations <- activity_observation_local_context(
    ordered_silver,
    segments,
    expected_sample_indexes
  )
  window_segments <- segments[
    segments$from_sample_index >= indexes[[1L]] &
      segments$to_sample_index <= indexes[[2L]],
    , drop = FALSE
  ]
  expected_from_indexes <- seq.int(indexes[[1L]], indexes[[2L]] - 1L)
  expected_to_indexes <- seq.int(indexes[[1L]] + 1L, indexes[[2L]])
  if (!identical(as.integer(observations$sample_index), expected_sample_indexes) ||
      !identical(as.integer(window_segments$from_sample_index), expected_from_indexes) ||
      !identical(as.integer(window_segments$to_sample_index), expected_to_indexes)) {
    stop("Governed observation or segment evidence contains a sample-index gap.", call. = FALSE)
  }

  evidence_provenance <- "CURRENT_RAW_SILVER_OFFLINE_EXTRACTION"
  observations$case_key <- case_key
  observations$evidence_provenance <- evidence_provenance
  observations$is_focus_observation <-
    observations$sample_index >= indexes[[3L]] &
    observations$sample_index <= indexes[[4L]]
  window_segments$case_key <- case_key
  window_segments$evidence_provenance <- evidence_provenance
  window_segments$is_focus_segment <-
    window_segments$from_sample_index == indexes[[5L]] &
    window_segments$to_sample_index == indexes[[6L]]

  request <- data.frame(
    case_key = case_key,
    activity_id = as.character(observations$activity_id[[1L]]),
    focus_from_sample_index = indexes[[3L]],
    focus_to_sample_index = indexes[[4L]],
    window_radius = indexes[[3L]] - indexes[[1L]],
    window_from_sample_index = indexes[[1L]],
    window_to_sample_index = indexes[[2L]],
    focus_segment_from_sample_index = indexes[[5L]],
    focus_segment_to_sample_index = indexes[[6L]],
    evidence_provenance = evidence_provenance,
    evidence_note = evidence_note,
    stringsAsFactors = FALSE
  )
  status <- data.frame(
    activity_id = as.character(observations$activity_id[[1L]]),
    case_key = case_key,
    extraction_status = "SUCCESS",
    observation_count = nrow(observations),
    segment_count = nrow(window_segments),
    raw_silver_mismatch_count = sum(positional_window$any_mismatch),
    detail = sprintf(
      "Complete governed window extracted for samples %d through %d.",
      indexes[[1L]], indexes[[2L]]
    ),
    stringsAsFactors = FALSE
  )
  labels <- geographic_manual_label_template(observations, window_segments)
  if (nrow(labels) != nrow(observations) + nrow(window_segments) ||
      any(labels$manual_label != "UNREVIEWED")) {
    stop("Manual-review template is incomplete or contains assigned labels.", call. = FALSE)
  }

  list(
    reference_window_request = request,
    raw_stream_metadata = positional_result$raw_stream_metadata,
    raw_silver_positional_comparison = positional_window,
    reference_window_observations = observations,
    reference_window_segments = window_segments,
    reference_window_status = status,
    manual_label_template = labels
  )
}

write_governed_gps_reference_window <- function(
  evidence,
  output_directory,
  repository_root = getwd()
) {
  repository_root <- normalizePath(repository_root, mustWork = TRUE)
  output_directory <- normalizePath(output_directory, mustWork = FALSE)
  if (identical(output_directory, repository_root) ||
      startsWith(output_directory, paste0(repository_root, .Platform$file.sep))) {
    stop("Output directory must be outside the repository.", call. = FALSE)
  }
  filenames <- c(
    reference_window_request = "reference_window_request.csv",
    raw_stream_metadata = "raw_stream_metadata.csv",
    raw_silver_positional_comparison = "raw_silver_positional_comparison.csv",
    reference_window_observations = "reference_window_observations.csv",
    reference_window_segments = "reference_window_segments.csv",
    reference_window_status = "reference_window_status.csv",
    manual_label_template = "manual_label_template.csv"
  )
  paths <- stats::setNames(file.path(output_directory, filenames), names(filenames))
  existing <- paths[file.exists(paths)]
  if (length(existing)) {
    stop(
      "Refusing to overwrite existing evidence file(s): ",
      paste(basename(existing), collapse = ", "),
      call. = FALSE
    )
  }
  dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
  for (name in names(filenames)) {
    utils::write.csv(evidence[[name]], paths[[name]], row.names = FALSE, na = "")
  }
  invisible(paths)
}
