#!/usr/bin/env Rscript

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 3L) {
  stop(
    "Usage: run_gps_qualification_prototype.R <evidence-manifest.csv> <reviewed-labels.csv> <output-directory>",
    call. = FALSE
  )
}

repository_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)
source(file.path(repository_root, "R", "quality", "profile_activity_track_integrity.R"))
source(file.path(repository_root, "R", "quality", "profile_geographic_calibration_evidence.R"))
source(file.path(repository_root, "R", "quality", "gps_qualification_prototype.R"))

manifest_path <- normalizePath(path.expand(arguments[[1L]]), winslash = "/", mustWork = TRUE)
labels_path <- normalizePath(path.expand(arguments[[2L]]), winslash = "/", mustWork = TRUE)
output_directory <- resolve_track_evidence_output_path(arguments[[3L]])

evidence_manifest <- utils::read.csv(manifest_path, stringsAsFactors = FALSE)
required_manifest <- c("observation_path", "segment_path")
if (any(!required_manifest %in% names(evidence_manifest)) || !nrow(evidence_manifest)) {
  stop("Evidence manifest must contain observation_path and segment_path rows.", call. = FALSE)
}
resolve_input <- function(path) normalizePath(path.expand(path), winslash = "/", mustWork = TRUE)
evidence_manifest$observation_path <- vapply(evidence_manifest$observation_path, resolve_input, character(1))
evidence_manifest$segment_path <- vapply(evidence_manifest$segment_path, resolve_input, character(1))
protected <- unique(c(
  dirname(labels_path), dirname(evidence_manifest$observation_path),
  dirname(evidence_manifest$segment_path)
))
if (any(vapply(protected, function(path) {
  identical(output_directory, path) || startsWith(output_directory, paste0(path, "/"))
}, logical(1)))) {
  stop("Output directory must not be inside an input or governed-evidence directory.", call. = FALSE)
}

features <- lapply(seq_len(nrow(evidence_manifest)), function(i) {
  observations <- utils::read.csv(evidence_manifest$observation_path[[i]], stringsAsFactors = FALSE)
  segments <- utils::read.csv(evidence_manifest$segment_path[[i]], stringsAsFactors = FALSE)
  if ("case_key" %in% names(evidence_manifest) &&
      !is.na(evidence_manifest$case_key[[i]]) && nzchar(evidence_manifest$case_key[[i]])) {
    case_key <- evidence_manifest$case_key[[i]]
    observations <- observations[observations$case_key == case_key, , drop = FALSE]
    segments <- segments[segments$case_key == case_key, , drop = FALSE]
    if (!nrow(observations) || !nrow(segments)) {
      stop("Evidence manifest case_key was not present in both evidence files: ", case_key, call. = FALSE)
    }
  }
  if (all(c("silver_time_seconds", "silver_latitude", "silver_longitude", "silver_distance_metres") %in%
      names(observations))) {
    samples <- data.frame(
      activity_id = as.character(observations$activity_id),
      sample_index = as.integer(observations$sample_index),
      latitude = as.numeric(observations$silver_latitude),
      longitude = as.numeric(observations$silver_longitude),
      time_seconds = as.numeric(observations$silver_time_seconds),
      distance_metres = as.numeric(observations$silver_distance_metres),
      stringsAsFactors = FALSE
    )
    prepared <- prepare_gps_qualification_features(samples)
    prepared$observations$case_key <- observations$case_key
    prepared$segments$case_key <- unique(segments$case_key)[[1L]]
    return(prepared)
  }
  prepare_gps_qualification_evidence_features(observations, segments)
})

