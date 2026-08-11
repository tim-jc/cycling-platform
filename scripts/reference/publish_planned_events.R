#!/usr/bin/env Rscript
source("bootstrap.R")

result <- run_planned_events_publication()

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
