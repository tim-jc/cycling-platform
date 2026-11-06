#' Extract ordered Raw stream values needed for GPS timestamp evidence.
#'
#' @param raw_streams Rows for the time, latlng, and distance Raw streams.
#' @return A list containing stream metadata and one positionally aligned row per
#'   Raw array position.
expand_raw_gps_evidence_streams <- function(raw_streams) {
  required <- c("activity_id", "stream_type", "original_size", "stream_payload")
  missing_columns <- setdiff(required, names(raw_streams))
  if (length(missing_columns) > 0L) {
    stop("Raw stream fixture is missing: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  }

  expected_types <- c("time", "latlng", "distance")
  if (!setequal(raw_streams$stream_type, expected_types) || anyDuplicated(raw_streams$stream_type)) {
    stop("Expected exactly one Raw time, latlng, and distance stream.", call. = FALSE)
  }
  if (length(unique(raw_streams$activity_id)) != 1L) {
    stop("Raw streams must belong to exactly one activity.", call. = FALSE)
  }

  payloads <- stats::setNames(
    lapply(
      raw_streams$stream_payload,
      function(payload) {
        if (is.na(payload) || !nzchar(payload)) return(NULL)
        jsonlite::fromJSON(payload, simplifyVector = FALSE)
      }
    ),
    raw_streams$stream_type
  )
  payload_lengths <- vapply(payloads, length, integer(1))
  declared_sizes <- stats::setNames(as.integer(raw_streams$original_size), raw_streams$stream_type)
  sample_count <- max(c(payload_lengths, declared_sizes), na.rm = TRUE)
  indexes <- seq_len(sample_count)

  scalar_at <- function(type, index) {
    value <- payloads[[type]][index]
    if (length(value) == 0L || is.null(value[[1L]])) return(NA_real_)
    as.numeric(value[[1L]])
  }
  coordinate_at <- function(index, position) {
    value <- payloads$latlng[index]
    if (length(value) == 0L || is.null(value[[1L]]) || length(value[[1L]]) < position) return(NA_real_)
    coordinate <- value[[1L]][position]
    if (length(coordinate) == 0L || is.null(coordinate[[1L]])) return(NA_real_)
    as.numeric(coordinate[[1L]])
  }

  list(
    metadata = data.frame(
      activity_id = rep(raw_streams$activity_id[[1L]], length(expected_types)),
      stream_type = expected_types,
      original_size = unname(declared_sizes[expected_types]),
      payload_length = unname(payload_lengths[expected_types]),
      stringsAsFactors = FALSE
    ),
    samples = data.frame(
      activity_id = rep(raw_streams$activity_id[[1L]], sample_count),
      sample_index = indexes,
      raw_time_seconds = vapply(indexes, \(i) scalar_at("time", i), numeric(1)),
      raw_latitude = vapply(indexes, \(i) coordinate_at(i, 1L), numeric(1)),
      raw_longitude = vapply(indexes, \(i) coordinate_at(i, 2L), numeric(1)),
      raw_distance_metres = vapply(indexes, \(i) scalar_at("distance", i), numeric(1))
    )
  )
}

gps_evidence_values_match <- function(raw, silver) {
  (is.na(raw) & is.na(silver)) | (!is.na(raw) & !is.na(silver) & raw == silver)
}

duplicate_timestamp_evidence_filenames <- function() {
  c(
    extraction_summary = "extraction_summary.csv",
    raw_stream_metadata = "raw_stream_metadata.csv",
    positional_comparison = "raw_silver_positional_comparison.csv",
    non_increasing_intervals = "non_increasing_timestamp_intervals.csv",
    equal_timestamp_runs = "equal_timestamp_runs.csv",
    reference_window = "reference_window.csv"
  )
}

#' Compare Raw arrays and Silver observations and identify timestamp anomalies.
#'
#' @param raw_streams Raw stream rows.
#' @param silver_samples Ordered Silver observations.
#' @param context_observations Observations required on each side of a review run.
#' @return Evidence tables ready for CSV output.
build_duplicate_timestamp_evidence <- function(raw_streams, silver_samples, context_observations = 5L) {
  context_observations <- as.integer(context_observations)
  if (is.na(context_observations) || context_observations < 0L) {
    stop("context_observations must be a non-negative integer.", call. = FALSE)
  }
  required_silver <- c(
    "activity_id", "sample_index", "time_seconds", "latitude", "longitude", "distance_metres"
  )
  missing_columns <- setdiff(required_silver, names(silver_samples))
  if (length(missing_columns) > 0L) {
    stop("Silver samples are missing: ", paste(missing_columns, collapse = ", "), call. = FALSE)
  }
  if (anyDuplicated(silver_samples$sample_index)) {
    stop("Silver sample_index values must be unique.", call. = FALSE)
  }

  expanded <- expand_raw_gps_evidence_streams(raw_streams)
  silver_samples <- silver_samples[order(silver_samples$sample_index), required_silver, drop = FALSE]
  names(silver_samples)[names(silver_samples) != "activity_id" & names(silver_samples) != "sample_index"] <-
    paste0("silver_", names(silver_samples)[names(silver_samples) != "activity_id" & names(silver_samples) != "sample_index"])
  names(silver_samples)[names(silver_samples) == "silver_time_seconds"] <- "silver_time_seconds"

  positional <- merge(
    expanded$samples, silver_samples,
    by = c("activity_id", "sample_index"), all = TRUE, sort = FALSE
  )
  positional <- positional[order(positional$sample_index), , drop = FALSE]
  rownames(positional) <- NULL
  comparisons <- list(
    time = c("raw_time_seconds", "silver_time_seconds"),
    latitude = c("raw_latitude", "silver_latitude"),
    longitude = c("raw_longitude", "silver_longitude"),
    distance = c("raw_distance_metres", "silver_distance_metres")
  )
  for (field in names(comparisons)) {
    columns <- comparisons[[field]]
    positional[[paste0(field, "_matches")]] <- gps_evidence_values_match(
      positional[[columns[[1L]]]], positional[[columns[[2L]]]]
    )
  }
  positional$any_mismatch <- !Reduce(`&`, positional[paste0(names(comparisons), "_matches")])

  raw_time_difference <- diff(positional$raw_time_seconds)
  silver_time_difference <- diff(positional$silver_time_seconds)
  interval_indexes <- which(
    (!is.na(raw_time_difference) & raw_time_difference <= 0) |
      (!is.na(silver_time_difference) & silver_time_difference <= 0)
  )
  classify_interval <- function(difference) {
    ifelse(is.na(difference), NA_character_, ifelse(difference == 0, "EQUAL", ifelse(difference < 0, "DECREASING", "INCREASING")))
  }
  intervals <- if (length(interval_indexes) == 0L) {
    data.frame(
      from_sample_index = integer(), to_sample_index = integer(),
      raw_from_time_seconds = numeric(), raw_to_time_seconds = numeric(), raw_interval_type = character(),
      silver_from_time_seconds = numeric(), silver_to_time_seconds = numeric(), silver_interval_type = character(),
      coordinates_identical = logical(), distance_change_metres = numeric()
    )
  } else {
    data.frame(
      from_sample_index = positional$sample_index[interval_indexes],
      to_sample_index = positional$sample_index[interval_indexes + 1L],
      raw_from_time_seconds = positional$raw_time_seconds[interval_indexes],
      raw_to_time_seconds = positional$raw_time_seconds[interval_indexes + 1L],
      raw_interval_type = classify_interval(raw_time_difference[interval_indexes]),
      silver_from_time_seconds = positional$silver_time_seconds[interval_indexes],
      silver_to_time_seconds = positional$silver_time_seconds[interval_indexes + 1L],
      silver_interval_type = classify_interval(silver_time_difference[interval_indexes]),
      coordinates_identical = gps_evidence_values_match(
        positional$raw_latitude[interval_indexes], positional$raw_latitude[interval_indexes + 1L]
      ) & gps_evidence_values_match(
        positional$raw_longitude[interval_indexes], positional$raw_longitude[interval_indexes + 1L]
      ),
      distance_change_metres = positional$raw_distance_metres[interval_indexes + 1L] -
        positional$raw_distance_metres[interval_indexes]
    )
  }

  equal_pair <- c(FALSE, !is.na(positional$raw_time_seconds[-1L]) &
    !is.na(positional$raw_time_seconds[-nrow(positional)]) &
    diff(positional$raw_time_seconds) == 0)
  run_group <- cumsum(!equal_pair)
  group_sizes <- table(run_group)
  duplicate_groups <- as.integer(names(group_sizes[group_sizes >= 2L]))
  runs <- do.call(rbind, lapply(seq_along(duplicate_groups), function(run_number) {
    rows <- which(run_group == duplicate_groups[[run_number]])
    data.frame(
      run_id = run_number,
      timestamp_seconds = positional$raw_time_seconds[rows[[1L]]],
      start_sample_index = positional$sample_index[rows[[1L]]],
      end_sample_index = positional$sample_index[rows[[length(rows)]]],
      observation_count = length(rows),
      interval_count = length(rows) - 1L
    )
  }))
  if (is.null(runs)) {
    runs <- data.frame(
      run_id = integer(), timestamp_seconds = numeric(), start_sample_index = integer(),
      end_sample_index = integer(), observation_count = integer(), interval_count = integer()
    )
  }

  eligible <- runs$start_sample_index > context_observations &
    runs$end_sample_index <= nrow(positional) - context_observations
  reference_window <- positional[FALSE, , drop = FALSE]
  reference_status <- "NO_INTERNAL_RUN_WITH_REQUESTED_CONTEXT"
  selected_run_id <- NA_integer_
  if (any(eligible)) {
    candidates <- runs[eligible, , drop = FALSE]
    selected <- candidates[order(-candidates$observation_count, candidates$start_sample_index), , drop = FALSE][1L, ]
    selected_run_id <- selected$run_id
    window_indexes <- seq.int(
      selected$start_sample_index - context_observations,
      selected$end_sample_index + context_observations
    )
    reference_window <- positional[positional$sample_index %in% window_indexes, , drop = FALSE]
    reference_window$selected_duplicate_run <- reference_window$sample_index >= selected$start_sample_index &
      reference_window$sample_index <= selected$end_sample_index
    reference_status <- "READY"
  }

  summary <- data.frame(
    activity_id = expanded$metadata$activity_id[[1L]],
    raw_position_count = nrow(expanded$samples),
    silver_position_count = nrow(silver_samples),
    equal_interval_count = sum(intervals$raw_interval_type == "EQUAL", na.rm = TRUE),
    decreasing_interval_count = sum(intervals$raw_interval_type == "DECREASING", na.rm = TRUE),
    silver_equal_interval_count = sum(intervals$silver_interval_type == "EQUAL", na.rm = TRUE),
    silver_decreasing_interval_count = sum(intervals$silver_interval_type == "DECREASING", na.rm = TRUE),
    equal_timestamp_run_count = nrow(runs),
    positional_mismatch_count = sum(positional$any_mismatch),
    reference_window_status = reference_status,
    selected_run_id = selected_run_id
  )

  list(
    summary = summary,
    raw_stream_metadata = expanded$metadata,
    positional_comparison = positional,
    non_increasing_intervals = intervals,
    equal_timestamp_runs = runs,
    reference_window = reference_window
  )
}

write_duplicate_timestamp_evidence <- function(evidence, output_directory, repository_root = getwd()) {
  filenames <- duplicate_timestamp_evidence_filenames()
  names(filenames)[names(filenames) == "extraction_summary"] <- "summary"
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