bind <- function(name) {
  frames <- lapply(features, `[[`, name)
  columns <- unique(unlist(lapply(frames, names), use.names = FALSE))
  frames <- lapply(frames, function(frame) {
    missing <- setdiff(columns, names(frame))
    for (column in missing) frame[[column]] <- NA
    frame[, columns, drop = FALSE]
  })
  do.call(rbind, frames)
}
observation_features <- bind("observations")
segment_features <- bind("segments")
observation_entity_key <- paste(observation_features$activity_id, observation_features$sample_index, sep = "\034")
segment_entity_key <- paste(
  segment_features$activity_id, segment_features$from_sample_index,
  segment_features$to_sample_index, sep = "\034"
)
deduplicate_identical_entities <- function(frame, keys, entity_type, source_columns, context_score) {
  groups <- split(seq_along(keys), keys)
  inconsistent <- vapply(groups, function(indexes) {
    if (length(indexes) <= 1L) return(FALSE)
    signatures <- vapply(indexes, function(index) {
      gps_qualification_input_signature(frame[index, , drop = FALSE], source_columns)
    }, character(1))
    length(unique(signatures)) > 1L
  }, logical(1))
  if (any(inconsistent)) {
    stop("Evidence sources conflict for duplicate ", entity_type, " geographic keys.", call. = FALSE)
  }
  selected <- vapply(groups, function(indexes) indexes[[which.max(context_score[indexes])]], integer(1))
  frame[sort(selected), , drop = FALSE]
}
observation_features <- deduplicate_identical_entities(
  observation_features, observation_entity_key, "observation",
  c("activity_id", "sample_index", "latitude", "longitude", "time_seconds", "distance_metres"),
  as.integer(observation_features$source_context_before_available) +
    as.integer(observation_features$source_context_after_available)
)
segment_features <- deduplicate_identical_entities(
  segment_features, segment_entity_key, "segment",
  c(
    "activity_id", "from_sample_index", "to_sample_index", "from_latitude",
    "from_longitude", "to_latitude", "to_longitude", "elapsed_time_difference_seconds",
    "geographic_displacement_metres", "device_distance_difference_metres"
  ),
  rep(0L, nrow(segment_features))
)

policy <- default_gps_qualification_policy()
started_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
run_context <- list(evaluation_run_id = paste0(
  "gpsq-", format(Sys.time(), "%Y%m%dT%H%M%SZ", tz = "UTC"), "-",
  substr(fingerprint_gps_qualification_policy(policy), 1L, 12L)
))
observation_result <- qualify_gps_observations(observation_features, policy, run_context)
segment_result <- qualify_gps_segments(segment_features, policy, run_context)
reasons <- rbind(observation_result$reasons, segment_result$reasons)
labels <- utils::read.csv(labels_path, stringsAsFactors = FALSE, na.strings = c("", "NA"))
evaluation <- evaluate_gps_qualification(
  observation_result$decisions, segment_result$decisions, labels,
  observation_features, segment_features, reasons
)

input_paths <- c(
  manifest_path, labels_path, evidence_manifest$observation_path, evidence_manifest$segment_path
)
input_hashes <- vapply(input_paths, digest::digest, character(1), algo = "sha256", file = TRUE)
repository_sha <- tryCatch(
  trimws(system2("git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)),
  error = function(error) NA_character_
)
run_manifest <- data.frame(
  evaluation_run_id = run_context$evaluation_run_id,
  policy_version = policy$policy_version,
  policy_fingerprint = fingerprint_gps_qualification_policy(policy),
  feature_contract_version = policy$feature_contract_version,
  repository_commit_sha = repository_sha[[1L]],
  started_at_utc = started_at,
  completed_at_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  label_snapshot_path = labels_path,
  label_snapshot_sha256 = input_hashes[[2L]],
  input_paths = paste(input_paths, collapse = "|"),
  input_sha256 = paste(input_hashes, collapse = "|"),
  stringsAsFactors = FALSE
)
result <- list(
  observation_features = observation_features,
  segment_features = segment_features,
  observation_decisions = observation_result$decisions,
  segment_decisions = segment_result$decisions,
  reasons = reasons,
  evaluation = evaluation
)
write_gps_qualification_outputs(result, run_manifest, output_directory, repository_root)
message(
  "GPS qualification prototype complete: ", nrow(labels), " evidence rows; ",
  sum(labels$manual_label != "UNREVIEWED"), " reviewed; output ", output_directory
)
