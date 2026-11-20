GPS_STAGE2CA_PACKAGE_VERSION <- "gps-qualification-stage2ca-scientific-reconciliation-v2"
GPS_STAGE2CA_PROVENANCE <- "OWNER_SCIENTIFIC_REVIEW_2026-11-18_TO_2026-11-20_FINAL_RECONCILIATION"

stage2ca_sha256 <- function(path) {
  digest::digest(normalizePath(path, mustWork = TRUE), algo = "sha256", file = TRUE)
}

verify_stage2ca_file_manifest <- function(manifest_path, relative_root = NULL) {
  manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
  if (!all(c("sha256") %in% names(manifest))) {
    stop("Evidence manifest lacks sha256.", call. = FALSE)
  }
  if ("path" %in% names(manifest)) {
    paths <- manifest$path
  } else if ("file_name" %in% names(manifest) && !is.null(relative_root)) {
    paths <- file.path(relative_root, manifest$file_name)
  } else {
    stop("Evidence manifest has no resolvable path column.", call. = FALSE)
  }
  if (any(!file.exists(paths))) stop("Evidence manifest references a missing file.", call. = FALSE)
  hashes <- vapply(paths, stage2ca_sha256, character(1))
  if (any(hashes != manifest$sha256)) stop("Evidence manifest hash mismatch.", call. = FALSE)
  invisible(data.frame(path = paths, sha256 = hashes, stringsAsFactors = FALSE))
}

build_stage2ca_decision_ledger <- function(prior_decisions) {
  required <- c(
    "entity_type", "activity_id", "sample_index", "from_sample_index",
    "to_sample_index", "case_key", "decision_status", "conditional_acceptance",
    "review_provenance", "reviewer_rationale", "confirmed_research_label",
    "governance_status"
  )
  if (!all(required %in% names(prior_decisions))) {
    stop("Prior decision ledger schema is incomplete.", call. = FALSE)
  }
  result <- data.frame(
    entity_type = prior_decisions$entity_type,
    activity_id = as.character(prior_decisions$activity_id),
    sample_index = prior_decisions$sample_index,
    from_sample_index = prior_decisions$from_sample_index,
    to_sample_index = prior_decisions$to_sample_index,
    prior_case_key = prior_decisions$case_key,
    prior_decision_status = prior_decisions$decision_status,
    prior_research_label = prior_decisions$confirmed_research_label,
    prior_conditional_acceptance = prior_decisions$conditional_acceptance,
    prior_review_provenance = prior_decisions$review_provenance,
    reconciliation_action = ifelse(
      nzchar(prior_decisions$confirmed_research_label),
      "RETAINED_PRIOR_RESEARCH_DECISION", "REMAINS_UNREVIEWED"
    ),
    current_research_label = prior_decisions$confirmed_research_label,
    current_decision_status = prior_decisions$decision_status,
    current_conditional_acceptance = prior_decisions$conditional_acceptance,
    owner_review_date = "2026-11-19",
    reconciliation_provenance = GPS_STAGE2CA_PROVENANCE,
    reconciliation_rationale = "Prior research state retained without promotion to governed policy.",
    governance_status = "SCIENTIFIC_RESEARCH_DECISION_NOT_GOVERNED_LABEL",
    stringsAsFactors = FALSE
  )

  conditional_resolved <- result$activity_id %in% c("31722499", "989877988") &
    result$prior_conditional_acceptance == "TRUE"
  result$reconciliation_action[conditional_resolved] <- "CONDITION_SATISFIED"
  result$current_decision_status[conditional_resolved] <-
    "OWNER_CONFIRMED_UNCONDITIONAL_RESEARCH_DECISION"
  result$current_conditional_acceptance[conditional_resolved] <- "FALSE"
  result$reconciliation_rationale[conditional_resolved] <- ifelse(
    result$activity_id[conditional_resolved] == "31722499",
    "Owner confirmed repeated initial positions are geographically correct; the prior geographic-credibility condition is satisfied.",
    "Owner confirmed both focus observations are geographically credible; the prior geographic-credibility condition is satisfied."
  )

  superseded <- result$entity_type == "OBSERVATION" &
    result$activity_id == "158147957" &
    suppressWarnings(as.integer(result$sample_index)) %in% 1009:1015
  result$reconciliation_action[superseded] <- "SUPERSEDED_BY_OWNER_REASSESSMENT"
  superseded_samples <- suppressWarnings(as.integer(result$sample_index[superseded]))
  result$current_research_label[superseded] <- ifelse(
    superseded_samples <= 1013L, "UNCERTAIN", "REJECTED"
  )
  result$current_decision_status[superseded] <- "OWNER_CONFIRMED_SUPERSEDING_RESEARCH_DECISION"
  result$current_conditional_acceptance[superseded] <- "FALSE"
  result$reconciliation_rationale[superseded] <- ifelse(
    superseded_samples <= 1013L,
    "Owner final review found samples 1009-1013 physically plausible but not sufficiently established; the final non-governed research decision is UNCERTAIN.",
    "Owner final review found samples 1014-1015 geographically unreliable; the recording interruption is contextual evidence but not a standalone rejection rule."
  )

  superseded_segments <- result$entity_type == "SEGMENT" &
    result$activity_id == "158147957" &
    suppressWarnings(as.integer(result$from_sample_index)) %in% 1008:1014
  segment_from <- suppressWarnings(as.integer(result$from_sample_index[superseded_segments]))
  result$reconciliation_action[superseded_segments] <- "SUPERSEDED_BY_FINAL_OWNER_REASSESSMENT"
  result$current_research_label[superseded_segments] <- ifelse(
    segment_from <= 1012L, "UNCERTAIN", "REJECTED"
  )
  result$current_decision_status[superseded_segments] <-
    "OWNER_CONFIRMED_SUPERSEDING_RESEARCH_DECISION"
  result$current_conditional_acceptance[superseded_segments] <- "FALSE"
  result$reconciliation_rationale[superseded_segments] <- ifelse(
    segment_from <= 1012L,
    "Owner final review supersedes the earlier rejection with UNCERTAIN; plausible geometry does not establish that the route was occupied.",
    "Owner final review retains REJECTED for the geographically unreliable connecting geometry."
  )
  result
}

