#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) || any(arguments %in% c("-h", "--help"))) {
  stop(
    "Usage: Rscript scripts/operations/preview_operational_conditions.R",
    call. = FALSE
  )
}

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
preview <- preview_operational_condition_evaluation(connection)

message(sprintf(
  "Read-only operational-condition preview: conditions=%d proposed_transitions=%d",
  nrow(preview), sum(preview$transition_event != "NONE")
))
print(preview, row.names = FALSE)
