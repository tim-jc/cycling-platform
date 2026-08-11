#!/usr/bin/env Rscript
source("bootstrap.R")

events <- read_planned_events_dataset()
connection <- get_connection("cycling_platform_reference")
on.exit(DBI::dbDisconnect(connection), add = TRUE)

result <- publish_planned_events(connection, events)

message(
  "Reference planned-events publication complete: events inserted ",
  result$inserted_events,
  ", updated ", result$updated_events,
  ", unchanged ", result$unchanged_events,
  "; stages inserted ", result$inserted_stages,
  ", updated ", result$updated_stages,
  ", unchanged ", result$unchanged_stages,
  ", removed ", result$removed_stages,
  "."
)
