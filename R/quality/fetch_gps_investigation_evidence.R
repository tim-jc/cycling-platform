validate_gps_investigation_activity_id <- function(activity_id) {
  activity_id <- trimws(as.character(activity_id))
  if (length(activity_id) != 1L || is.na(activity_id) ||
      !grepl("^[0-9]+$", activity_id)) {
    stop("Activity ID must contain digits only.", call. = FALSE)
  }
  activity_id
}

fetch_gps_raw_silver_evidence <- function(
  connection,
  activity_id,
  get_query = DBI::dbGetQuery
) {
  activity_id <- validate_gps_investigation_activity_id(activity_id)
  raw_streams <- get_query(
    connection,
    paste(
      "SELECT activity_id, stream_type, original_size, stream_payload",
      "FROM cycling_platform_raw.activity_streams",
      "WHERE activity_id = ? AND stream_type IN ('time', 'latlng', 'distance')",
      "ORDER BY stream_type"
    ),
    params = list(activity_id)
  )
  silver_samples <- get_query(
    connection,
    paste(
      "SELECT activity_id, sample_index, time_seconds, latitude, longitude, distance_metres",
      "FROM cycling_platform_silver.activity_streams",
      "WHERE activity_id = ?",
      "ORDER BY sample_index"
    ),
    params = list(activity_id)
  )
  list(raw_streams = raw_streams, silver_samples = silver_samples)
}

gps_optional_index_pair <- function(requests, from_name, to_name, window_from, window_to) {
  from <- suppressWarnings(as.integer(requests[[from_name]]))
  to <- suppressWarnings(as.integer(requests[[to_name]]))
  supplied <- !is.na(from) | !is.na(to)
  if (any(supplied & (is.na(from) | is.na(to)))) {
    stop(from_name, " and ", to_name, " must be supplied together.", call. = FALSE)
  }
  if (any(supplied & (from > to | from < window_from | to > window_to))) {
    stop(from_name, " and ", to_name, " must lie inside the requested window.", call. = FALSE)
  }
  list(from = from, to = to, supplied = supplied)
}

validate_governed_gps_reference_window_requests <- function(requests) {
  required <- c(
    "activity_id", "case_key", "window_from_sample_index",
    "window_to_sample_index", "focus_from_sample_index",
    "focus_to_sample_index", "focus_segment_from_sample_index",
    "focus_segment_to_sample_index", "evidence_note"
  )
  missing <- setdiff(required, names(requests))
  if (length(missing)) {
    stop("Reference-window request is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!nrow(requests)) stop("Reference-window request contains no rows.", call. = FALSE)

  requests <- requests[, required, drop = FALSE]
  requests$activity_id <- vapply(
    requests$activity_id, validate_gps_investigation_activity_id, character(1)
  )
  requests$case_key <- trimws(as.character(requests$case_key))
  if (any(!grepl("^[A-Za-z0-9][A-Za-z0-9_-]*$", requests$case_key))) {
    stop("case_key must use only letters, digits, underscores, or hyphens.", call. = FALSE)
  }
  if (anyDuplicated(requests$case_key)) {
    stop("Reference-window case_key values must be unique.", call. = FALSE)
  }
  requests$evidence_note <- trimws(as.character(requests$evidence_note))
  if (any(is.na(requests$evidence_note) | !nzchar(requests$evidence_note))) {
    stop("Every reference-window request requires an evidence_note.", call. = FALSE)
  }

  window_from <- suppressWarnings(as.integer(requests$window_from_sample_index))
  window_to <- suppressWarnings(as.integer(requests$window_to_sample_index))
  if (anyNA(window_from) || anyNA(window_to) ||
      any(window_from < 1L | window_to <= window_from)) {
    stop(
      "Reference-window sample bounds must be positive, ordered, and contain a segment.",
      call. = FALSE
    )
  }
  focus <- gps_optional_index_pair(
    requests, "focus_from_sample_index", "focus_to_sample_index",
    window_from, window_to
  )
  segment <- gps_optional_index_pair(
    requests, "focus_segment_from_sample_index", "focus_segment_to_sample_index",
    window_from, window_to
  )
  if (any(segment$supplied & segment$to != segment$from + 1L)) {
    stop("Focus segment endpoints must identify one consecutive segment.", call. = FALSE)
  }

  requests$window_from_sample_index <- window_from
  requests$window_to_sample_index <- window_to
  requests$focus_from_sample_index <- focus$from
  requests$focus_to_sample_index <- focus$to
  requests$focus_segment_from_sample_index <- segment$from
  requests$focus_segment_to_sample_index <- segment$to
  requests
}

read_governed_gps_reference_window_requests <- function(path) {
  requests <- utils::read.csv(
    normalizePath(path, mustWork = TRUE),
    colClasses = c(activity_id = "character"),
    stringsAsFactors = FALSE,
    na.strings = c("", "NA")
  )
  validate_governed_gps_reference_window_requests(requests)
}

extract_governed_gps_reference_window_requests <- function(
  connection,
  requests,
  get_evidence = fetch_gps_raw_silver_evidence
) {
  requests <- validate_governed_gps_reference_window_requests(requests)
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
    results[[index]] <- build_governed_gps_reference_window(
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
  }
  results
}

governed_gps_reference_window_filenames <- function() {
  c(
    "reference_window_request.csv", "raw_stream_metadata.csv",
    "raw_silver_positional_comparison.csv", "reference_window_observations.csv",
    "reference_window_segments.csv", "reference_window_status.csv",
    "manual_label_template.csv"
  )
}

validate_governed_gps_reference_window_destinations <- function(
  case_keys,
  output_directory,
  repository_root = getwd()
) {
  if (!length(case_keys) || any(!nzchar(case_keys)) || anyDuplicated(case_keys) ||
      any(!grepl("^[A-Za-z0-9][A-Za-z0-9_-]*$", case_keys))) {
    stop("Governed reference-window outputs require unique safe case keys.", call. = FALSE)
  }
  root <- validate_track_evidence_output_destination(
    output_directory, character(), repository_root
  )$output_directory
  lapply(case_keys, function(case_key) {
    validate_track_evidence_output_destination(
      file.path(root, case_key),
      governed_gps_reference_window_filenames(),
      repository_root
    )
  })
}

write_governed_gps_reference_window_requests <- function(
  results,
  output_directory,
  repository_root = getwd()
) {
  if (!length(results) || is.null(names(results)) || any(!nzchar(names(results))) ||
      anyDuplicated(names(results))) {
    stop("Governed reference-window results require unique case-key names.", call. = FALSE)
  }
  destinations <- validate_governed_gps_reference_window_destinations(
    names(results), output_directory, repository_root
  )
  for (index in seq_along(results)) {
    write_governed_gps_reference_window(
      results[[index]], destinations[[index]]$output_directory, repository_root
    )
  }
  invisible(output_directory)
}
