#!/usr/bin/env Rscript

source("bootstrap.R")

arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) != 1L || !arguments[[1L]] %in% c("preview", "apply")) {
  stop(paste(
    "Usage: Rscript scripts/operations/backfill_canonical_activity_identity.R",
    "<preview|apply>"
  ), call. = FALSE)
}

connection <- get_connection("cycling_platform_silver")
on.exit(if (DBI::dbIsValid(connection)) DBI::dbDisconnect(connection), add = TRUE)

result <- if (identical(arguments[[1L]], "preview")) {
  preview_canonical_activity_identity_backfill(connection)
} else {
  backfill_canonical_activity_identity(connection)
}
print(result, row.names = FALSE)
