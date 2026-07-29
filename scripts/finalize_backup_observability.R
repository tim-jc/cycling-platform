#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)

if (length(args) != 9L) {
  stop(
    paste(
      "Usage: finalize_backup_observability.R",
      "<manifest.tsv> <inventory.tsv> <status_file> <backup_dir>",
      "<retention_days>",
      "<run_prefix> <started_epoch> <source_host> <backup_host>"
    ),
    call. = FALSE
  )
}

script_argument <- grep(
  "^--file=",
  commandArgs(trailingOnly = FALSE),
  value = TRUE
)

if (
  length(script_argument) > 0 &&
    !identical(sub("^--file=", "", script_argument[[1]]), "-")
) {
  script_path <- sub("^--file=", "", script_argument[[1]])
  project_dir <- dirname(dirname(normalizePath(script_path)))
  setwd(project_dir)
}

source("bootstrap.R")

manifest_path <- args[[1]]
inventory_path <- args[[2]]
status_file <- args[[3]]
backup_dir <- args[[4]]
retention_days <- as.integer(args[[5]])
run_prefix <- args[[6]]
started_epoch <- as.numeric(args[[7]])
source_host <- args[[8]]
backup_host <- args[[9]]

files <- utils::read.delim(
  manifest_path,
  colClasses = c(
    database_name = "character",
    filename = "character",
    compressed_bytes = "numeric",
    uncompressed_bytes = "numeric",
    verified_at = "character"
  ),
  check.names = FALSE,
  stringsAsFactors = FALSE
)

files$verified_at <- as.POSIXct(
  files$verified_at,
  format = "%Y-%m-%dT%H:%M:%SZ",
  tz = "UTC"
)

disk_files <- utils::read.delim(
  inventory_path,
  colClasses = c(
    filename = "character",
    modified_epoch = "numeric",
    compressed_bytes = "numeric"
  ),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
disk_files$modified_at <- as.POSIXct(
  disk_files$modified_epoch,
  origin = "1970-01-01",
  tz = "UTC"
)
disk_files$modified_epoch <- NULL

manifest <- list(
  started_at = as.POSIXct(
    started_epoch,
    origin = "1970-01-01",
    tz = "UTC"
  ),
  completed_at = Sys.time(),
  backup_host = backup_host,
  source_host = source_host,
  run_prefix = run_prefix,
  files = files
)

validate_backup_manifest(manifest)

# The local artefact remains useful even if the Admin metadata write fails.
write_backup_success_artifact(
  manifest = manifest,
  path = status_file
)

connection <- get_connection("cycling_platform_admin")

tryCatch(
  {
    ensure_backup_observability_tables(connection)

    backup_run_id <- record_successful_backup_run(
      connection = connection,
      manifest = manifest
    )

    reconciliation <- record_backup_reconciliation(
      connection = connection,
      backup_dir = backup_dir,
      backup_host = backup_host,
      retention_days = retention_days,
      disk_files = disk_files
    )

    message(
      "Recorded backup run ",
      backup_run_id,
      " and reconciliation status ",
      reconciliation$status,
      "."
    )
  },
  finally = {
    if (DBI::dbIsValid(connection)) {
      DBI::dbDisconnect(connection)
    }
  }
)