stage2ca_contextual_findings <- function() {
  data.frame(
    activity_id = c(
      "31690375", "31690375", "15562928333", "158147957", "44605096",
      "48062184", "31722499", "48062184", "31856627", "31856627",
      "3057187825", "1128729284", "989877988", "31856627"
    ),
    finding_type = c(
      "SUSTAINED_POSITIONAL_BIAS", "LOCAL_CONSISTENCY_LIMITATION",
      "DISTANCE_DIVERGENCE_AND_RECONCILIATION", "PLAUSIBLE_DESTINATION_REASSESSMENT",
      "CREDIBLE_TRACE_WITH_MEASUREMENT_STEP", "CLEAN_MOVEMENT_CONTROL",
      "BENIGN_DUPLICATED_INITIAL_OBSERVATIONS", "SPARSE_RECORDING_PROBABLE_STOP",
      "CREDIBLE_ENDPOINTS_UNRELIABLE_GEOMETRY", "OFFICE_REACQUISITION_EPISODE",
      "PROGRESSIVE_ACQUISITION_RECOVERY", "UNDERGROUND_CAR_PARK_DISTURBANCE",
      "LATERAL_DISTURBANCE_AFTER_CREDIBLE_FOCUS", "OFFICE_ONSET_FINAL_REVIEW"
    ),
    from_sample_index = c(87, 86, 1459, 1008, 785, 2313, 1, 5827, 6239, 5357, 1, 357, 211, 5327),
    to_sample_index = c(108, 109, 1472, 1015, 786, 2374, 20, 5888, 6241, 5415, 40, 370, 219, 5387),
    assessment_class = c(
      "CONTEXTUAL_GEOGRAPHIC_ASSESSMENT", "SCIENTIFIC_LIMITATION",
      "QUANTITATIVE_AND_CONTEXTUAL_FINDING", "CONTEXTUAL_GEOGRAPHIC_ASSESSMENT",
      "CONTROL_FINDING", "CONTROL_FINDING", "CONTROL_FINDING",
      "CONTEXTUAL_PLAUSIBLE_EXPLANATION", "CONTEXTUAL_GEOGRAPHIC_ASSESSMENT",
      "CONTEXTUAL_GEOGRAPHIC_ASSESSMENT", "CONTEXTUAL_GEOGRAPHIC_ASSESSMENT",
      "CONTEXTUAL_GEOGRAPHIC_ASSESSMENT", "CONTEXTUAL_GEOGRAPHIC_ASSESSMENT",
      "QUANTITATIVE_AND_CONTEXTUAL_FINDING"
    ),
    owner_confirmed_finding = c(
      "Samples 87-108 follow the approximate route direction but are displaced north of the road.",
      "Plausible speed, direction and reported-distance agreement do not establish absolute positional accuracy.",
      "Uniform displaced movement accumulates negative signed distance discrepancy before an abrupt geographically identified recovery.",
      "Sample 1012 lies at a plausible former-office entrance; unusual route geometry may represent the actual approach.",
      "The accepted focus segment has a discrete signed-distance step without a compelling geographic or kinematic anomaly.",
      "The road-aligned control has close geographic and reported-distance agreement with small gradual signed divergence.",
      "Samples 1-20 repeat position and timestamp but are geographically correct; their repetition does not measure stationary duration.",
      "Positions are credible across the window; waiting for dropped riders is plausible but not historically confirmed.",
      "Both endpoints are credible and sample 6241 exists, while the unobserved connecting geometry is not credible.",
      "Leaving the office is associated with a displaced episode followed by full geographic reacquisition.",
      "Local measurement consistency returns before definite geographic reacquisition; focus plausibility may be coincidental within disturbance.",
      "The workday gap is not evidence of continuous GPS disturbance; numerical and geographic recovery have different timing.",
      "The accepted focus precedes a short lateral displacement; the disturbance contributes less signed discrepancy than the credible focus.",
      "Minor wandering precedes sample 5357; the owner identifies 5357 as the last credible sample and reports an approximately 90-degree real route turn while the recorded trace turns by approximately 45 degrees. The owner-reported route geometry is distinct from calculated segment-bearing changes."
    ),
    plausible_explanation = c(
      "Sustained positional bias", "", "Source/device processing unresolved",
      "Legitimate office approach and later stationary drift", "", "", "",
      "Group stop after descent", "Recording interruption", "GPS reacquisition",
      "Underground initial acquisition", "Underground car park and working-day interruption",
      "Short lateral positional disturbance", "Insufficient recorded change in direction"
    ),
    unresolved_hypothesis = c(
      "Mechanism and numeric boundary signature unresolved", "Reported-distance provenance unresolved",
      "Garmin distance algorithm not inferred", "Source-level cropping remains a future possibility; no source modification is authorised",
      "Cause of discrepancy step unresolved", "Cause of gradual divergence unresolved",
      "Origin of repeated records unresolved", "Whether riders actually waited is unconfirmed",
      "Actual path during gap unknown", "Onset context requires supplementary evidence",
      "No unique numeric recovery marker", "Unobserved interval reception state unknown",
      "Temporal proximity does not establish causation",
      "No compelling numerical onset signature; mechanism remains unresolved"
    ),
    creates_individual_label = FALSE,
    provenance = GPS_STAGE2CA_PROVENANCE,
    governance_status = "OWNER_CONFIRMED_CONTEXT_NOT_GOVERNED_LABEL",
    stringsAsFactors = FALSE
  )
}

