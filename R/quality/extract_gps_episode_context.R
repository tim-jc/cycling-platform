GPS_STAGE2C_EXTRACTION_VERSION <- "gps-qualification-stage2c-v1-experimental"
GPS_STAGE2C_CONTEXT_SCALES <- c(3L, 5L, 15L, 30L)

gps_stage2c_case_filenames <- function(request_type) {
  files <- c(
    governed_gps_reference_window_filenames(),
    "descriptive_observations.csv", "descriptive_segments.csv",
    "multi_scale_observation_context.csv",
    "observation_review_worksheet.csv", "segment_review_worksheet.csv",
    "episode_boundary_review_worksheet.csv",
    "contextual_findings_review_worksheet.csv"
  )
  if (identical(request_type, "COMPLETE_EPISODE")) {
    files <- c(files, "episode_track.png", "episode_measurements.png")
  }
  files
}

gps_stage2c_root_filenames <- function() {
  c(
    "extraction_manifest.csv", "file_manifest.csv",
    "consolidated_observation_review.csv", "consolidated_segment_review.csv"
  )
}

read_gps_stage2c_request_registry <- function(path) {
  utils::read.csv(
    normalizePath(path, mustWork = TRUE),
    colClasses = c(activity_id = "character"),
    stringsAsFactors = FALSE,
    na.strings = c("", "NA")
  )
}

