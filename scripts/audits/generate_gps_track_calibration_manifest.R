#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || arguments[[1]] %in% c("-h", "--help")) {
  stop(
    paste(
      "Usage: Rscript scripts/audits/generate_gps_track_calibration_manifest.R",
      "<local-manifest.csv>\nThe destination must not already exist."
    ),
    call. = FALSE
  )
}

destination <- normalizePath(dirname(arguments[[1]]), mustWork = FALSE)
manifest_path <- file.path(destination, basename(arguments[[1]]))
connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)

started <- proc.time()[["elapsed"]]
candidates <- fetch_track_calibration_candidates(connection)
manifest <- select_track_calibration_manifest(candidates)
write_track_calibration_manifest(manifest, manifest_path)

message(sprintf(
  paste0(
    "Calibration manifest written: path=%s selected=%d eligible_population=%d ",
    "cutoff_utc=%s elapsed=%.3fs"
  ),
  manifest_path, nrow(manifest), unique(manifest$eligible_population_count),
  TRACK_CALIBRATION_CUTOFF_UTC, proc.time()[["elapsed"]] - started
))
if (nrow(manifest) < TRACK_CALIBRATION_TARGET_SIZE) {
  warning(
    sprintf(
      "Eligible population contained only %d activities; the manifest is shorter than the target of %d.",
      nrow(manifest), TRACK_CALIBRATION_TARGET_SIZE
    ),
    call. = FALSE
  )
}
