#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 4L || any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/extract_gps_qualification_batch1.R",
      "<request.csv> <diagnostic-segments.csv> <activity-manifest.csv>",
      "<output-directory>"
    ),
    call. = FALSE
  )
}

request_path <- normalizePath(arguments[[1L]], mustWork = TRUE)
diagnostic_path <- normalizePath(arguments[[2L]], mustWork = TRUE)
activity_manifest_path <- normalizePath(arguments[[3L]], mustWork = TRUE)
output_directory <- arguments[[4L]]

requests <- read_governed_gps_reference_window_requests(request_path)
diagnostic_segments <- utils::read.csv(
  diagnostic_path,
  colClasses = c(activity_id = "character"),
  stringsAsFactors = FALSE
)
activity_manifest <- utils::read.csv(
  activity_manifest_path,
  colClasses = c(activity_id = "character"),
  stringsAsFactors = FALSE
)
requests <- validate_gps_qualification_batch_requests(
  requests, diagnostic_segments, activity_manifest
)

# The complete batch is checked before opening the read-only source connection.
validate_gps_qualification_batch_destinations(requests, output_directory)

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
results <- extract_gps_qualification_batch(connection, requests)

repository_commit_sha <- system2(
  "git", c("rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE
)[[1L]]
write_gps_qualification_batch(
  results = results,
  requests = requests,
  output_directory = output_directory,
  request_path = request_path,
  diagnostic_path = diagnostic_path,
  activity_manifest_path = activity_manifest_path,
  repository_commit_sha = repository_commit_sha
)

message(sprintf(
  "GPS qualification Batch 1 complete: cases=%d activities=%d output=%s",
  nrow(requests), length(unique(requests$activity_id)),
  resolve_track_evidence_output_path(output_directory)
))
