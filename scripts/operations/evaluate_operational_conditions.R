#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) || any(arguments %in% c("-h", "--help"))) {
  stop(
    "Usage: Rscript scripts/operations/evaluate_operational_conditions.R",
    call. = FALSE
  )
}

connection <- get_connection("cycling_platform_admin")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
result <- evaluate_operational_conditions(connection)

message(sprintf(
  "Operational conditions evaluated: conditions=%d transitions=%d",
  nrow(result), sum(result$transition_event != "NONE")
))
print(result, row.names = FALSE)