validate_gps_stage2c_request_registry <- function(requests, activity_manifest) {
  required <- c(
    "request_id", "request_type", "case_key", "episode_id", "activity_id",
    "window_from_sample_index", "window_to_sample_index",
    "focus_from_sample_index", "focus_to_sample_index",
    "focus_segment_from_sample_index", "focus_segment_to_sample_index",
    "original_focus_observation_indices", "original_focus_segment_pairs",
    "context_before_observations", "context_after_observations",
    "selection_rationale", "calibration_partition", "overlap_group",
    "source_evidence_path", "source_evidence_sha256", "repository_revision",
    "extraction_version"
  )
  missing <- setdiff(required, names(requests))
  if (length(missing)) {
    stop("Stage 2C request registry is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  if (!nrow(requests)) stop("Stage 2C request registry is empty.", call. = FALSE)
  requests <- requests[, required, drop = FALSE]
  text_columns <- setdiff(required, c(
    "window_from_sample_index", "window_to_sample_index",
    "focus_from_sample_index", "focus_to_sample_index",
    "focus_segment_from_sample_index", "focus_segment_to_sample_index",
    "context_before_observations", "context_after_observations"
  ))
  for (column in text_columns) requests[[column]] <- trimws(as.character(requests[[column]]))
  if (any(!grepl("^[A-Za-z0-9][A-Za-z0-9_-]*$", requests$request_id)) ||
      anyDuplicated(requests$request_id)) {
    stop("Stage 2C request_id values must be unique safe identifiers.", call. = FALSE)
  }
  if (any(!requests$request_type %in% c("STANDARD_CONTEXT", "COMPLETE_EPISODE"))) {
    stop("Stage 2C request_type is unsupported.", call. = FALSE)
  }
  if (any(!grepl("^[0-9]+(;[0-9]+)*$", requests$original_focus_observation_indices)) ||
      any(!grepl("^[0-9]+-[0-9]+(;[0-9]+-[0-9]+)*$", requests$original_focus_segment_pairs))) {
    stop("Stage 2C original focus references are malformed.", call. = FALSE)
  }
  requests$activity_id <- vapply(
    requests$activity_id, validate_gps_investigation_activity_id, character(1)
  )
  if (any(requests$calibration_partition != "CALIBRATION") ||
      any(geographic_activity_partition(requests$activity_id) != "CALIBRATION")) {
    stop("Stage 2C registry contains non-CALIBRATION evidence.", call. = FALSE)
  }
  if (any(!nzchar(requests$selection_rationale)) || any(!nzchar(requests$overlap_group)) ||
      any(!nzchar(requests$source_evidence_path)) ||
      any(!grepl("^[0-9a-f]{64}$", requests$source_evidence_sha256)) ||
      any(!nzchar(requests$repository_revision)) ||
      any(requests$extraction_version != GPS_STAGE2C_EXTRACTION_VERSION)) {
    stop("Stage 2C registry provenance is incomplete or invalid.", call. = FALSE)
  }
  if (any(!file.exists(requests$source_evidence_path))) {
    stop("Stage 2C source evidence path is missing.", call. = FALSE)
  }
  actual_hashes <- vapply(requests$source_evidence_path, gps_sha256_file, character(1))
  if (any(actual_hashes != requests$source_evidence_sha256)) {
    stop("Stage 2C source evidence hash does not match.", call. = FALSE)
  }
  manifest <- activity_manifest
  if (any(!c("activity_id", "gps_sample_count") %in% names(manifest))) {
    stop("Activity manifest lacks activity_id or gps_sample_count.", call. = FALSE)
  }
  manifest$activity_id <- as.character(manifest$activity_id)
  if (anyDuplicated(manifest$activity_id)) stop("Activity manifest has duplicate IDs.", call. = FALSE)
  position <- match(requests$activity_id, manifest$activity_id)
  if (anyNA(position)) stop("Stage 2C activity is absent from the calibration manifest.", call. = FALSE)
  sample_count <- suppressWarnings(as.integer(manifest$gps_sample_count[position]))
  governed <- validate_governed_gps_reference_window_requests(data.frame(
    activity_id = requests$activity_id,
    case_key = requests$request_id,
    window_from_sample_index = requests$window_from_sample_index,
    window_to_sample_index = requests$window_to_sample_index,
    focus_from_sample_index = requests$focus_from_sample_index,
    focus_to_sample_index = requests$focus_to_sample_index,
    focus_segment_from_sample_index = requests$focus_segment_from_sample_index,
    focus_segment_to_sample_index = requests$focus_segment_to_sample_index,
    evidence_note = requests$selection_rationale,
    stringsAsFactors = FALSE
  ))
  index_columns <- setdiff(names(governed), c("activity_id", "case_key", "evidence_note"))
  requests[index_columns] <- governed[index_columns]
  if (any(requests$window_to_sample_index > sample_count)) {
    stop("Stage 2C request bounds exceed the recorded sample count.", call. = FALSE)
  }
  for (index in seq_len(nrow(requests))) {
    focus_observations <- as.integer(strsplit(
      requests$original_focus_observation_indices[[index]], ";", fixed = TRUE
    )[[1L]])
    segment_text <- strsplit(
      requests$original_focus_segment_pairs[[index]], ";", fixed = TRUE
    )[[1L]]
    focus_segments <- do.call(rbind, lapply(segment_text, function(value) {
      as.integer(strsplit(value, "-", fixed = TRUE)[[1L]])
    }))
    if (any(focus_observations < requests$window_from_sample_index[[index]] |
            focus_observations > requests$window_to_sample_index[[index]]) ||
        any(focus_segments[, 2L] != focus_segments[, 1L] + 1L) ||
        any(focus_segments < requests$window_from_sample_index[[index]]) ||
        any(focus_segments > requests$window_to_sample_index[[index]])) {
      stop("Stage 2C original focus references lie outside the request or are not consecutive.", call. = FALSE)
    }
  }
  standard <- requests$request_type == "STANDARD_CONTEXT"
  before <- suppressWarnings(as.integer(requests$context_before_observations))
  after <- suppressWarnings(as.integer(requests$context_after_observations))
  if (any(standard & (is.na(before) | is.na(after) | before != 30L | after != 30L))) {
    stop("Standard Stage 2C windows require exactly 30 observations on each side.", call. = FALSE)
  }
  expected_from <- pmax(1L, requests$focus_from_sample_index - 30L)
  expected_to <- pmin(sample_count, requests$focus_to_sample_index + 30L)
  if (any(standard & (
      requests$window_from_sample_index != expected_from |
      requests$window_to_sample_index != expected_to))) {
    stop("Standard Stage 2C window bounds do not match the governed 30-observation rule.", call. = FALSE)
  }
  requests$recorded_sample_count <- sample_count
  requests$requested_start_is_actual_boundary <- requests$window_from_sample_index == 1L
  requests$requested_end_is_actual_boundary <- requests$window_to_sample_index == sample_count
  requests
}

gps_strict_cumulative <- function(values) {
  result <- rep(NA_real_, length(values))
  if (!length(values)) return(result)
  total <- 0
  complete <- TRUE
  for (index in seq_along(values)) {
    if (!is.finite(values[[index]])) complete <- FALSE
    if (complete) {
      total <- total + values[[index]]
      result[[index]] <- total
    }
  }
  result
}

gps_stage2c_descriptive_tables <- function(governed) {
  observations <- governed$reference_window_observations
  segments <- governed$reference_window_segments
  bearings <- gps_context_segment_bearings(segments)
  bearing_change <- c(NA_real_, geographic_absolute_bearing_change_degrees(
    bearings[-length(bearings)], bearings[-1L]
  ))
  segment_descriptive <- data.frame(
    segments,
    initial_bearing_degrees = bearings,
    bearing_change_degrees = bearing_change,
    repeated_coordinate = is.finite(segments$geographic_displacement_metres) &
      segments$geographic_displacement_metres == 0,
    repeated_timestamp = is.finite(segments$elapsed_time_difference_seconds) &
      segments$elapsed_time_difference_seconds == 0,
    cumulative_geographic_displacement_metres = gps_strict_cumulative(
      segments$geographic_displacement_metres
    ),
    cumulative_device_distance_change_metres = gps_strict_cumulative(
      segments$device_distance_difference_metres
    ),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  first_time <- observations$time_seconds[[1L]]
  elapsed <- if (is.finite(first_time)) observations$time_seconds - first_time else {
    rep(NA_real_, nrow(observations))
  }
  observation_descriptive <- data.frame(
    observations,
    elapsed_from_window_start_seconds = elapsed,
    preceding_segment_elapsed_seconds = c(NA_real_, segments$elapsed_time_difference_seconds),
    preceding_geographic_displacement_metres = c(NA_real_, segments$geographic_displacement_metres),
    preceding_device_distance_change_metres = c(NA_real_, segments$device_distance_difference_metres),
    preceding_implied_speed_metres_per_second = c(NA_real_, segments$implied_geographic_speed_metres_per_second),
    preceding_relative_distance_discrepancy = c(NA_real_, segments$gps_device_distance_relative_discrepancy),
    cumulative_geographic_displacement_metres = c(
      0, segment_descriptive$cumulative_geographic_displacement_metres
    ),
    cumulative_device_distance_change_metres = c(
      0, segment_descriptive$cumulative_device_distance_change_metres
    ),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  list(observations = observation_descriptive, segments = segment_descriptive)
}

gps_stage2c_multiscale_context <- function(observations, segments, case_key) {
  stationary <- gps_exact_stationary_run_evidence(observations)
  rows <- list()
  counter <- 0L
  for (scale in GPS_STAGE2C_CONTEXT_SCALES) {
    for (sample_index in observations$sample_index) {
      counter <- counter + 1L
      rows[[counter]] <- gps_context_observation_row(
        observations, segments, stationary, sample_index, case_key, scale
      )
    }
  }
  bind_gps_context_rows(rows)
}

gps_stage2c_evidence_key <- function(frame, entity_type) {
  if (entity_type == "OBSERVATION") {
    paste(entity_type, frame$activity_id, frame$sample_index, sep = "\r")
  } else {
    paste(entity_type, frame$activity_id, frame$from_sample_index,
          frame$to_sample_index, sep = "\r")
  }
}

gps_stage2c_review_worksheet <- function(frame, entity_type, request, prior_decisions) {
  count <- nrow(frame)
  result <- data.frame(
    entity_type = rep(entity_type, count),
    activity_id = as.character(frame$activity_id),
    sample_index = if (entity_type == "OBSERVATION") frame$sample_index else NA_integer_,
    from_sample_index = if (entity_type == "SEGMENT") frame$from_sample_index else NA_integer_,
    to_sample_index = if (entity_type == "SEGMENT") frame$to_sample_index else NA_integer_,
    request_id = request$request_id[[1L]],
    episode_id = request$episode_id[[1L]],
    calibration_partition = "CALIBRATION",
    manual_label = "UNREVIEWED",
    prior_research_label = NA_character_,
    prior_decision_status = NA_character_,
    prior_conditional_acceptance = NA,
    prior_review_provenance = NA_character_,
    reviewer = NA_character_, reviewed_at_utc = NA_character_,
    reviewer_rationale = NA_character_,
    stringsAsFactors = FALSE
  )
  if (!is.null(prior_decisions) && nrow(prior_decisions)) {
    current_key <- gps_stage2c_evidence_key(result, entity_type)
    prior <- prior_decisions[prior_decisions$entity_type == entity_type, , drop = FALSE]
    prior_key <- gps_stage2c_evidence_key(prior, entity_type)
    match_position <- match(current_key, prior_key)
    matched <- !is.na(match_position)
    result$prior_research_label[matched] <- prior$confirmed_research_label[match_position[matched]]
    result$prior_decision_status[matched] <- prior$decision_status[match_position[matched]]
    result$prior_conditional_acceptance[matched] <-
      prior$conditional_acceptance[match_position[matched]] == "TRUE"
    result$prior_review_provenance[matched] <- prior$review_provenance[match_position[matched]]
  }
  result
}

build_gps_stage2c_result <- function(source, request, prior_decisions = NULL,
                                     contextual_findings = NULL) {
  request <- request[1L, , drop = FALSE]
  governed <- build_governed_gps_reference_window(
    source$raw_streams, source$silver_samples,
    request$window_from_sample_index, request$window_to_sample_index,
    request$focus_from_sample_index, request$focus_to_sample_index,
    request$focus_segment_from_sample_index,
    request$focus_segment_to_sample_index,
    request$request_id, request$selection_rationale
  )
  descriptive <- gps_stage2c_descriptive_tables(governed)
  focus_observations <- as.integer(strsplit(
    request$original_focus_observation_indices[[1L]], ";", fixed = TRUE
  )[[1L]])
  focus_segment_text <- strsplit(
    request$original_focus_segment_pairs[[1L]], ";", fixed = TRUE
  )[[1L]]
  focus_segments <- do.call(rbind, lapply(focus_segment_text, function(value) {
    as.integer(strsplit(value, "-", fixed = TRUE)[[1L]])
  }))
  descriptive$observations$is_original_focus_observation <-
    descriptive$observations$sample_index %in% focus_observations
  descriptive$segments$is_original_focus_segment <- vapply(
    seq_len(nrow(descriptive$segments)), function(index) {
      any(
        focus_segments[, 1L] == descriptive$segments$from_sample_index[[index]] &
          focus_segments[, 2L] == descriptive$segments$to_sample_index[[index]]
      )
    }, logical(1)
  )
  window_observations <- descriptive$observations[, c(
    "activity_id", "sample_index", "latitude", "longitude", "time_seconds",
    "distance_metres"
  )]
  window_segments <- profile_activity_track_integrity(
    window_observations, include_segments = TRUE
  )$segments
  multiscale <- gps_stage2c_multiscale_context(
    window_observations, window_segments, request$request_id[[1L]]
  )
  observations_review <- gps_stage2c_review_worksheet(
    descriptive$observations, "OBSERVATION", request, prior_decisions
  )
  segments_review <- gps_stage2c_review_worksheet(
    descriptive$segments, "SEGMENT", request, prior_decisions
  )
  boundary_review <- data.frame(
    request_id = request$request_id[[1L]], episode_id = request$episode_id[[1L]],
    activity_id = request$activity_id[[1L]],
    boundary_role = c("REQUESTED_EPISODE_START", "REQUESTED_EPISODE_END"),
    sample_index = c(request$window_from_sample_index, request$window_to_sample_index),
    true_activity_boundary = c(
      request$requested_start_is_actual_boundary,
      request$requested_end_is_actual_boundary
    ),
    prior_contextual_finding = NA_character_,
    prior_review_provenance = NA_character_,
    manual_assessment = "UNREVIEWED", reviewer = NA_character_,
    reviewed_at_utc = NA_character_, reviewer_rationale = NA_character_,
    stringsAsFactors = FALSE
  )
  findings <- data.frame()
  if (!is.null(contextual_findings) && nrow(contextual_findings)) {
    findings <- contextual_findings[
      as.character(contextual_findings$activity_id) == request$activity_id[[1L]],
      , drop = FALSE
    ]
    findings$request_id <- rep(request$request_id[[1L]], nrow(findings))
    findings$manual_assessment <- rep("UNREVIEWED", nrow(findings))
    findings$reviewer <- rep(NA_character_, nrow(findings))
    findings$reviewed_at_utc <- rep(NA_character_, nrow(findings))
    findings$reviewer_rationale <- rep(NA_character_, nrow(findings))
    if (nrow(findings)) {
      boundary_rows <- list()
      for (finding_index in seq_len(nrow(findings))) {
        candidate_indexes <- c(
          suppressWarnings(as.integer(findings$from_sample_index[[finding_index]])),
          suppressWarnings(as.integer(findings$to_sample_index[[finding_index]]))
        )
        candidate_roles <- c("OWNER_CONTEXT_START", "OWNER_CONTEXT_END")
        for (boundary_index in seq_along(candidate_indexes)) {
          candidate <- candidate_indexes[[boundary_index]]
          if (is.na(candidate) ||
              candidate < request$window_from_sample_index[[1L]] ||
              candidate > request$window_to_sample_index[[1L]]) next
          boundary_rows[[length(boundary_rows) + 1L]] <- data.frame(
            request_id = request$request_id[[1L]],
            episode_id = request$episode_id[[1L]],
            activity_id = request$activity_id[[1L]],
            boundary_role = candidate_roles[[boundary_index]],
            sample_index = candidate,
            true_activity_boundary = candidate == 1L ||
              candidate == request$recorded_sample_count[[1L]],
            prior_contextual_finding = as.character(findings$finding[[finding_index]]),
            prior_review_provenance = as.character(
              findings$review_provenance[[finding_index]]
            ),
            manual_assessment = "UNREVIEWED", reviewer = NA_character_,
            reviewed_at_utc = NA_character_, reviewer_rationale = NA_character_,
            stringsAsFactors = FALSE
          )
        }
      }
      if (length(boundary_rows)) {
        boundary_review <- rbind(boundary_review, do.call(rbind, boundary_rows))
        boundary_review <- unique(boundary_review)
      }
    }
  }
  list(
    governed = governed,
    descriptive_observations = descriptive$observations,
    descriptive_segments = descriptive$segments,
    multi_scale_observation_context = multiscale,
    observation_review_worksheet = observations_review,
    segment_review_worksheet = segments_review,
    episode_boundary_review_worksheet = boundary_review,
    contextual_findings_review_worksheet = findings
  )
}

extract_gps_stage2c <- function(connection, requests, prior_decisions = NULL,
                                contextual_findings = NULL,
                                get_evidence = fetch_gps_raw_silver_evidence) {
  evidence_by_activity <- list()
  results <- vector("list", nrow(requests)); names(results) <- requests$request_id
  for (index in seq_len(nrow(requests))) {
    activity_id <- requests$activity_id[[index]]
    if (is.null(evidence_by_activity[[activity_id]])) {
      evidence_by_activity[[activity_id]] <- get_evidence(connection, activity_id)
    }
    results[[index]] <- build_gps_stage2c_result(
      evidence_by_activity[[activity_id]], requests[index, , drop = FALSE],
      prior_decisions, contextual_findings
    )
  }
  results
}

collapse_gps_stage2c_review <- function(results, name) {
  rows <- lapply(results, `[[`, name)
  rows <- rows[vapply(rows, nrow, integer(1)) > 0L]
  if (!length(rows)) return(data.frame())
  combined <- do.call(rbind, rows); rownames(combined) <- NULL
  entity_type <- combined$entity_type[[1L]]
  keys <- gps_stage2c_evidence_key(combined, entity_type)
  groups <- split(seq_len(nrow(combined)), keys)
  collapsed <- lapply(groups, function(indexes) {
    group <- combined[indexes, , drop = FALSE]
    compare <- setdiff(names(group), c("request_id", "episode_id"))
    if (any(vapply(compare, function(column) {
      length(unique(as.character(group[[column]]))) > 1L
    }, logical(1)))) {
      stop("Overlapping Stage 2C review evidence is contradictory.", call. = FALSE)
    }
    row <- group[1L, , drop = FALSE]
    row$request_id <- paste(sort(unique(group$request_id)), collapse = ";")
    row$episode_id <- paste(sort(unique(group$episode_id)), collapse = ";")
    row
  })
  result <- do.call(rbind, collapsed); rownames(result) <- NULL
  result
}

with_gps_stage2c_read_connection <- function(code,
                                             connect = get_connection,
                                             is_valid = DBI::dbIsValid,
                                             disconnect = DBI::dbDisconnect) {
  if (!is.function(code)) stop("Stage 2C connection work must be a function.", call. = FALSE)
  connection <- connect("cycling_platform_admin")
  on.exit({
    tryCatch(
      {
        if (is_valid(connection)) disconnect(connection)
      },
      error = function(error) {
        warning(
          "Stage 2C connection cleanup failed: ", conditionMessage(error),
          call. = FALSE
        )
      }
    )
  }, add = TRUE)
  code(connection)
}

with_gps_stage2c_png <- function(path, width, height, resolution, draw) {
  if (!is.function(draw)) stop("Stage 2C plot drawing must be a function.", call. = FALSE)
  grDevices::png(path, width = width, height = height, res = resolution)
  device <- grDevices::dev.cur()
  on.exit({
    devices <- grDevices::dev.list()
    if (!is.null(devices) && device %in% devices) grDevices::dev.off(device)
  }, add = TRUE)
  draw()
  invisible(path)
}

render_gps_stage2c_episode_plots <- function(result, track_path, measurements_path) {
  observations <- result$descriptive_observations
  segments <- result$descriptive_segments
  review <- result$observation_review_worksheet
  colours <- rep("grey45", nrow(observations))
  prior <- match(observations$sample_index, review$sample_index)
  prior_labels <- review$prior_research_label[prior]
  colours[prior_labels == "ACCEPTED" & !is.na(prior_labels)] <- "forestgreen"
  colours[prior_labels == "UNCERTAIN" & !is.na(prior_labels)] <- "darkorange"
  colours[prior_labels == "REJECTED" & !is.na(prior_labels)] <- "firebrick"
  with_gps_stage2c_png(track_path, 1400, 1000, 140, function() {
    graphics::plot(
      observations$longitude, observations$latitude, type = "l",
      xlab = "Longitude", ylab = "Latitude", asp = 1,
      main = paste("GPS episode", unique(observations$case_key))
    )
    graphics::points(observations$longitude, observations$latitude, pch = 16, col = colours)
    focus <- observations$is_original_focus_observation
    graphics::points(observations$longitude[focus], observations$latitude[focus],
                     col = "blue", pch = 8, cex = 1.5)
    graphics::text(observations$longitude, observations$latitude,
                   labels = observations$sample_index, pos = 3, cex = 0.55)
    graphics::legend(
      "topright",
      legend = c("Unreviewed", "Prior accepted", "Prior uncertain", "Prior rejected", "Original focus"),
      col = c("grey45", "forestgreen", "darkorange", "firebrick", "blue"),
      pch = c(16, 16, 16, 16, 8), cex = 0.8
    )
  })

  with_gps_stage2c_png(measurements_path, 1600, 1400, 140, function() {
    graphics::par(mfrow = c(3, 2), mar = c(4, 4, 2, 1))
    x <- segments$to_sample_index
    plot_one <- function(value, label) {
      graphics::plot(x, value, type = "o", pch = 16, xlab = "To sample index", ylab = label)
      focus_indexes <- observations$sample_index[observations$is_original_focus_observation]
      graphics::abline(v = focus_indexes, col = "blue", lty = 3)
    }
    plot_one(segments$elapsed_time_difference_seconds, "Elapsed seconds")
    plot_one(segments$geographic_displacement_metres, "GPS displacement (m)")
    plot_one(segments$device_distance_difference_metres, "Device distance change (m)")
    plot_one(segments$implied_geographic_speed_metres_per_second, "Implied speed (m/s)")
    plot_one(segments$gps_device_distance_relative_discrepancy, "Relative discrepancy")
    plot_one(segments$bearing_change_degrees, "Bearing change (degrees)")
  })
  invisible(c(track_path, measurements_path))
}

validate_gps_stage2c_destinations <- function(requests, output_directory,
                                              repository_root = getwd()) {
  root <- validate_track_evidence_output_destination(
    output_directory, gps_stage2c_root_filenames(), repository_root
  )
  cases <- lapply(seq_len(nrow(requests)), function(index) {
    validate_track_evidence_output_destination(
      file.path(root$output_directory, requests$request_id[[index]]),
      gps_stage2c_case_filenames(requests$request_type[[index]]),
      repository_root
    )
  })
  list(root = root, cases = cases)
}

write_gps_stage2c_results <- function(results, requests, output_directory,
                                      input_paths, repository_commit_sha,
                                      repository_root = getwd()) {
  destinations <- validate_gps_stage2c_destinations(
    requests, output_directory, repository_root
  )
  dir.create(destinations$root$output_directory, recursive = TRUE, showWarnings = FALSE)
  written <- character()
  manifest_rows <- list()
  for (index in seq_along(results)) {
    result <- results[[index]]
    request <- requests[index, , drop = FALSE]
    case_directory <- destinations$cases[[index]]$output_directory
    governed_paths <- write_governed_gps_reference_window(
      result$governed, case_directory, repository_root
    )
    tables <- c(
      descriptive_observations = "descriptive_observations.csv",
      descriptive_segments = "descriptive_segments.csv",
      multi_scale_observation_context = "multi_scale_observation_context.csv",
      observation_review_worksheet = "observation_review_worksheet.csv",
      segment_review_worksheet = "segment_review_worksheet.csv",
      episode_boundary_review_worksheet = "episode_boundary_review_worksheet.csv",
      contextual_findings_review_worksheet = "contextual_findings_review_worksheet.csv"
    )
    table_paths <- file.path(case_directory, unname(tables))
    names(table_paths) <- names(tables)
    for (name in names(tables)) {
      utils::write.csv(result[[name]], table_paths[[name]], row.names = FALSE, na = "")
    }
    plot_paths <- character()
    if (request$request_type[[1L]] == "COMPLETE_EPISODE") {
      plot_paths <- file.path(
        case_directory, c("episode_track.png", "episode_measurements.png")
      )
      render_gps_stage2c_episode_plots(result, plot_paths[[1L]], plot_paths[[2L]])
    }
    written <- c(written, unname(governed_paths), table_paths, plot_paths)
    manifest_rows[[index]] <- data.frame(
      request_id = request$request_id,
      request_type = request$request_type,
      episode_id = request$episode_id,
      activity_id = request$activity_id,
      calibration_partition = request$calibration_partition,
      requested_from_sample_index = request$window_from_sample_index,
      requested_to_sample_index = request$window_to_sample_index,
      returned_from_sample_index = min(result$descriptive_observations$sample_index),
      returned_to_sample_index = max(result$descriptive_observations$sample_index),
      observation_count = nrow(result$descriptive_observations),
      segment_count = nrow(result$descriptive_segments),
      raw_silver_mismatch_count = sum(
        result$governed$raw_silver_positional_comparison$any_mismatch
      ),
      automated_qualification_decision_count = 0L,
      extraction_version = GPS_STAGE2C_EXTRACTION_VERSION,
      repository_commit_sha = repository_commit_sha,
      stringsAsFactors = FALSE
    )
  }
  observations <- collapse_gps_stage2c_review(
    results, "observation_review_worksheet"
  )
  segments <- collapse_gps_stage2c_review(results, "segment_review_worksheet")
  root_paths <- destinations$root$paths
  utils::write.csv(do.call(rbind, manifest_rows), root_paths[[1L]], row.names = FALSE, na = "")
  utils::write.csv(observations, root_paths[[3L]], row.names = FALSE, na = "")
  utils::write.csv(segments, root_paths[[4L]], row.names = FALSE, na = "")
  written <- c(written, root_paths[c(1L, 3L, 4L)])
  inputs <- normalizePath(input_paths, winslash = "/", mustWork = TRUE)
  files <- data.frame(
    file_role = c(rep("INPUT", length(inputs)), rep("OUTPUT", length(written))),
    path = c(inputs, normalizePath(written, winslash = "/", mustWork = TRUE)),
    sha256 = vapply(c(inputs, written), gps_sha256_file, character(1)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(files, root_paths[[2L]], row.names = FALSE, na = "")
  invisible(list(
    extraction_manifest = do.call(rbind, manifest_rows),
    file_manifest = files,
    consolidated_observations = observations,
    consolidated_segments = segments
  ))
}