stage2ca_boundary_register <- function() {
  rows <- list(
    c("31690375", "CANNON_STREET_DISPLACEMENT", "LAST_RELIABLE", 86, 86, "Owner-confirmed contextual boundary"),
    c("31690375", "CANNON_STREET_DISPLACEMENT", "DISPLACED_RANGE", 87, 108, "Approximate route direction but north of road"),
    c("31690375", "CANNON_STREET_DISPLACEMENT", "GEOGRAPHIC_RECOVERY", 109, 109, "Geographic recovery"),
    c("15562928333", "KINGSTON_REACQUISITION", "UNIFORM_DISPLACED_RANGE", 1459, 1471, "Straight uniform trace"),
    c("15562928333", "KINGSTON_REACQUISITION", "ABRUPT_RECOVERY", 1472, 1472, "Road alignment resumes"),
    c("158147957", "END_ACTIVITY_REASSESSMENT", "PLAUSIBLE_DESTINATION", 1012, 1012, "Former-office entrance"),
    c("31856627", "OFFICE_REACQUISITION", "LAST_DEFINITELY_RELIABLE", 5357, 5357, "Owner-confirmed after supplementary review"),
    c("31856627", "OFFICE_REACQUISITION", "DISPLACED_RANGE", 5358, 5414, "Approximate position but displaced from road"),
    c("31856627", "OFFICE_REACQUISITION", "FULL_REACQUISITION", 5415, 5415, "Full geographic reacquisition"),
    c("3057187825", "UNDERGROUND_ACQUISITION", "BROAD_AGREEMENT", 32, 32, "Broad geographic agreement"),
    c("3057187825", "UNDERGROUND_ACQUISITION", "DEFINITE_REACQUISITION", 40, 40, "Definite geographic reacquisition"),
    c("1128729284", "UNDERGROUND_CAR_PARK", "LAST_CREDIBLE", 357, 357, "Last credible position"),
    c("1128729284", "UNDERGROUND_CAR_PARK", "DISTURBED_RANGE", 358, 365, "Positional disturbance"),
    c("1128729284", "UNDERGROUND_CAR_PARK", "BROAD_AGREEMENT", 366, 366, "Broad geographic agreement"),
    c("1128729284", "UNDERGROUND_CAR_PARK", "FULL_REACQUISITION", 370, 370, "Apparent full reacquisition"),
    c("989877988", "LATERAL_DISTURBANCE", "CREDIBLE_BOUNDARY", 215, 215, "Credible before disturbance"),
    c("989877988", "LATERAL_DISTURBANCE", "INACCURATE_RANGE", 216, 218, "Geographically inaccurate"),
    c("989877988", "LATERAL_DISTURBANCE", "CREDIBILITY_RESTORED", 219, 219, "Geographic credibility restored")
  )
  result <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(result) <- c("activity_id", "episode_id", "milestone_type", "from_sample_index", "to_sample_index", "owner_assessment")
  result$from_sample_index <- as.integer(result$from_sample_index)
  result$to_sample_index <- as.integer(result$to_sample_index)
  result$individual_qualification_label <- ""
  result$owner_review_date <- "2026-11-19"
  result$provenance <- GPS_STAGE2CA_PROVENANCE
  result$governance_status <- "CONTEXTUAL_BOUNDARY_NOT_INDIVIDUAL_LABEL"
  result
}

read_stage2ca_segments <- function(evidence_root, request_id) {
  path <- file.path(evidence_root, request_id, "descriptive_segments.csv")
  result <- utils::read.csv(path, colClasses = c(activity_id = "character"), stringsAsFactors = FALSE)
  attr(result, "source_path") <- normalizePath(path, winslash = "/", mustWork = TRUE)
  result
}

stage2ca_segment <- function(segments, from, to) {
  row <- segments$from_sample_index == from & segments$to_sample_index == to
  if (sum(row) != 1L) stop("Expected segment is missing or duplicated.", call. = FALSE)
  segments[row, , drop = FALSE]
}

stage2ca_range <- function(segments, from, to) {
  result <- segments[
    segments$from_sample_index >= from & segments$to_sample_index <= to,
    , drop = FALSE
  ]
  if (!nrow(result) || result$from_sample_index[[1L]] != from ||
      result$to_sample_index[[nrow(result)]] != to ||
      any(result$to_sample_index != result$from_sample_index + 1L)) {
    stop("Quantitative range is incomplete.", call. = FALSE)
  }
  result
}

