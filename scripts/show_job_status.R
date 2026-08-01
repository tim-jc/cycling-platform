#!/usr/bin/env Rscript
source(file.path("R", "utils", "execution_context.R"))
source(file.path("R", "utils", "format_notification_helpers.R"))
source(file.path("R", "utils", "job_status.R"))

args <- commandArgs(trailingOnly = TRUE)
job_name <- if (length(args) > 0L) args[[1]] else "silver-full"
stale_after_seconds <- if (length(args) > 1L) as.numeric(args[[2]]) else 120
config <- yaml::read_yaml(file.path("config", "platform.yml"))
status_path <- file.path(config$logging$directory %||% "logs", "status", paste0(job_name, "-latest.json"))
result <- read_job_status(status_path)

if (!isTRUE(result$ok)) {
  message(result$error, " Expected: ", status_path)
  quit(save = "no", status = 1L)
}

status <- result$status
staleness <- job_status_staleness(status, stale_after_seconds = stale_after_seconds)
cat(format_job_status(status, staleness), "\n", sep = "")
