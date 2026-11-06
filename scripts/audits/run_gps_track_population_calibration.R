#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) < 1L || length(arguments) > 2L ||
    any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/run_gps_track_population_calibration.R",
      "<output-directory> [maximum-activities]"
    ),
    call. = FALSE
  )
}

output_directory <- normalizePath(arguments[[1]], mustWork = FALSE)
maximum_activities <- NULL
if (length(arguments) == 2L) {
  maximum_activities <- suppressWarnings(as.integer(arguments[[2]]))
  if (is.na(maximum_activities) || maximum_activities < 1L) {
    stop("maximum-activities must be a positive integer.", call. = FALSE)
  }
}

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)

candidates <- fetch_track_calibration_candidates(connection)
result <- run_geographic_population_calibration(
  connection, candidates, maximum_activities = maximum_activities
)
write_geographic_population_calibration_outputs(result, output_directory)

processed <- nrow(result$activity_execution)
message(sprintf(
  paste0(
    "Population calibration: eligible=%d processed=%d succeeded=%d failed=%d ",
    "samples=%d segments=%d maximum_activity_samples=%d elapsed=%.3fs output=%s"
  ),
  result$eligible_population_count, processed,
  sum(result$activity_execution$processing_status == "SUCCESS"),
  sum(result$activity_execution$processing_status != "SUCCESS"),
  result$sample_count, result$segment_count,
  result$maximum_activity_sample_count, result$elapsed_seconds, output_directory
))
if (!is.null(maximum_activities) && processed > 0L) {
  message(sprintf(
    "Linear full-population runtime estimate from this pilot: %.1fs (%d eligible / %d pilot activities).",
    result$elapsed_seconds * result$eligible_population_count / processed,
    result$eligible_population_count, processed
  ))
}
if (!result$complete) {
  stop("Population calibration is incomplete; inspect population_failures.csv.", call. = FALSE)
}