build_stage2ca_quantitative_verification <- function(evidence_root) {
  claims <- list(); counter <- 0L
  add <- function(activity, request, claim, discussed, computed, units, status, method, interpretation = "UNCHANGED") {
    counter <<- counter + 1L
    claims[[counter]] <<- data.frame(
      activity_id = activity, request_id = request, claim = claim,
      originally_discussed_value = discussed, recomputed_value = computed,
      units = units, verification_status = status, method = method,
      scientific_interpretation_impact = interpretation,
      source_evidence_path = normalizePath(
        file.path(evidence_root, request, "descriptive_segments.csv"),
        winslash = "/", mustWork = TRUE
      ),
      terminology = "Geographic distance is coordinate-derived; reported distance is source-cumulative-stream-derived and not assumed independent.",
      stringsAsFactors = FALSE
    )
  }
  one <- function(request, from, to) stage2ca_segment(read_stage2ca_segments(evidence_root, request), from, to)
  segment_range <- function(request, from, to) stage2ca_range(read_stage2ca_segments(evidence_root, request), from, to)

  kingston <- "STAGE2C_EPISODE_15562928333_KINGSTON_REACQUISITION"
  k_uniform <- segment_range(kingston, 1459, 1471)
  k_recovery <- one(kingston, 1471, 1472)
  add("15562928333", kingston, "Signed discrepancy across segments 1459-1460 through 1470-1471", "approximately -44.46", sum(k_uniform$gps_device_distance_signed_difference_metres), "metres", "CONFIRMED", "Sum geographic minus reported distance across the 12 segments.")
  add("15562928333", kingston, "Recovery segment geographic distance", "approximately 56.54", k_recovery$geographic_displacement_metres, "metres", "CONFIRMED", "Segment 1471-1472 coordinate-derived distance.")
  add("15562928333", kingston, "Recovery segment reported distance", "approximately 10.6", k_recovery$device_distance_difference_metres, "metres", "CONFIRMED", "Segment 1471-1472 source cumulative-distance difference.")
  add("15562928333", kingston, "Recovery segment signed discrepancy", "approximately +45.94", k_recovery$gps_device_distance_signed_difference_metres, "metres", "CONFIRMED", "Geographic minus reported distance for segment 1471-1472.")
  add("15562928333", kingston, "Uniform-range bearing span", "exceptionally uniform direction", diff(range(k_uniform$initial_bearing_degrees)), "degrees", "CONFIRMED_QUALITATIVE", "Maximum minus minimum initial bearing for segments 1459-1471.")
  add("15562928333", kingston, "Uniform-range geographic-distance span", "exceptionally uniform displacement", diff(range(k_uniform$geographic_displacement_metres)), "metres", "CONFIRMED_QUALITATIVE", "Maximum minus minimum segment geographic distance for segments 1459-1471.")
  k_after <- segment_range(kingston, 1472, 1477)
  add("15562928333", kingston, "Post-recovery signed discrepancy", "subsequent movement has much closer agreement", sum(k_after$gps_device_distance_signed_difference_metres), "metres", "CONFIRMED", "Sum geographic-minus-reported distance across segments 1472-1477.")

  end_request <- "STAGE2C_EPISODE_158147957_END_DETERIORATION"
  end_drift <- one(end_request, 1012, 1013); end_gap <- one(end_request, 1013, 1014)
  add("158147957", end_request, "Segment 1012-1013 geographic distance", "approximately 6.74", end_drift$geographic_displacement_metres, "metres", "CONFIRMED", "Coordinate-derived segment distance.")
  add("158147957", end_request, "Segment 1012-1013 elapsed time", "73", end_drift$elapsed_time_difference_seconds, "seconds", "CONFIRMED", "Recorded elapsed-time difference.")
  add("158147957", end_request, "Segment 1012-1013 reported distance", "no increase", end_drift$device_distance_difference_metres, "metres", "CONFIRMED", "Source cumulative-distance difference.")
  add("158147957", end_request, "Subsequent recording gap", "exceeds 34 hours", end_gap$elapsed_time_difference_seconds / 3600, "hours", "CONFIRMED", "Elapsed time for segment 1013-1014.")

  control <- "STAGE2C_STANDARD_ORDINARY_MOVEMENT_44605096_785"
  x <- one(control, 785, 786)
  add("44605096", control, "Focus signed distance discrepancy", "approximately 8.12", x$gps_device_distance_signed_difference_metres, "metres", "CONFIRMED", "Geographic minus reported distance for segment 785-786.")
  control_window <- read_stage2ca_segments(evidence_root, control)
  control_window$cumulative_signed <- cumsum(control_window$gps_device_distance_signed_difference_metres)
  add("44605096", control, "Cumulative discrepancy after focus through sample 816", "abrupt step followed by relative stability", control_window$cumulative_signed[control_window$to_sample_index == 816] - control_window$cumulative_signed[control_window$to_sample_index == 786], "metres change after focus", "CONFIRMED", "Difference between cumulative signed discrepancy at samples 786 and 816.")

  clean <- "STAGE2C_STANDARD_ORDINARY_MOVEMENT_48062184_2343"
  x <- segment_range(clean, 2313, 2374)
  add("48062184", clean, "Review-window geographic distance", "approximately 408.27", sum(x$geographic_displacement_metres), "metres", "CONFIRMED", "Sum of 61 coordinate-derived segment distances.")
  add("48062184", clean, "Review-window reported distance", "approximately 408.60", sum(x$device_distance_difference_metres), "metres", "CONFIRMED", "Sum of 61 source cumulative-distance differences.")

  repeated <- "STAGE2C_STANDARD_START_DUPLICATES_31722499_1"
  x <- segment_range(repeated, 1, 20)
  add("31722499", repeated, "Repeated initial segments", "samples 1-20 identical coordinates and elapsed times", sum(x$geographic_displacement_metres == 0 & x$elapsed_time_difference_seconds == 0), "segments", "CONFIRMED", "Count of 19 consecutive zero-displacement, zero-time segments.")
  repeated_movement <- segment_range(repeated, 20, 32)
  add("31722499", repeated, "Subsequent implied-speed span", "exceptionally uniform movement", diff(range(repeated_movement$implied_geographic_speed_metres_per_second)), "metres per second", "CONFIRMED_QUALITATIVE", "Maximum minus minimum implied speed across segments 20-32.")
  add("31722499", repeated, "Subsequent bearing span", "exceptionally uniform movement", diff(range(repeated_movement$initial_bearing_degrees)), "degrees", "CONFIRMED_QUALITATIVE", "Maximum minus minimum initial bearing across segments 20-32.")

  sparse <- "STAGE2C_STANDARD_SPARSE_LOW_MOVEMENT_48062184_5857"
  x <- one(sparse, 5857, 5858); window <- read_stage2ca_segments(evidence_root, sparse)
  add("48062184", sparse, "Focus recording gap", "284", x$elapsed_time_difference_seconds, "seconds", "CONFIRMED", "Recorded elapsed-time difference.")
  add("48062184", sparse, "Focus geographic distance", "approximately 17.7", x$geographic_displacement_metres, "metres", "CONFIRMED", "Coordinate-derived segment distance.")
  add("48062184", sparse, "Focus reported distance", "approximately 17.8", x$device_distance_difference_metres, "metres", "CONFIRMED", "Source cumulative-distance difference.")
  add("48062184", sparse, "One-second intervals outside focus", "predominant", sum(window$elapsed_time_difference_seconds[-which(window$from_sample_index == 5857)] == 1), "of 60 non-focus segments", "CONFIRMED", "Count of one-second intervals after excluding the focus gap.")

  sparse_end <- "STAGE2C_STANDARD_SPARSE_MOVEMENT_31856627_6239"
  x <- one(sparse_end, 6239, 6240)
  add("31856627", sparse_end, "Focus recording gap", "approximately 911", x$elapsed_time_difference_seconds, "seconds", "CONFIRMED", "Recorded elapsed-time difference.")
  add("31856627", sparse_end, "Focus geographic distance", "approximately 736", x$geographic_displacement_metres, "metres", "CONFIRMED", "Coordinate-derived segment distance.")
  add("31856627", sparse_end, "Focus reported distance", "close agreement", x$device_distance_difference_metres, "metres", "CONFIRMED", "Source cumulative-distance difference.")
  add("31856627", sparse_end, "Observation after focus", "sample 6241 exists", max(read_stage2ca_segments(evidence_root, sparse_end)$to_sample_index), "sample index", "CORRECTS_EARLIER_DESCRIPTION", "Maximum sample reference in extracted window.", "Earlier terminal-observation wording corrected; scientific interpretation unchanged.")

  office <- "STAGE2C_STANDARD_HIGH_SPEED_AGREEMENT_31856627_5392"
  x <- one(office, 5392, 5393); office_window <- read_stage2ca_segments(evidence_root, office)
  add("31856627", office, "Focus geographic distance", "approximately 134.5", x$geographic_displacement_metres, "metres", "CONFIRMED", "Coordinate-derived segment distance.")
  add("31856627", office, "Focus elapsed time", "3", x$elapsed_time_difference_seconds, "seconds", "CONFIRMED", "Recorded elapsed-time difference.")
  add("31856627", office, "Focus reported distance", "very close agreement", x$device_distance_difference_metres, "metres", "CONFIRMED", "Source cumulative-distance difference.")
  add("31856627", office, "Largest recording interruption", "approximately eight hours", max(office_window$elapsed_time_difference_seconds) / 3600, "hours", "CONFIRMED", "Maximum elapsed-time difference in current window.")
  add("31856627", office, "Largest absolute bearing change", "substantial reversal", max(office_window$bearing_change_degrees, na.rm = TRUE), "degrees", "CONFIRMED", "Maximum absolute bearing change in current window.")

  underground <- "STAGE2C_STANDARD_HIGH_SPEED_DISAGREEMENT_3057187825_16"
  u <- read_stage2ca_segments(evidence_root, underground)
  u$cumulative_signed <- cumsum(u$gps_device_distance_signed_difference_metres)
  add("3057187825", underground, "Cumulative signed discrepancy at definite recovery sample 40", "does not reconcile", u$cumulative_signed[u$to_sample_index == 40], "metres", "CONFIRMED", "Cumulative geographic-minus-reported distance from window start through sample 40.")
  local_recovery <- stage2ca_range(u, 27, 40)
  add("3057187825", underground, "Maximum local signed discrepancy from samples 27-40", "local measurement agreement largely restored around sample 27", max(abs(local_recovery$gps_device_distance_signed_difference_metres)), "metres", "CONFIRMED", "Maximum absolute segment signed discrepancy across segments 27-40.")

  carpark <- "STAGE2C_STANDARD_MEASUREMENT_CONTRADICTION_1128729284_363"
  x <- one(carpark, 363, 364); cp <- read_stage2ca_segments(evidence_root, carpark)
  add("1128729284", carpark, "Focus geographic distance", "approximately 61.74", x$geographic_displacement_metres, "metres", "CONFIRMED", "Coordinate-derived segment distance.")
  add("1128729284", carpark, "Focus reported distance", "no increase", x$device_distance_difference_metres, "metres", "CONFIRMED", "Source cumulative-distance difference.")
  add("1128729284", carpark, "Largest recording gap", "approximately 10.87 hours", max(cp$elapsed_time_difference_seconds) / 3600, "hours", "CONFIRMED", "Maximum elapsed-time difference in review window.")

  lateral <- "STAGE2C_STANDARD_MEASUREMENT_CONTRADICTION_989877988_211"
  x <- one(lateral, 211, 212); disturbed <- segment_range(lateral, 215, 219)
  add("989877988", lateral, "Credible focus geographic distance", "approximately 15.4", x$geographic_displacement_metres, "metres", "CONFIRMED", "Coordinate-derived segment distance.")
  add("989877988", lateral, "Credible focus reported distance", "no increase", x$device_distance_difference_metres, "metres", "CONFIRMED", "Source cumulative-distance difference.")
  add("989877988", lateral, "Elapsed time between disturbance bounding observations", "approximately 29", sum(disturbed$elapsed_time_difference_seconds), "seconds", "CONFIRMED", "Sum elapsed time across segments 215-219.")
  add("989877988", lateral, "Disturbance signed discrepancy", "smaller than preceding credible focus", sum(disturbed$gps_device_distance_signed_difference_metres), "metres", "CONFIRMED", "Sum geographic-minus-reported distance across segments 215-219.")
  lateral_window <- read_stage2ca_segments(evidence_root, lateral)
  lateral_window$cumulative_signed <- cumsum(lateral_window$gps_device_distance_signed_difference_metres)
  add("989877988", lateral, "Cumulative discrepancy at end of review window", "persists after recovery", tail(lateral_window$cumulative_signed, 1L), "metres", "CONFIRMED", "Cumulative geographic-minus-reported distance through sample 242.")

  cannon <- "STAGE2C_EPISODE_31690375_INITIAL_ACQUISITION"
  onset <- one(cannon, 86, 87); recovery <- one(cannon, 108, 109)
  add("31690375", cannon, "Onset-boundary signed discrepancy", "strong agreement", onset$gps_device_distance_signed_difference_metres, "metres", "CONFIRMED", "Segment 86-87 geographic minus reported distance.")
  add("31690375", cannon, "Recovery-boundary signed discrepancy", "strong agreement", recovery$gps_device_distance_signed_difference_metres, "metres", "CONFIRMED", "Segment 108-109 geographic minus reported distance.")

  do.call(rbind, claims)
}

