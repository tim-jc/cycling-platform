GPS_QUALIFICATION_FEATURE_CONTRACT_VERSION <- "gps-qualification-features-v1"
GPS_QUALIFICATION_CLASSES <- c("ACCEPTED", "UNCERTAIN", "REJECTED")
GPS_QUALIFICATION_RULE_STATES <- c(
  "ENABLED_DETERMINISTIC", "ENABLED_EXPERIMENTAL", "DISABLED", "UNSUPPORTED"
)

default_gps_qualification_policy <- function() {
  list(
    policy_id = "gps-qualification-prototype",
    policy_version = "0.1.0-experimental",
    policy_status = "EXPERIMENTAL",
    feature_contract_version = GPS_QUALIFICATION_FEATURE_CONTRACT_VERSION,
    rules = list(
      coordinate_missing = list(state = "ENABLED_DETERMINISTIC"),
      coordinate_out_of_range = list(state = "ENABLED_DETERMINISTIC"),
      endpoint_unusable = list(state = "ENABLED_DETERMINISTIC"),
      movement_non_positive_time = list(state = "ENABLED_DETERMINISTIC"),
      stationary_duplicate = list(state = "ENABLED_DETERMINISTIC"),
      context_insufficient = list(state = "ENABLED_DETERMINISTIC"),
      position_context_coherent = list(
        state = "DISABLED",
        parameters = list(
          maximum_displacement_metres = NA_real_,
          maximum_bearing_change_degrees = NA_real_
        )
      ),
      local_excursion = list(
        state = "DISABLED",
        parameters = list(
          minimum_excursion_metres = NA_real_,
          maximum_bridge_metres = NA_real_
        )
      ),
      gps_device_distance_disagreement = list(
        state = "DISABLED",
        parameters = list(maximum_absolute_difference_metres = NA_real_)
      )
    )
  )
}

canonicalise_gps_policy_value <- function(value) {
  if (is.list(value)) {
    if (!is.null(names(value))) value <- value[order(names(value))]
    return(lapply(value, canonicalise_gps_policy_value))
  }
  value
}

