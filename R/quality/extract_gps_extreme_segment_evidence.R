#' Build offline Raw/Silver evidence for the largest-displacement and
#' highest-implied-speed segments in one activity.
#'
#' @param raw_streams Raw time, latlng, and distance stream rows.
#' @param silver_samples Silver samples for the same activity.
#' @param context_observations Number of observations retained on each side.
#' @return Named evidence tables suitable for CSV output.
gps_extreme_segment_evidence_filenames <- function() {
  c(
    extraction_summary = "extraction_summary.csv",
    raw_stream_metadata = "raw_stream_metadata.csv",
    anomaly_candidates = "anomaly_candidates.csv",
    candidate_window_observations = "candidate_window_observations.csv",
    candidate_window_segments = "candidate_window_segments.csv",
    extraction_status = "extraction_status.csv"
  )
}

build_gps_extreme_segment_evidence <- function(
  raw_streams,
  silver_samples,
  context_observations = 5L,
  case_keys = c("READING_LARGEST_DISPLACEMENT", "KINGSTON_HIGHEST_IMPLIED_SPEED")
) {
  context_observations <- as.integer(context_observations)
  if (is.na(context_observations) || context_observations < 0L) {
    stop("context_observations must be a non-negative integer.", call. = FALSE)
  }
  case_keys <- trimws(as.character(case_keys))
  if (length(case_keys) != 2L || any(!nzchar(case_keys)) ||
      any(!grepl("^[A-Za-z0-9][A-Za-z0-9_-]*$", case_keys)) ||
      anyDuplicated(case_keys)) {
    stop("case_keys must contain two unique safe identifiers.", call. = FALSE)
  }

  positional_result <- build_duplicate_timestamp_evidence(
    raw_streams = raw_streams,
    silver_samples = silver_samples,
    context_observations = context_observations
  )
  positional <- positional_result$positional_comparison
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
  if (!nrow(segments)) stop("No Silver segments are available for the activity.", call. = FALSE)

  finite_displacement <- which(is.finite(segments$geographic_displacement_metres))
  finite_speed <- which(is.finite(segments$implied_geographic_speed_metres_per_second))
  if (!length(finite_displacement) || !length(finite_speed)) {
    stop("The activity has no finite displacement or implied-speed evidence.", call. = FALSE)
  }
  largest_displacement_row <- finite_displacement[[which.max(
    segments$geographic_displacement_metres[finite_displacement]
  )]]
  highest_speed_row <- finite_speed[[which.max(
    segments$implied_geographic_speed_metres_per_second[finite_speed]
  )]]

  candidate_rows <- c(largest_displacement_row, highest_speed_row)
  candidates <- segments[candidate_rows, , drop = FALSE]
  candidates$case_key <- case_keys
  candidates$selection_rule <- c(
    "MAX_GEOGRAPHIC_DISPLACEMENT",
    "MAX_IMPLIED_GEOGRAPHIC_SPEED"
  )
  candidates$evidence_provenance <- "CURRENT_RAW_SILVER_OFFLINE_EXTRACTION"

  observation_windows <- vector("list", nrow(candidates))
  segment_windows <- vector("list", nrow(candidates))
  for (index in seq_len(nrow(candidates))) {
    lower <- max(1L, candidates$from_sample_index[[index]] - context_observations)
    upper <- min(max(positional$sample_index), candidates$to_sample_index[[index]] + context_observations)

    observation_rows <- positional[
      positional$sample_index >= lower & positional$sample_index <= upper,
      , drop = FALSE
    ]
    observation_rows$case_key <- candidates$case_key[[index]]
    observation_rows$evidence_provenance <- candidates$evidence_provenance[[index]]
    observation_rows$is_focus_observation <- observation_rows$sample_index %in%
      c(candidates$from_sample_index[[index]], candidates$to_sample_index[[index]])
    observation_windows[[index]] <- observation_rows

    segment_rows <- segments[
      segments$from_sample_index >= lower & segments$to_sample_index <= upper,
      , drop = FALSE
    ]
    segment_rows$case_key <- candidates$case_key[[index]]
    segment_rows$evidence_provenance <- candidates$evidence_provenance[[index]]
    segment_rows$is_focus_segment <-
      segment_rows$from_sample_index == candidates$from_sample_index[[index]] &
      segment_rows$to_sample_index == candidates$to_sample_index[[index]]
    segment_windows[[index]] <- segment_rows
  }

  observations <- do.call(rbind, observation_windows)
  window_segments <- do.call(rbind, segment_windows)
  rownames(observations) <- NULL
  rownames(window_segments) <- NULL
  status <- data.frame(
    activity_id = as.character(candidates$activity_id),
    case_key = candidates$case_key,
    extraction_status = "SUCCESS",
    detail = sprintf(
      "Located segment %d -> %d by %s with %d observations of requested context per side where available.",
      candidates$from_sample_index,
      candidates$to_sample_index,
      candidates$selection_rule,
      context_observations
    ),
    stringsAsFactors = FALSE
  )

  list(
    extraction_summary = data.frame(
      activity_id = as.character(candidates$activity_id[[1L]]),
      raw_position_count = nrow(positional_result$positional_comparison),
      silver_position_count = nrow(silver_samples),
      raw_silver_mismatch_count = sum(positional$any_mismatch),
      candidate_count = nrow(candidates),
      stringsAsFactors = FALSE
    ),
    raw_stream_metadata = positional_result$raw_stream_metadata,
    anomaly_candidates = candidates,
    candidate_window_observations = observations,
    candidate_window_segments = window_segments,
    extraction_status = status
  )
}

write_gps_extreme_segment_evidence <- function(
  evidence,
  output_directory,
  repository_root = getwd()
) {
  filenames <- gps_extreme_segment_evidence_filenames()
  destination <- validate_track_evidence_output_destination(
    output_directory, unname(filenames), repository_root
  )
  paths <- stats::setNames(destination$paths, names(filenames))
  dir.create(destination$output_directory, recursive = TRUE, showWarnings = FALSE)
  for (name in names(filenames)) {
    utils::write.csv(evidence[[name]], paths[[name]], row.names = FALSE, na = "")
  }
  invisible(paths)
}
