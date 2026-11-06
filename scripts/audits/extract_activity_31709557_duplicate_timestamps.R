#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || arguments %in% c("-h", "--help")) {
  stop(
    "Usage: Rscript scripts/audits/extract_activity_31709557_duplicate_timestamps.R <output-directory>",
    call. = FALSE
  )
}

activity_id <- 31709557
output_directory <- arguments[[1L]]

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)

raw_streams <- DBI::dbGetQuery(
  connection,
  paste(
    "SELECT activity_id, stream_type, original_size, stream_payload",
    "FROM cycling_platform_raw.activity_streams",
    "WHERE activity_id = ? AND stream_type IN ('time', 'latlng', 'distance')",
    "ORDER BY stream_type"
  ),
  params = list(activity_id)
)
silver_samples <- DBI::dbGetQuery(
  connection,
  paste(
    "SELECT activity_id, sample_index, time_seconds, latitude, longitude, distance_metres",
    "FROM cycling_platform_silver.activity_streams",
    "WHERE activity_id = ?",
    "ORDER BY sample_index"
  ),
  params = list(activity_id)
)

evidence <- build_duplicate_timestamp_evidence(raw_streams, silver_samples, context_observations = 5L)
write_duplicate_timestamp_evidence(evidence, output_directory, repository_root = getwd())

message(sprintf(
  paste0(
    "Read-only evidence extraction complete: activity=%d equal=%d decreasing=%d ",
    "runs=%d mismatches=%d reference_window=%s output=%s"
  ),
  activity_id,
  evidence$summary$equal_interval_count,
  evidence$summary$decreasing_interval_count,
  evidence$summary$equal_timestamp_run_count,
  evidence$summary$positional_mismatch_count,
  evidence$summary$reference_window_status,
  normalizePath(output_directory, mustWork = TRUE)
))
