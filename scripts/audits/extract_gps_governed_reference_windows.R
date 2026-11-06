#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L || any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/extract_gps_governed_reference_windows.R",
      "<request.csv> <output-directory>"
    ),
    call. = FALSE
  )
}

requests <- read_governed_gps_reference_window_requests(arguments[[1L]])
output_directory <- arguments[[2L]]
validate_governed_gps_reference_window_destinations(
  requests$case_key, output_directory
)

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
results <- extract_governed_gps_reference_window_requests(connection, requests)
write_governed_gps_reference_window_requests(results, output_directory)

message(sprintf(
  "Governed Raw/Silver windows complete: requests=%d activities=%d output=%s",
  nrow(requests), length(unique(requests$activity_id)),
  resolve_track_evidence_output_path(output_directory)
))
