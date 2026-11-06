#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (!length(arguments) %in% c(2L, 3L, 5L) ||
    any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/extract_gps_extreme_segments.R",
      paste(
        "<activity-id> <output-directory> [context-observations",
        "[displacement-case-key speed-case-key]]"
      )
    ),
    call. = FALSE
  )
}

activity_id <- validate_gps_investigation_activity_id(arguments[[1L]])
output_directory <- arguments[[2L]]
context_observations <- if (length(arguments) >= 3L) {
  suppressWarnings(as.integer(arguments[[3L]]))
} else {
  5L
}
case_keys <- if (length(arguments) == 5L) {
  arguments[4:5]
} else {
  c("LARGEST_DISPLACEMENT", "HIGHEST_IMPLIED_SPEED")
}
if (is.na(context_observations) || context_observations < 0L) {
  stop("context-observations must be a non-negative integer.", call. = FALSE)
}
validate_track_evidence_output_destination(
  output_directory, unname(gps_extreme_segment_evidence_filenames())
)

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
source_evidence <- fetch_gps_raw_silver_evidence(connection, activity_id)
evidence <- build_gps_extreme_segment_evidence(
  source_evidence$raw_streams,
  source_evidence$silver_samples,
  context_observations,
  case_keys
)
write_gps_extreme_segment_evidence(evidence, output_directory)

message(sprintf(
  "Read-only extraction complete: activity=%s candidates=%d mismatches=%d output=%s",
  activity_id,
  evidence$extraction_summary$candidate_count,
  evidence$extraction_summary$raw_silver_mismatch_count,
  resolve_track_evidence_output_path(output_directory)
))