build_stage2ca_supplementary_quantitative_verification <- function(supplementary_root) {
  request <- "STAGE2CA_SUPPLEMENTARY_31856627_OFFICE_ONSET_5327_5387"
  segments <- read_stage2ca_segments(supplementary_root, request)
  focus <- stage2ca_segment(segments, 5357L, 5358L)
  before <- stage2ca_segment(segments, 5356L, 5357L)
  after <- stage2ca_segment(segments, 5358L, 5359L)
  claims <- data.frame(
    activity_id = "31856627",
    request_id = request,
    claim = c(
      "Focus elapsed time", "Focus geographic distance", "Focus implied speed",
      "Focus reported distance", "Focus signed distance discrepancy",
      "Calculated bearing change at focus", "Incoming recorded bearing",
      "Focus recorded bearing", "Following recorded bearing",
      "Owner-reported real route turn", "Owner visual estimate of recorded trace turn"
    ),
    originally_discussed_value = c(
      "no compelling interval signature", "no compelling displacement signature",
      "no compelling speed signature", "close distance consistency",
      "close distance consistency", "no compelling bearing-change signature",
      "calculated from evidence", "calculated from evidence", "calculated from evidence",
      "approximately 90", "approximately 45"
    ),
    recomputed_value = c(
      focus$elapsed_time_difference_seconds, focus$geographic_displacement_metres,
      focus$implied_geographic_speed_metres_per_second,
      focus$device_distance_difference_metres,
      focus$gps_device_distance_signed_difference_metres,
      focus$bearing_change_degrees, before$initial_bearing_degrees,
      focus$initial_bearing_degrees, after$initial_bearing_degrees, NA_real_, NA_real_
    ),
    units = c(
      "seconds", "metres", "metres per second", "metres", "metres", "degrees",
      "degrees", "degrees", "degrees", "degrees", "degrees"
    ),
    verification_status = c(
      rep("CONFIRMED", 9L), "OWNER_CONTEXT_NOT_CALCULABLE_FROM_GPS_EVIDENCE",
      "OWNER_CONTEXT_NOT_EQUIVALENT_TO_SINGLE_SEGMENT_BEARING_CHANGE"
    ),
    method = c(
      rep("Direct value from supplementary descriptive segment 5357-5358.", 6L),
      "Initial bearing for segment 5356-5357.",
      "Initial bearing for segment 5357-5358.",
      "Initial bearing for segment 5358-5359.",
      "Owner route knowledge; the extracted GPS evidence does not encode the intended physical route.",
      "Owner visual assessment of the wider trace; the calculated focus-segment bearing change is recorded separately."
    ),
    scientific_interpretation_impact = c(rep("UNCHANGED", 11L)),
    source_evidence_path = normalizePath(
      file.path(supplementary_root, request, "descriptive_segments.csv"),
      winslash = "/", mustWork = TRUE
    ),
    terminology = "Geographic distance is coordinate-derived; reported distance is source-cumulative-stream-derived and not assumed independent.",
    stringsAsFactors = FALSE
  )
  claims
}

