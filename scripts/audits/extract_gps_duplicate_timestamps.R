#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) < 2L || length(arguments) > 3L ||
    any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/extract_gps_duplicate_timestamps.R",
      "<activity-id> <output-directory> [context-observations]"
    ),
    call. = FALSE
  )
}

activity_id <- validate_gps_investigation_activity_id(arguments[[1L]])
output_directory <- arguments[[2L]]
context_observations <- if (length(arguments) == 3L) {
  suppressWarnings(as.integer(arguments[[3L]]))
} else {
  5L
}
if (is.na(context_observations) || context_observations < 0L) {
  stop("context-observations must be a non-negative integer.", call. = FALSE)
}
validate_track_evidence_output_destination(
  output_directory, unname(duplicate_timestamp_evidence_filenames())
)

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
source_evidence <- fetch_gps_raw_silver_evidence(connection, activity_id)
evidence <- build_duplicate_timestamp_evidence(
  source_evidence$raw_streams,
  source_evidence$silver_samples,
  context_observations
)
write_duplicate_timestamp_evidence(evidence, output_directory)

message(sprintf(
  paste0(
    "Read-only evidence extraction complete: activity=%s equal=%d decreasing=%d ",
    "runs=%d mismatches=%d reference_window=%s output=%s"
  ),
  activity_id,
  evidence$summary$equal_interval_count,
  evidence$summary$decreasing_interval_count,
  evidence$summary$equal_timestamp_run_count,
  evidence$summary$positional_mismatch_count,
  evidence$summary$reference_window_status,
  resolve_track_evidence_output_path(output_directory)
))