validate_gps_qualification_policy <- function(policy) {
  required <- c(
    "policy_id", "policy_version", "policy_status",
    "feature_contract_version", "rules"
  )
  missing <- setdiff(required, names(policy))
  if (length(missing)) {
    stop("GPS qualification policy is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  scalar_text <- required[required != "rules"]
  invalid_text <- vapply(policy[scalar_text], function(x) {
    length(x) != 1L || is.na(x) || !is.character(x) || !nzchar(x)
  }, logical(1))
  if (any(invalid_text)) stop("GPS qualification policy metadata must be non-empty text.", call. = FALSE)
  if (!identical(policy$policy_status, "EXPERIMENTAL")) {
    stop("Stage 1 accepts only an EXPERIMENTAL policy.", call. = FALSE)
  }
  if (!identical(policy$feature_contract_version, GPS_QUALIFICATION_FEATURE_CONTRACT_VERSION)) {
    stop("Unsupported GPS qualification feature contract.", call. = FALSE)
  }
  if (!is.list(policy$rules) || !length(policy$rules) || is.null(names(policy$rules)) ||
      any(!nzchar(names(policy$rules))) || anyDuplicated(names(policy$rules))) {
    stop("GPS qualification rules must be a uniquely named list.", call. = FALSE)
  }
  states <- vapply(policy$rules, function(rule) {
    if (!is.list(rule) || length(rule$state) != 1L) return(NA_character_)
    as.character(rule$state)
  }, character(1))
  if (any(is.na(states) | !states %in% GPS_QUALIFICATION_RULE_STATES)) {
    stop("GPS qualification policy contains an unsupported rule state.", call. = FALSE)
  }
  experimental <- states == "ENABLED_EXPERIMENTAL"
  if (any(experimental)) {
    approved <- vapply(policy$rules[experimental], function(rule) isTRUE(rule$approved), logical(1))
    if (any(!approved)) stop("Experimental rules require explicit approved = TRUE.", call. = FALSE)
  }
  invisible(TRUE)
}

fingerprint_gps_qualification_policy <- function(policy) {
  validate_gps_qualification_policy(policy)
  if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required.", call. = FALSE)
  canonical_text <- paste(
    capture.output(dput(canonicalise_gps_policy_value(policy))), collapse = "\n"
  )
  digest::digest(canonical_text, algo = "sha256", serialize = FALSE)
}

gps_qualification_input_signature <- function(frame, columns) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("Package 'digest' is required.", call. = FALSE)
  value <- frame[, columns, drop = FALSE]
  rownames(value) <- NULL
  digest::digest(value, algo = "sha256", serialize = TRUE)
}

validate_gps_qualification_samples <- function(samples) {
  required <- c(
    "activity_id", "sample_index", "latitude", "longitude",
    "time_seconds", "distance_metres"
  )
  missing <- setdiff(required, names(samples))
  if (length(missing)) stop("GPS samples are missing: ", paste(missing, collapse = ", "), call. = FALSE)
  if (!nrow(samples)) return(invisible(TRUE))
  activity_ids <- unique(as.character(samples$activity_id))
  if (length(activity_ids) != 1L || is.na(activity_ids) || !nzchar(activity_ids)) {
    stop("GPS samples must describe exactly one activity.", call. = FALSE)
  }
  numeric_columns <- setdiff(required, "activity_id")
  if (any(!vapply(samples[numeric_columns], is.numeric, logical(1)))) {
    stop("GPS sample indexes and measurements must be numeric.", call. = FALSE)
  }
  if (any(!is.finite(samples$sample_index)) || anyDuplicated(samples$sample_index) ||
      any(diff(samples$sample_index) <= 0)) {
    stop("GPS sample indexes must be finite, unique and strictly increasing in source order.", call. = FALSE)
  }
  invisible(TRUE)
}

#' Prepare GPS Qualification Features
#'
#' Reuses the governed track profiler and local-context calculations. The input
#' is never sorted or repaired. Set attribute `complete_activity` to TRUE only
#' when the first and last rows are known activity boundaries; otherwise edge
#' observations explicitly retain unknown source context.
prepare_gps_qualification_features <- function(samples) {
  validate_gps_qualification_samples(samples)
  if (!nrow(samples)) {
    observations <- data.frame(
      activity_id = character(), sample_index = integer(), latitude = numeric(),
      longitude = numeric(), time_seconds = numeric(), distance_metres = numeric(),
      coordinate_present = logical(), coordinate_valid = logical(),
      context_complete = logical(), input_signature = character(),
      stringsAsFactors = FALSE
    )
    segments <- data.frame(
      activity_id = character(), from_sample_index = integer(), to_sample_index = integer(),
      from_coordinate_valid = logical(), to_coordinate_valid = logical(),
      movement_non_positive_time = logical(), identical_coordinate = logical(),
      identical_device_distance = logical(), identical_timestamp = logical(),
      input_signature = character(), stringsAsFactors = FALSE
    )
    return(list(observations = observations, segments = segments))
  }
  profile <- profile_activity_track_integrity(samples, include_segments = TRUE)
  observations <- activity_observation_local_context(
    samples, profile$segments, samples$sample_index
  )
  complete_activity <- isTRUE(attr(samples, "complete_activity"))
  observations$coordinate_present <-
    !is.na(observations$latitude) & !is.na(observations$longitude)
  observations$coordinate_valid <- track_coordinate_is_valid(
    observations$latitude, observations$longitude
  )
  observations$source_context_before_available <- !is.na(observations$previous_sample_index)
  observations$source_context_after_available <- !is.na(observations$next_sample_index)
  observations$source_boundary_before_known <-
    observations$source_context_before_available | complete_activity
  observations$source_boundary_after_known <-
    observations$source_context_after_available | complete_activity
  observations$context_complete <-
    observations$source_context_before_available & observations$source_context_after_available
  observations$input_signature <- vapply(seq_len(nrow(observations)), function(i) {
    gps_qualification_input_signature(observations[i, , drop = FALSE], c(
      "activity_id", "sample_index", "latitude", "longitude", "time_seconds",
      "distance_metres", "previous_sample_index", "next_sample_index"
    ))
  }, character(1))

  segments <- profile$segments
  if (nrow(segments)) {
    from_position <- match(segments$from_sample_index, samples$sample_index)
    to_position <- match(segments$to_sample_index, samples$sample_index)
    segments$from_coordinate_present <-
      !is.na(segments$from_latitude) & !is.na(segments$from_longitude)
    segments$to_coordinate_present <-
      !is.na(segments$to_latitude) & !is.na(segments$to_longitude)
    segments$from_coordinate_valid <- track_coordinate_is_valid(
      segments$from_latitude, segments$from_longitude
    )
    segments$to_coordinate_valid <- track_coordinate_is_valid(
      segments$to_latitude, segments$to_longitude
    )
    segments$sample_indexes_consecutive <-
      segments$to_sample_index - segments$from_sample_index == 1L
    segments$identical_coordinate <-
      segments$from_coordinate_valid & segments$to_coordinate_valid &
      segments$from_latitude == segments$to_latitude &
      segments$from_longitude == segments$to_longitude
    segments$identical_device_distance <-
      is.finite(segments$device_distance_difference_metres) &
      segments$device_distance_difference_metres == 0
    segments$identical_timestamp <-
      is.finite(segments$elapsed_time_difference_seconds) &
      segments$elapsed_time_difference_seconds == 0
    segments$movement_non_positive_time <-
      is.finite(segments$geographic_displacement_metres) &
      segments$geographic_displacement_metres > 0 &
      is.finite(segments$elapsed_time_difference_seconds) &
      segments$elapsed_time_difference_seconds <= 0
    segments$source_context_before_available <- from_position > 1L
    segments$source_context_after_available <- to_position < nrow(samples)
    segments$source_boundary_before_known <-
      segments$source_context_before_available | complete_activity
    segments$source_boundary_after_known <-
      segments$source_context_after_available | complete_activity
    segments$input_signature <- vapply(seq_len(nrow(segments)), function(i) {
      gps_qualification_input_signature(segments[i, , drop = FALSE], c(
        "activity_id", "from_sample_index", "to_sample_index", "from_latitude",
        "from_longitude", "to_latitude", "to_longitude",
        "elapsed_time_difference_seconds", "device_distance_difference_metres"
      ))
    }, character(1))
  } else {
    segments$from_coordinate_present <- logical()
    segments$to_coordinate_present <- logical()
    segments$from_coordinate_valid <- logical()
    segments$to_coordinate_valid <- logical()
    segments$sample_indexes_consecutive <- logical()
    segments$identical_coordinate <- logical()
    segments$identical_device_distance <- logical()
    segments$identical_timestamp <- logical()
    segments$movement_non_positive_time <- logical()
    segments$source_context_before_available <- logical()
    segments$source_context_after_available <- logical()
    segments$source_boundary_before_known <- logical()
    segments$source_boundary_after_known <- logical()
    segments$input_signature <- character()
  }
  list(observations = observations, segments = segments)
}

#' Adapt Governed Reference-Window Evidence for Qualification
#'
#' This adapter consumes the already-derived observation and segment contracts;
#' it does not infer missing neighbours beyond the recorded evidence window.
prepare_gps_qualification_evidence_features <- function(observations, segments) {
  observation_required <- c(
    "activity_id", "sample_index", "latitude", "longitude", "time_seconds",
    "distance_metres", "previous_sample_index", "next_sample_index"
  )
  segment_required <- c(
    "activity_id", "from_sample_index", "to_sample_index", "from_latitude",
    "from_longitude", "to_latitude", "to_longitude",
    "elapsed_time_difference_seconds", "geographic_displacement_metres",
    "device_distance_difference_metres"
  )
  missing_observation <- setdiff(observation_required, names(observations))
  missing_segment <- setdiff(segment_required, names(segments))
  if (length(missing_observation)) {
    stop("Governed observation evidence is missing: ", paste(missing_observation, collapse = ", "), call. = FALSE)
  }
  if (length(missing_segment)) {
    stop("Governed segment evidence is missing: ", paste(missing_segment, collapse = ", "), call. = FALSE)
  }
  observations$coordinate_present <- !is.na(observations$latitude) & !is.na(observations$longitude)
  observations$coordinate_valid <- track_coordinate_is_valid(observations$latitude, observations$longitude)
  observations$source_context_before_available <- !is.na(observations$previous_sample_index)
  observations$source_context_after_available <- !is.na(observations$next_sample_index)
  observations$source_boundary_before_known <- observations$source_context_before_available
  observations$source_boundary_after_known <- observations$source_context_after_available
  observations$context_complete <- observations$source_context_before_available &
    observations$source_context_after_available
  observations$input_signature <- vapply(seq_len(nrow(observations)), function(i) {
    gps_qualification_input_signature(observations[i, , drop = FALSE], observation_required)
  }, character(1))

  segments$from_coordinate_present <- !is.na(segments$from_latitude) & !is.na(segments$from_longitude)
  segments$to_coordinate_present <- !is.na(segments$to_latitude) & !is.na(segments$to_longitude)
  segments$from_coordinate_valid <- track_coordinate_is_valid(segments$from_latitude, segments$from_longitude)
  segments$to_coordinate_valid <- track_coordinate_is_valid(segments$to_latitude, segments$to_longitude)
  segments$sample_indexes_consecutive <- segments$to_sample_index - segments$from_sample_index == 1L
  segments$identical_coordinate <- segments$from_coordinate_valid & segments$to_coordinate_valid &
    segments$from_latitude == segments$to_latitude & segments$from_longitude == segments$to_longitude
  segments$identical_device_distance <- is.finite(segments$device_distance_difference_metres) &
    segments$device_distance_difference_metres == 0
  segments$identical_timestamp <- is.finite(segments$elapsed_time_difference_seconds) &
    segments$elapsed_time_difference_seconds == 0
  segments$movement_non_positive_time <- is.finite(segments$geographic_displacement_metres) &
    segments$geographic_displacement_metres > 0 &
    is.finite(segments$elapsed_time_difference_seconds) &
    segments$elapsed_time_difference_seconds <= 0
  segments$source_context_before_available <- NA
  segments$source_context_after_available <- NA
  segments$source_boundary_before_known <- NA
  segments$source_boundary_after_known <- NA
  segments$input_signature <- vapply(seq_len(nrow(segments)), function(i) {
    gps_qualification_input_signature(segments[i, , drop = FALSE], segment_required)
  }, character(1))
  list(observations = observations, segments = segments)
}

validate_gps_qualification_run_context <- function(run_context) {
  required <- c("evaluation_run_id")
  if (!is.list(run_context) || any(!required %in% names(run_context)) ||
      length(run_context$evaluation_run_id) != 1L ||
      is.na(run_context$evaluation_run_id) || !nzchar(run_context$evaluation_run_id)) {
    stop("run_context must contain one non-empty evaluation_run_id.", call. = FALSE)
  }
  invisible(TRUE)
}

empty_gps_qualification_reasons <- function() {
  data.frame(
    entity_type = character(), activity_id = character(), sample_index = integer(),
    from_sample_index = integer(), to_sample_index = integer(), reason_code = character(),
    evidence_role = character(), rule_id = character(), stringsAsFactors = FALSE
  )
}

gps_reason_row <- function(entity_type, row, reason_code, evidence_role, rule_id) {
  data.frame(
    entity_type = entity_type,
    activity_id = as.character(row$activity_id),
    sample_index = if (entity_type == "OBSERVATION") as.integer(row$sample_index) else NA_integer_,
    from_sample_index = if (entity_type == "SEGMENT") as.integer(row$from_sample_index) else NA_integer_,
    to_sample_index = if (entity_type == "SEGMENT") as.integer(row$to_sample_index) else NA_integer_,
    reason_code = reason_code, evidence_role = evidence_role, rule_id = rule_id,
    stringsAsFactors = FALSE
  )
}

gps_decision_metadata <- function(policy, run_context) {
  validate_gps_qualification_policy(policy)
  validate_gps_qualification_run_context(run_context)
  list(
    policy_version = policy$policy_version,
    policy_fingerprint = fingerprint_gps_qualification_policy(policy),
    evaluation_run_id = as.character(run_context$evaluation_run_id)
  )
}

qualify_gps_observations <- function(observation_features, policy, run_context) {
  metadata <- gps_decision_metadata(policy, run_context)
  required <- c(
    "activity_id", "sample_index", "coordinate_present", "coordinate_valid",
    "context_complete", "input_signature"
  )
  missing <- setdiff(required, names(observation_features))
  if (length(missing)) stop("Observation features are missing: ", paste(missing, collapse = ", "), call. = FALSE)
  decisions <- vector("list", nrow(observation_features))
  reasons <- list()
  for (i in seq_len(nrow(observation_features))) {
    row <- observation_features[i, , drop = FALSE]
    classification <- "UNCERTAIN"
    primary <- "NO_ENABLED_RULE_DECISION"
    row_reasons <- list()
    if (!isTRUE(row$coordinate_present)) {
      classification <- "REJECTED"; primary <- "COORDINATE_MISSING"
      row_reasons[[1L]] <- gps_reason_row("OBSERVATION", row, primary, "DETERMINING_REJECT", "coordinate_missing")
    } else if (!isTRUE(row$coordinate_valid)) {
      classification <- "REJECTED"; primary <- "COORDINATE_OUT_OF_RANGE"
      row_reasons[[1L]] <- gps_reason_row("OBSERVATION", row, primary, "DETERMINING_REJECT", "coordinate_out_of_range")
    } else if (!isTRUE(row$context_complete)) {
      primary <- "CONTEXT_INCOMPLETE"
      row_reasons[[1L]] <- gps_reason_row("OBSERVATION", row, primary, "DETERMINING_UNCERTAIN", "context_insufficient")
    } else {
      row_reasons[[1L]] <- gps_reason_row("OBSERVATION", row, primary, "DETERMINING_UNCERTAIN", "default_uncertain")
    }
    reasons <- c(reasons, row_reasons)
    decisions[[i]] <- data.frame(
      activity_id = as.character(row$activity_id), sample_index = as.integer(row$sample_index),
      classification = classification, primary_reason_code = primary,
      evaluation_status = "SUCCESS", rule_conflict = FALSE,
      policy_version = metadata$policy_version,
      policy_fingerprint = metadata$policy_fingerprint,
      evaluation_run_id = metadata$evaluation_run_id,
      input_signature = as.character(row$input_signature), stringsAsFactors = FALSE
    )
  }
  list(
    decisions = if (length(decisions)) do.call(rbind, decisions) else data.frame(),
    reasons = if (length(reasons)) do.call(rbind, reasons) else empty_gps_qualification_reasons()
  )
}

qualify_gps_segments <- function(segment_features, policy, run_context) {
  metadata <- gps_decision_metadata(policy, run_context)
  required <- c(
    "activity_id", "from_sample_index", "to_sample_index", "from_coordinate_valid",
    "to_coordinate_valid", "movement_non_positive_time", "identical_coordinate",
    "identical_device_distance", "identical_timestamp", "input_signature"
  )
  missing <- setdiff(required, names(segment_features))
  if (length(missing)) stop("Segment features are missing: ", paste(missing, collapse = ", "), call. = FALSE)
  decisions <- vector("list", nrow(segment_features))
  reasons <- list()
  for (i in seq_len(nrow(segment_features))) {
    row <- segment_features[i, , drop = FALSE]
    classification <- "UNCERTAIN"
    primary <- "NO_ENABLED_RULE_DECISION"
    row_reasons <- list()
    if (!isTRUE(row$from_coordinate_valid) || !isTRUE(row$to_coordinate_valid)) {
      classification <- "REJECTED"; primary <- "ENDPOINT_UNUSABLE"
      row_reasons[[1L]] <- gps_reason_row("SEGMENT", row, primary, "DETERMINING_REJECT", "endpoint_unusable")
    } else if (isTRUE(row$movement_non_positive_time)) {
      classification <- "REJECTED"; primary <- "TIME_NON_INCREASING_WITH_DISPLACEMENT"
      row_reasons[[1L]] <- gps_reason_row("SEGMENT", row, primary, "DETERMINING_REJECT", "movement_non_positive_time")
    } else {
      row_reasons[[1L]] <- gps_reason_row("SEGMENT", row, primary, "DETERMINING_UNCERTAIN", "default_uncertain")
      if (isTRUE(row$identical_coordinate) && isTRUE(row$identical_device_distance) &&
          isTRUE(row$identical_timestamp)) {
        row_reasons[[2L]] <- gps_reason_row(
          "SEGMENT", row, "DUPLICATE_TIMESTAMP_STATIONARY", "SUPPORTING", "stationary_duplicate"
        )
      }
    }
    reasons <- c(reasons, row_reasons)
    decisions[[i]] <- data.frame(
      activity_id = as.character(row$activity_id),
      from_sample_index = as.integer(row$from_sample_index),
      to_sample_index = as.integer(row$to_sample_index), classification = classification,
      primary_reason_code = primary, evaluation_status = "SUCCESS", rule_conflict = FALSE,
      policy_version = metadata$policy_version,
      policy_fingerprint = metadata$policy_fingerprint,
      evaluation_run_id = metadata$evaluation_run_id,
      input_signature = as.character(row$input_signature), stringsAsFactors = FALSE
    )
  }
  list(
    decisions = if (length(decisions)) do.call(rbind, decisions) else data.frame(),
    reasons = if (length(reasons)) do.call(rbind, reasons) else empty_gps_qualification_reasons()
  )
}

qualify_activity_gps <- function(samples, policy = default_gps_qualification_policy(), run_context) {
  features <- prepare_gps_qualification_features(samples)
  observations <- qualify_gps_observations(features$observations, policy, run_context)
  segments <- qualify_gps_segments(features$segments, policy, run_context)
  list(
    observation_features = features$observations,
    segment_features = features$segments,
    observation_decisions = observations$decisions,
    segment_decisions = segments$decisions,
    reasons = rbind(observations$reasons, segments$reasons),
    coverage = data.frame(
      coverage_status = if (nrow(samples)) "GPS_STREAM_PRESENT" else "GPS_STREAM_ABSENT",
      observation_count = nrow(features$observations),
      segment_count = nrow(features$segments), stringsAsFactors = FALSE
    )
  )
}

gps_label_entity_key <- function(frame) {
  ifelse(
    frame$entity_type == "OBSERVATION",
    paste("OBSERVATION", frame$activity_id, frame$sample_index, sep = "\034"),
    paste("SEGMENT", frame$activity_id, frame$from_sample_index, frame$to_sample_index, sep = "\034")
  )
}

gps_prediction_rows <- function(observation_predictions, segment_predictions) {
  observations <- data.frame(
    entity_type = "OBSERVATION", activity_id = as.character(observation_predictions$activity_id),
    sample_index = as.integer(observation_predictions$sample_index),
    from_sample_index = NA_integer_, to_sample_index = NA_integer_,
    predicted_classification = observation_predictions$classification,
    primary_reason_code = observation_predictions$primary_reason_code,
    evaluation_status = observation_predictions$evaluation_status,
    stringsAsFactors = FALSE
  )
  segments <- data.frame(
    entity_type = "SEGMENT", activity_id = as.character(segment_predictions$activity_id),
    sample_index = NA_integer_, from_sample_index = as.integer(segment_predictions$from_sample_index),
    to_sample_index = as.integer(segment_predictions$to_sample_index),
    predicted_classification = segment_predictions$classification,
    primary_reason_code = segment_predictions$primary_reason_code,
    evaluation_status = segment_predictions$evaluation_status,
    stringsAsFactors = FALSE
  )
  rbind(observations, segments)
}

gps_evaluation_summary <- function(rows, entity_type, partition) {
  subset <- rows[rows$entity_type == entity_type & rows$calibration_partition == partition &
    rows$manual_label != "UNREVIEWED" & !is.na(rows$predicted_classification), , drop = FALSE]
  reviewed <- nrow(subset)
  decisive <- subset$predicted_classification %in% c("ACCEPTED", "REJECTED")
  data.frame(
    entity_type = entity_type, calibration_partition = partition,
    reviewed_rows = reviewed, unique_entities = length(unique(subset$entity_key)),
    matched_rows = reviewed, agreement_count = sum(subset$manual_label == subset$predicted_classification),
    agreement_rate = if (reviewed) mean(subset$manual_label == subset$predicted_classification) else NA_real_,
    decisive_coverage = if (reviewed) mean(decisive) else NA_real_,
    uncertainty_rate = if (reviewed) mean(subset$predicted_classification == "UNCERTAIN") else NA_real_,
    false_acceptance_count = sum(subset$predicted_classification == "ACCEPTED" & subset$manual_label == "REJECTED"),
    false_rejection_count = sum(subset$predicted_classification == "REJECTED" & subset$manual_label == "ACCEPTED"),
    over_confidence_count = sum(decisive & subset$manual_label == "UNCERTAIN"),
    under_confidence_count = sum(subset$predicted_classification == "UNCERTAIN" &
      subset$manual_label %in% c("ACCEPTED", "REJECTED")), stringsAsFactors = FALSE
  )
}

evaluate_gps_qualification <- function(
  observation_predictions,
  segment_predictions,
  reviewed_labels,
  observation_features = NULL,
  segment_features = NULL,
  reasons = NULL
) {
  required <- c(
    "entity_type", "activity_id", "sample_index", "from_sample_index", "to_sample_index",
    "case_key", "calibration_partition", "manual_label", "evidence_version"
  )
  missing <- setdiff(required, names(reviewed_labels))
  if (length(missing)) stop("Reviewed labels are missing: ", paste(missing, collapse = ", "), call. = FALSE)
  if (any(!reviewed_labels$manual_label %in% c(GPS_QUALIFICATION_CLASSES, "UNREVIEWED"))) {
    stop("Reviewed labels contain an unsupported classification.", call. = FALSE)
  }
  evidence_key <- do.call(paste, c(reviewed_labels[c(
    "entity_type", "activity_id", "sample_index", "from_sample_index", "to_sample_index",
    "case_key", "evidence_version"
  )], sep = "\034"))
  if (anyDuplicated(evidence_key)) stop("Reviewed labels contain duplicate evidence keys.", call. = FALSE)
  reviewed_labels$entity_key <- gps_label_entity_key(reviewed_labels)
  reviewed <- reviewed_labels[reviewed_labels$manual_label != "UNREVIEWED", , drop = FALSE]
  classifications <- split(reviewed$manual_label, reviewed$entity_key)
  conflicts <- names(classifications)[vapply(classifications, function(x) length(unique(x)) > 1L, logical(1))]
  if (length(conflicts)) stop("Reviewed labels conflict for the same geographic entity.", call. = FALSE)

  predictions <- gps_prediction_rows(observation_predictions, segment_predictions)
  predictions$entity_key <- gps_label_entity_key(predictions)
  if (anyDuplicated(predictions$entity_key)) stop("Predictions contain duplicate geographic entity keys.", call. = FALSE)
  if (!is.null(observation_features) || !is.null(segment_features)) {
    feature_rows <- list()
    if (!is.null(observation_features) && nrow(observation_features)) {
      frame <- observation_features
      frame$entity_type <- "OBSERVATION"
      frame$from_sample_index <- NA_integer_; frame$to_sample_index <- NA_integer_
      frame$entity_key <- gps_label_entity_key(frame)
      feature_rows[[length(feature_rows) + 1L]] <- frame
    }
    if (!is.null(segment_features) && nrow(segment_features)) {
      frame <- segment_features
      frame$entity_type <- "SEGMENT"; frame$sample_index <- NA_integer_
      frame$entity_key <- gps_label_entity_key(frame)
      feature_rows[[length(feature_rows) + 1L]] <- frame
    }
    if (length(feature_rows)) {
      feature_columns <- unique(unlist(lapply(feature_rows, names), use.names = FALSE))
      feature_rows <- lapply(feature_rows, function(frame) {
        for (column in setdiff(feature_columns, names(frame))) frame[[column]] <- NA
        frame[, feature_columns, drop = FALSE]
      })
      feature_frame <- do.call(rbind, feature_rows)
      keep <- setdiff(names(feature_frame), c(
        "entity_type", "activity_id", "sample_index", "from_sample_index",
        "to_sample_index", "entity_key", "case_key", "evidence_provenance",
        "is_focus_observation", "is_focus_segment", "input_signature"
      ))
      names(feature_frame)[match(keep, names(feature_frame))] <- paste0("feature_", keep)
      predictions <- merge(predictions, feature_frame[, c("entity_key", paste0("feature_", keep)), drop = FALSE],
        by = "entity_key", all.x = TRUE, sort = FALSE)
    }
  }
  if (!is.null(reasons) && nrow(reasons)) {
    reasons$entity_key <- gps_label_entity_key(reasons)
    reason_codes <- tapply(reasons$reason_code, reasons$entity_key, function(values) {
      paste(sort(unique(values)), collapse = ";")
    })
    reason_frame <- data.frame(
      entity_key = names(reason_codes), fired_reason_codes = unname(reason_codes),
      stringsAsFactors = FALSE
    )
    predictions <- merge(predictions, reason_frame, by = "entity_key", all.x = TRUE, sort = FALSE)
  }
  matched <- merge(
    reviewed_labels, predictions[, setdiff(names(predictions), c(
      "entity_type", "activity_id", "sample_index", "from_sample_index", "to_sample_index"
    )), drop = FALSE], by = "entity_key", all.x = TRUE, sort = FALSE
  )
  matched$match_status <- ifelse(is.na(matched$predicted_classification), "UNMATCHED", "MATCHED")
  matched$agreement <- ifelse(
    matched$manual_label == "UNREVIEWED" | is.na(matched$predicted_classification),
    NA, matched$manual_label == matched$predicted_classification
  )
  summaries <- do.call(rbind, lapply(c("OBSERVATION", "SEGMENT"), function(entity_type) {
    do.call(rbind, lapply(c("CALIBRATION", "HOLDOUT"), function(partition) {
      gps_evaluation_summary(matched, entity_type, partition)
    }))
  }))
  confusion <- do.call(rbind, lapply(c("OBSERVATION", "SEGMENT"), function(entity_type) {
    do.call(rbind, lapply(c("CALIBRATION", "HOLDOUT"), function(partition) {
      rows <- matched[matched$entity_type == entity_type &
        matched$calibration_partition == partition & matched$manual_label != "UNREVIEWED" &
        !is.na(matched$predicted_classification), , drop = FALSE]
      grid <- expand.grid(
        manual_label = GPS_QUALIFICATION_CLASSES,
        predicted_classification = GPS_QUALIFICATION_CLASSES,
        stringsAsFactors = FALSE
      )
      counts <- table(
        factor(rows$manual_label, levels = GPS_QUALIFICATION_CLASSES),
        factor(rows$predicted_classification, levels = GPS_QUALIFICATION_CLASSES)
      )
      grid$count <- as.integer(counts)
      grid$entity_type <- entity_type; grid$calibration_partition <- partition
      grid[, c("entity_type", "calibration_partition", "manual_label", "predicted_classification", "count")]
    }))
  }))
  disagreements <- matched[
    matched$manual_label != "UNREVIEWED" & !is.na(matched$agreement) & !matched$agreement, , drop = FALSE
  ]
  holdout <- matched[matched$calibration_partition == "HOLDOUT" &
    matched$manual_label != "UNREVIEWED", , drop = FALSE]
  list(
    coverage = matched,
    summary = summaries,
    confusion = confusion,
    disagreements = disagreements,
    holdout_cases = holdout,
    counts = data.frame(
      evidence_rows = nrow(reviewed_labels), reviewed_rows = nrow(reviewed),
      unique_reviewed_entities = length(unique(reviewed$entity_key)),
      unreviewed_rows = sum(reviewed_labels$manual_label == "UNREVIEWED"),
      matched_rows = sum(matched$match_status == "MATCHED"),
      unmatched_rows = sum(matched$match_status == "UNMATCHED"), stringsAsFactors = FALSE
    )
  )
}

write_gps_qualification_outputs <- function(result, manifest, output_directory, repository_root = getwd()) {
  filenames <- c(
    "observation_features.csv", "segment_features.csv", "observation_decisions.csv",
    "segment_decisions.csv", "qualification_reasons.csv", "evaluation_summary.csv",
    "evaluation_confusion.csv", "evaluation_coverage.csv", "evaluation_disagreements.csv",
    "holdout_cases.csv", "run_manifest.csv"
  )
  destination <- validate_track_evidence_output_destination(
    output_directory, filenames, repository_root
  )
  required <- c(
    "observation_features", "segment_features", "observation_decisions", "segment_decisions",
    "reasons", "evaluation"
  )
  missing <- setdiff(required, names(result))
  if (length(missing)) stop("Qualification result is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  dir.create(destination$output_directory, recursive = TRUE, showWarnings = FALSE)
  outputs <- list(
    result$observation_features, result$segment_features, result$observation_decisions,
    result$segment_decisions, result$reasons, result$evaluation$summary,
    result$evaluation$confusion, result$evaluation$coverage,
    result$evaluation$disagreements, result$evaluation$holdout_cases, manifest
  )
  for (i in seq_along(outputs)) {
    utils::write.csv(outputs[[i]], destination$paths[[i]], row.names = FALSE, na = "")
  }
  invisible(destination$output_directory)
}
