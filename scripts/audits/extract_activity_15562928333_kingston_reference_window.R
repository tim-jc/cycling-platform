#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || arguments %in% c("-h", "--help")) {
  stop(
    paste(
      "Usage: Rscript",
      "scripts/audits/extract_activity_15562928333_kingston_reference_window.R",
      "<output-directory>"
    ),
    call. = FALSE
  )
}

activity_id <- 15562928333
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

evidence <- build_governed_gps_reference_window(
  raw_streams = raw_streams,
  silver_samples = silver_samples,
  window_from_sample_index = 1448L,
  window_to_sample_index = 1477L,
  focus_from_sample_index = 1453L,
  focus_to_sample_index = 1472L,
  focus_segment_from_sample_index = 1471L,
  focus_segment_to_sample_index = 1472L,
  case_key = "KINGSTON_TUNNEL_GPS_DRIFT",
  evidence_note = paste(
    "Kingston tunnel GPS-loss and reacquisition review;",
    "samples 1453 through 1472 are the manually identified focus interval."
  )
)
write_governed_gps_reference_window(evidence, output_directory, repository_root = getwd())

message(sprintf(
  paste0(
    "Read-only Kingston reference extraction complete: activity=%s observations=%d ",
    "segments=%d mismatches=%d labels=%d output=%s"
  ),
  activity_id,
  nrow(evidence$reference_window_observations),
  nrow(evidence$reference_window_segments),
  evidence$reference_window_status$raw_silver_mismatch_count,
  nrow(evidence$manual_label_template),
  normalizePath(output_directory, mustWork = TRUE)
))