build_stage2ca_coverage_register <- function(stage2c_registry) {
  status <- rep("OWNER_REVIEW_RECONCILED", nrow(stage2c_registry))
  outstanding <- rep("", nrow(stage2c_registry))
  context_only <- stage2c_registry$request_id %in% c(
    "STAGE2C_STANDARD_STATIONARY_GAP_31690375_7",
    "STAGE2C_STANDARD_HIGH_SPEED_AGREEMENT_31690375_22"
  )
  status[context_only] <- "OWNER_CONFIRMED_PRIOR_DECISIONS_RETAINED"
  outstanding[context_only] <- ""
  end_case <- stage2c_registry$activity_id == "158147957"
  status[end_case] <- "OWNER_REVIEW_COMPLETE_FINAL_DECISIONS_RECONCILED"
  outstanding[end_case] <- ""
  office <- stage2c_registry$request_id == "STAGE2C_STANDARD_HIGH_SPEED_AGREEMENT_31856627_5392"
  status[office] <- "OWNER_REVIEW_COMPLETE_WITH_ACCEPTED_SUPPLEMENTARY_CONTEXT"
  outstanding[office] <- ""
  data.frame(
    request_id = stage2c_registry$request_id,
    activity_id = as.character(stage2c_registry$activity_id),
    request_type = stage2c_registry$request_type,
    overlap_group = stage2c_registry$overlap_group,
    review_coverage_status = status,
    explicit_new_individual_decisions = ifelse(
      stage2c_registry$activity_id %in% c("158147957", "31722499", "989877988"),
      "YES", "NO_RETAINED_OR_CONTEXT_ONLY"
    ),
    outstanding_review_requirement = outstanding,
    holdout_inspected = FALSE,
    provenance = GPS_STAGE2CA_PROVENANCE,
    stringsAsFactors = FALSE
  )
}

build_stage2ca_supplementary_request <- function(source_evidence_path,
                                                 repository_revision) {
  data.frame(
    request_id = "STAGE2CA_SUPPLEMENTARY_31856627_OFFICE_ONSET_5327_5387",
    request_type = "STANDARD_CONTEXT",
    case_key = "SUPPLEMENTARY_OFFICE_ONSET_31856627_5357",
    episode_id = "ACTIVITY_31856627_OFFICE_REACQUISITION",
    activity_id = "31856627",
    window_from_sample_index = 5327L,
    window_to_sample_index = 5387L,
    focus_from_sample_index = 5357L,
    focus_to_sample_index = 5357L,
    focus_segment_from_sample_index = 5357L,
    focus_segment_to_sample_index = 5358L,
    original_focus_observation_indices = "5357;5358",
    original_focus_segment_pairs = "5357-5358",
    context_before_observations = 30L,
    context_after_observations = 30L,
    selection_rationale = "Supplementary calibration-only onset context: sample 5357 last definitely reliable, sample 5358 begins owner-identified displaced episode; overlaps existing Stage 2C evidence from 5362 onward.",
    calibration_partition = "CALIBRATION",
    overlap_group = "ACTIVITY_31856627_OFFICE_REACQUISITION",
    source_evidence_path = normalizePath(source_evidence_path, winslash = "/", mustWork = TRUE),
    source_evidence_sha256 = stage2ca_sha256(source_evidence_path),
    repository_revision = repository_revision,
    extraction_version = GPS_STAGE2C_EXTRACTION_VERSION,
    stringsAsFactors = FALSE
  )
}

