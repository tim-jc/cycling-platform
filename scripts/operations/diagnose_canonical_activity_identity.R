#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) || any(arguments %in% c("-h", "--help"))) {
  stop(
    "Usage: Rscript scripts/operations/diagnose_canonical_activity_identity.R",
    call. = FALSE
  )
}

connection <- get_connection("cycling_platform_silver")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)
print(read_canonical_activity_identity_integrity(connection), row.names = FALSE)
