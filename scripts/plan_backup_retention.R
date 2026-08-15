#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2L) {
  stop("Usage: plan_backup_retention.R <backup_dir> <retention_days>", call. = FALSE)
}
source(file.path("R", "backup", "bootstrap_backup_runtime.R"))
backup_dir <- args[[1]]
retention_days <- as.integer(args[[2]])
if (is.na(retention_days) || retention_days < 1L) {
  stop("retention_days must be a positive integer.", call. = FALSE)
}
plan <- backup_retention_plan(
  scan_backup_directory(backup_dir),
  retention_days = retention_days
)
if (length(plan$delete_files)) writeLines(plan$delete_files)