validate_stage2ca_supplementary_overlap <- function(
  supplementary_root,
  existing_stage2c_root,
  supplementary_request_id = "STAGE2CA_SUPPLEMENTARY_31856627_OFFICE_ONSET_5327_5387",
  existing_request_id = "STAGE2C_STANDARD_HIGH_SPEED_AGREEMENT_31856627_5392"
) {
  read <- function(root, request, filename) {
    utils::read.csv(
      file.path(root, request, filename),
      colClasses = c(activity_id = "character"), stringsAsFactors = FALSE
    )
  }
  supplementary_observations <- read(
    supplementary_root, supplementary_request_id, "reference_window_observations.csv"
  )
  existing_observations <- read(
    existing_stage2c_root, existing_request_id, "reference_window_observations.csv"
  )
  expected_observations <- 5362:5387
  supplementary_overlap <- supplementary_observations[
    supplementary_observations$sample_index %in% expected_observations, , drop = FALSE
  ]
  existing_overlap <- existing_observations[
    existing_observations$sample_index %in% expected_observations, , drop = FALSE
  ]
  observation_columns <- c(
    "activity_id", "sample_index", "latitude", "longitude", "time_seconds",
    "distance_metres"
  )
  if (!identical(supplementary_overlap$sample_index, expected_observations) ||
      !identical(existing_overlap$sample_index, expected_observations) ||
      !isTRUE(all.equal(
        supplementary_overlap[, observation_columns],
        existing_overlap[, observation_columns],
        check.attributes = FALSE, tolerance = 0
      ))) {
    stop("Supplementary Stage 2CA observation overlap does not match Stage 2C.", call. = FALSE)
  }

  supplementary_segments <- read(
    supplementary_root, supplementary_request_id, "reference_window_segments.csv"
  )
  existing_segments <- read(
    existing_stage2c_root, existing_request_id, "reference_window_segments.csv"
  )
  supplementary_segment_overlap <- supplementary_segments[
    supplementary_segments$from_sample_index %in% 5362:5386 &
      supplementary_segments$to_sample_index %in% 5363:5387, , drop = FALSE
  ]
  existing_segment_overlap <- existing_segments[
    existing_segments$from_sample_index %in% 5362:5386 &
      existing_segments$to_sample_index %in% 5363:5387, , drop = FALSE
  ]
  segment_columns <- c(
    "activity_id", "from_sample_index", "to_sample_index", "from_latitude",
    "from_longitude", "to_latitude", "to_longitude",
    "elapsed_time_difference_seconds", "geographic_displacement_metres",
    "device_distance_difference_metres", "gps_device_distance_signed_difference_metres"
  )
  if (nrow(supplementary_segment_overlap) != 25L ||
      nrow(existing_segment_overlap) != 25L ||
      !isTRUE(all.equal(
        supplementary_segment_overlap[, segment_columns],
        existing_segment_overlap[, segment_columns],
        check.attributes = FALSE, tolerance = 0
      ))) {
    stop("Supplementary Stage 2CA segment overlap does not match Stage 2C.", call. = FALSE)
  }
  data.frame(
    activity_id = "31856627",
    overlap_from_sample_index = 5362L,
    overlap_to_sample_index = 5387L,
    matching_observation_count = 26L,
    matching_segment_count = 25L,
    overlap_status = "EXACT_MATCH",
    stringsAsFactors = FALSE
  )
}

