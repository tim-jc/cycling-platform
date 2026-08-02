normalise_database_count <- function(value) {
  if (bit64::is.integer64(value)) {
    return(as.numeric(as.character(value)))
  }
  as.numeric(value)
}

format_activity_reconciliation_summary <- function(reconciliation) {
  if (nrow(reconciliation) == 0L) return(character())

  reconciliation <- normalise_activity_reconciliation_counts(reconciliation)

  totals <- stats::setNames(rep(0, 4L), c("NEW", "CHANGED", "UNCHANGED", "MISSING"))
  grouped <- stats::aggregate(activity_count ~ reconciliation_status, reconciliation, sum)
  totals[grouped$reconciliation_status] <- grouped$activity_count
  count_text <- function(value) format(value, scientific = FALSE, trim = TRUE)

  c(
    glue::glue(
      "Reconciliation: examined {count_text(sum(reconciliation$activity_count[reconciliation$reconciliation_status != 'MISSING']))}",
      " · new/recovered {count_text(totals[['NEW']])}",
      " · changed {count_text(totals[['CHANGED']])}",
      " · unchanged {count_text(totals[['UNCHANGED']])}",
      " · missing from source {count_text(totals[['MISSING']])}"
    ),
    glue::glue(
      "Selective repairs requested: details {count_text(sum(reconciliation$details_repair_required))}",
      " · streams {count_text(sum(reconciliation$streams_repair_required))}",
      " · laps {count_text(sum(reconciliation$laps_repair_required))}"
    )
  )
}

normalise_activity_reconciliation_counts <- function(reconciliation) {
  count_columns <- c(
    "activity_count",
    "details_repair_required",
    "streams_repair_required",
    "laps_repair_required"
  )
  reconciliation[count_columns] <- lapply(
    reconciliation[count_columns],
    normalise_database_count
  )
  reconciliation
}
