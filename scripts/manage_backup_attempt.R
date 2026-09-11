#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 1L || !args[[1]] %in% c("start", "fail")) {
  stop("Usage: manage_backup_attempt.R start|fail ...", call. = FALSE)
}

script_argument <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
if (length(script_argument) > 0L) {
  script_path <- sub("^--file=", "", script_argument[[1]])
  setwd(dirname(dirname(normalizePath(script_path))))
}
source(file.path("R", "backup", "bootstrap_backup_runtime.R"))

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
ensure_backup_observability_tables(connection)

if (identical(args[[1]], "start")) {
  if (length(args) != 6L) stop("Backup attempt start requires five arguments.", call. = FALSE)
  attempt_id <- create_backup_attempt(
    connection = connection,
    backup_host = args[[2]],
    source_host = args[[3]],
    run_prefix = args[[4]],
    started_at = as.POSIXct(as.numeric(args[[5]]), origin = "1970-01-01", tz = "UTC")
  )
  writeLines(as.character(attempt_id), args[[6]])
} else {
  if (length(args) != 9L) stop("Backup attempt failure requires eight arguments.", call. = FALSE)
  integer_or_na <- function(value) if (!nzchar(value)) NA_integer_ else as.integer(value)
  verified_count <- integer_or_na(args[[8]])
  if (is.na(verified_count)) verified_count <- 0L
  finish_backup_attempt_failure(
    connection = connection,
    backup_attempt_id = bit64::as.integer64(args[[2]]),
    failure_class = args[[3]],
    failing_database = args[[4]],
    failing_operation = args[[5]],
    final_attempt_number = integer_or_na(args[[6]]),
    max_attempts = integer_or_na(args[[7]]),
    partial_verified_file_count = verified_count,
    failure_summary = args[[9]]
  )
}
