#!/usr/bin/env Rscript
source("bootstrap.R")

events <- read_planned_events_dataset()
connection <- get_connection("cycling_platform_reference")
on.exit(DBI::dbDisconnect(connection), add = TRUE)

result <- validate_planned_events_publication(connection, events)
if (!result$passed) {
  print(result$findings, row.names = FALSE)
  stop("Reference planned-events publication validation failed.", call. = FALSE)
}

message(
  "Reference planned-events publication validation passed for ",
  length(events),
  " event file(s)."
)
