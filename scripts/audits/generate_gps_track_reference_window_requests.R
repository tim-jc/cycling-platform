#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || arguments[[1]] %in% c("-h", "--help")) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/generate_gps_track_reference_window_requests.R",
      "<request.csv>"
    ),
    call. = FALSE
  )
}

write_geographic_reference_window_requests(arguments[[1]])
message("Reference-window request written: ", normalizePath(arguments[[1]]))
