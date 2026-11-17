#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) || any(arguments %in% c("-h", "--help"))) {
  stop(
    "Usage: Rscript scripts/operations/diagnose_canonical_activity_identity.R",
    call. = FALSE
  )
}

result <- with_canonical_activity_identity_connection(
  read_canonical_activity_identity_integrity
)
print(result, row.names = FALSE)
