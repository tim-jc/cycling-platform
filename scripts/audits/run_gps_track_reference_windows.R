#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 2L || any(arguments %in% c("-h", "--help"))) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/run_gps_track_reference_windows.R",
      "<request.csv> <output-directory>"
    ),
    call. = FALSE
  )
}

request_path <- normalizePath(arguments[[1]], mustWork = TRUE)
output_directory <- normalizePath(arguments[[2]], mustWork = FALSE)
requests <- utils::read.csv(
  request_path, colClasses = c(activity_id = "character"),
  stringsAsFactors = FALSE, na.strings = c("", "NA")
)

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)

result <- extract_geographic_reference_windows(connection, requests)
write_geographic_reference_window_outputs(result, output_directory)
message(sprintf(
  "Reference windows: activities=%d success=%d not_located=%d failed=%d output=%s",
  nrow(result$status), sum(result$status$extraction_status == "SUCCESS"),
  sum(result$status$extraction_status == "WINDOW_NOT_LOCATED"),
  sum(result$status$extraction_status == "FAILED"), output_directory
))
if (any(result$status$extraction_status == "FAILED")) {
  stop("One or more reference-window activities failed; inspect reference_window_status.csv.", call. = FALSE)
}
