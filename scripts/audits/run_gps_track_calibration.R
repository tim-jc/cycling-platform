#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L || any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/run_gps_track_calibration.R",
      "<manifest.csv> <output-directory>"
    ),
    call. = FALSE
  )
}

manifest_path <- normalizePath(arguments[[1]], mustWork = TRUE)
output_directory <- normalizePath(arguments[[2]], mustWork = FALSE)
manifest <- read_track_calibration_manifest(manifest_path)

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)

sample_order <- order(manifest$gps_sample_count, manifest$deterministic_rank)
ordinary_index <- sample_order[[ceiling(length(sample_order) / 2)]]
explain_ids <- unique(c(
  manifest$activity_id[[ordinary_index]],
  manifest$activity_id[[which.max(manifest$gps_sample_count)]]
))
for (activity_id in explain_ids) {
  message("Read-only query plan for activity ", activity_id, ":")
  plan <- DBI::dbGetQuery(
    connection,
    paste0(
      "EXPLAIN SELECT activity_id, sample_index, latitude, longitude, time_seconds, ",
      "distance_metres FROM cycling_platform_silver.activity_streams ",
      "WHERE activity_id = ? ORDER BY sample_index"
    ),
    params = list(activity_id)
  )
  print(plan, row.names = FALSE)
}

result <- run_track_calibration(connection, manifest)
write_track_calibration_outputs(result, manifest, output_directory)
message(sprintf(
  paste0(
    "Calibration complete: requested=%d succeeded=%d failed=%d elapsed=%.3fs ",
    "total_sample_rows=%d maximum_activity_samples=%d output=%s"
  ),
  nrow(manifest), sum(result$activity_summary$processing_status == "SUCCESS"),
  length(result$failed_activity_ids), result$elapsed_seconds,
  result$total_sample_rows_processed, result$maximum_activity_sample_count,
  output_directory
))
if (!result$complete) {
  stop(
    "Calibration output is incomplete; failed activity ID(s): ",
    paste(result$failed_activity_ids, collapse = ", "),
    call. = FALSE
  )
}
