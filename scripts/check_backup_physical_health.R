#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3L || length(args) > 4L) {
  stop(
    "Usage: check_backup_physical_health.R <status_file> <stale_hours> <critical_hours> [now_epoch]",
    call. = FALSE
  )
}
source("bootstrap.R")
status_file <- args[[1]]
stale_hours <- as.numeric(args[[2]])
critical_hours <- as.numeric(args[[3]])
now <- if (length(args) == 4L) {
  as.POSIXct(as.numeric(args[[4]]), origin = "1970-01-01", tz = "UTC")
} else {
  Sys.time()
}
read_result <- read_backup_success_artifact(status_file)
if (!identical(read_result$status, "VALID")) {
  cat(read_result$status, "NA", "none", sep = "\t")
  cat("\n")
  quit(status = 0L)
}
artifact <- read_result$artifact
if (!backup_success_artifact_files_available(artifact, status_file)) {
  cat("INCOMPLETE", "NA", artifact$run_prefix, sep = "\t")
  cat("\n")
  quit(status = 0L)
}
completed_at <- as.POSIXct(
  artifact$completed_at,
  format = "%Y-%m-%dT%H:%M:%SZ",
  tz = "UTC"
)
freshness <- backup_freshness_status(
  completed_at,
  now = now,
  stale_hours = stale_hours,
  critical_hours = critical_hours
)
cat(
  freshness$status,
  sprintf("%.1f", freshness$age_hours),
  artifact$run_prefix,
  sep = "\t"
)
cat("\n")
