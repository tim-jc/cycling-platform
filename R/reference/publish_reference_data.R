format_reference_planned_events_result <- function(result) {
  paste0(
    "planned_events: events inserted ", result$inserted_events,
    ", updated ", result$updated_events,
    ", unchanged ", result$unchanged_events,
    "; stages inserted ", result$inserted_stages,
    ", updated ", result$updated_stages,
    ", unchanged ", result$unchanged_stages,
    ", removed ", result$removed_stages
  )
}

publish_reference_data <- function(
  planned_events_publisher = run_planned_events_publication,
  log = message
) {
  log("Reference data publication starting.")

  # Platform-owned orchestration is deliberately explicit. Add each future
  # repository-owned Reference publisher here, preserving its own transaction
  # and reconciliation boundary.
  planned_events_result <- planned_events_publisher()
  log(format_reference_planned_events_result(planned_events_result))

  log("Reference data publication complete: 1 dataset published and validated.")

  invisible(list(planned_events = planned_events_result))
}