write_stage2ca_package <- function(output_directory, prior_decisions_path,
                                   prior_context_path, stage2c_registry_path,
                                   stage2c_evidence_root, governed_snapshot_path,
                                   repository_revision, supplementary_root,
                                   prior_reconciliation_root,
                                   repository_root = getwd()) {
  filenames <- c(
    "scientific_decision_reconciliation.csv", "contextual_findings.csv",
    "disturbance_boundary_recovery_register.csv", "quantitative_verification.csv",
    "review_coverage_outstanding.csv", "supplementary_onset_request.csv",
    "scientific_principles_and_diagnostic_candidates.csv",
    "supplementary_evidence_validation.csv", "package_manifest.csv",
    "file_manifest.csv", "verification_report.md"
  )
  destination <- validate_track_evidence_output_destination(
    output_directory, filenames, repository_root
  )
  verify_stage2ca_file_manifest(
    file.path(stage2c_evidence_root, "file_manifest.csv")
  )
  verify_stage2ca_file_manifest(
    file.path(dirname(prior_decisions_path), "file_manifest.csv"),
    dirname(prior_decisions_path)
  )
  verify_stage2ca_file_manifest(file.path(supplementary_root, "file_manifest.csv"))
  verify_stage2ca_file_manifest(
    file.path(prior_reconciliation_root, "file_manifest.csv")
  )
  prior <- utils::read.csv(
    prior_decisions_path, colClasses = c(activity_id = "character"),
    stringsAsFactors = FALSE, na.strings = character()
  )
  registry <- utils::read.csv(
    stage2c_registry_path, colClasses = c(activity_id = "character"),
    stringsAsFactors = FALSE
  )
  if (any(registry$calibration_partition != "CALIBRATION") ||
      any(geographic_activity_partition(registry$activity_id) != "CALIBRATION")) {
    stop("Stage 2CA source registry includes holdout evidence.", call. = FALSE)
  }
  decisions <- build_stage2ca_decision_ledger(prior)
  context <- stage2ca_contextual_findings()
  boundaries <- stage2ca_boundary_register()
  quantitative <- rbind(
    build_stage2ca_quantitative_verification(stage2c_evidence_root),
    build_stage2ca_supplementary_quantitative_verification(supplementary_root)
  )
  coverage <- build_stage2ca_coverage_register(registry)
  supplementary <- build_stage2ca_supplementary_request(
    file.path(
      stage2c_evidence_root,
      "STAGE2C_STANDARD_HIGH_SPEED_AGREEMENT_31856627_5392",
      "reference_window_request.csv"
    ),
    repository_revision
  )
  supplementary_validation <- validate_stage2ca_supplementary_overlap(
    supplementary_root, stage2c_evidence_root
  )
  principles <- data.frame(
    category = c(rep("SCIENTIFIC_DIMENSION", 5), rep("PRINCIPLE", 8), rep("DIAGNOSTIC_CANDIDATE", 9), rep("LIMITATION", 6)),
    item = c(
      "Positional credibility", "Temporal continuity", "Measurement consistency",
      "Kinematic plausibility", "Contextual credibility",
      "Detection and boundary identification are separate problems",
      "Disturbance detection and recovery detection are separate problems",
      "Numerical recovery is not necessarily geographic recovery",
      "Missing observations do not establish continuous disturbance",
      "Manual geographic review contains uncertainty",
      "Technology and activity date are contextual variables",
      "Accepted stationary positions may establish sample-only tile evidence",
      "Rejected connecting geometry does not automatically invalidate endpoints",
      "Cumulative signed distance discrepancy", "Peak absolute cumulative discrepancy",
      "Rate and duration of discrepancy accumulation", "Reconciliation magnitude",
      "Implied speed", "Bearing change", "Repeated coordinates and timestamps",
      "Exceptional movement uniformity", "Recording gaps and multi-observation combinations",
      "Final cumulative discrepancy can conceal an excursion",
      "Persistent discrepancy need not mean persistent disturbance",
      "Legitimate movement may accumulate discrepancy", "Some disturbances never reconcile",
      "Near-zero reset may not delimit episodes",
      "Positional displacement may occur without distance disagreement"
    ),
    implementation_status = "RESEARCH_ONLY_NO_RULE_OR_THRESHOLD",
    provenance = GPS_STAGE2CA_PROVENANCE,
    stringsAsFactors = FALSE
  )
  dir.create(destination$output_directory, recursive = TRUE, showWarnings = FALSE)
  tables <- list(
    decisions, context, boundaries, quantitative, coverage, supplementary,
    principles, supplementary_validation
  )
  paths <- destination$paths
  for (index in seq_along(tables)) {
    utils::write.csv(tables[[index]], paths[[index]], row.names = FALSE, na = "")
  }
  package_manifest <- data.frame(
    property = c(
      "package_version", "milestone", "status", "owner_review_dates",
      "reconciliation_date", "repository_revision", "governance_status",
      "production_access", "holdout_inspected", "automated_decisions",
      "supplementary_extraction_status"
    ),
    value = c(
      GPS_STAGE2CA_PACKAGE_VERSION, "G3B.2A", "OWNER_ACCEPTED_CLOSED",
      "2026-11-18_TO_2026-11-20", "2026-11-20", repository_revision,
      "SCIENTIFIC_RESEARCH_ONLY_NOT_GOVERNED_LABEL", "NONE", "FALSE", "ZERO",
      "TECHNICALLY_ACCEPTED_AND_SCIENTIFICALLY_REVIEWED"
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(package_manifest, paths[[9L]], row.names = FALSE)
  report <- c(
    "# G3B.2A scientific reconciliation verification",
    "",
    "Status: Owner accepted and closed on 20 November 2026.",
    "",
    "The package reconciles owner review without changing governed labels or source evidence.",
    sprintf("Prior rows reconciled: %d.", nrow(decisions)),
    sprintf("Superseding observation decisions: %d.", sum(decisions$reconciliation_action == "SUPERSEDED_BY_OWNER_REASSESSMENT")),
    sprintf("Resolved reopened rows: %d.", sum(decisions$activity_id == "158147957" & decisions$reconciliation_action %in% c("SUPERSEDED_BY_OWNER_REASSESSMENT", "SUPERSEDED_BY_FINAL_OWNER_REASSESSMENT")) - 4L),
    sprintf("Conditional decisions resolved: %d.", sum(decisions$reconciliation_action == "CONDITION_SATISFIED")),
    sprintf("Quantitative claims verified: %d.", nrow(quantitative)),
    "",
    "All findings remain scientific research evidence. No qualification rule, threshold, production classification or governed label is created.",
    "The accepted supplementary office-onset evidence has exact overlap with the original Stage 2C package and contributes contextual findings only.",
    "All 15 original requests and the supplementary request are accounted for with no outstanding scientific review requirement for this milestone."
  )
  writeLines(report, paths[[11L]], useBytes = TRUE)

  inputs <- c(
    prior_decisions_path, prior_context_path, stage2c_registry_path,
    file.path(stage2c_evidence_root, "file_manifest.csv"),
    file.path(stage2c_evidence_root, "extraction_manifest.csv"),
    file.path(stage2c_evidence_root, "consolidated_observation_review.csv"),
    file.path(stage2c_evidence_root, "consolidated_segment_review.csv"),
    file.path(supplementary_root, "file_manifest.csv"),
    file.path(supplementary_root, "extraction_manifest.csv"),
    file.path(supplementary_root, "consolidated_observation_review.csv"),
    file.path(supplementary_root, "consolidated_segment_review.csv"),
    file.path(prior_reconciliation_root, "file_manifest.csv"),
    file.path(prior_reconciliation_root, "scientific_decision_reconciliation.csv"),
    governed_snapshot_path
  )
  written <- paths[c(1:9, 11)]
  manifest <- data.frame(
    file_role = c(rep("INPUT", length(inputs)), rep("OUTPUT", length(written))),
    path = normalizePath(c(inputs, written), winslash = "/", mustWork = TRUE),
    sha256 = vapply(c(inputs, written), stage2ca_sha256, character(1)),
    stringsAsFactors = FALSE
  )
  utils::write.csv(manifest, paths[[10L]], row.names = FALSE)
  invisible(list(
    decisions = decisions, contextual_findings = context, boundaries = boundaries,
    quantitative = quantitative, coverage = coverage, supplementary = supplementary,
    supplementary_validation = supplementary_validation, file_manifest = manifest
  ))
}
