#' Upsert Activities
#'
#' Insert new activities and update existing activities.
#'
#' @param connection DBI connection object.
#' @param activities Tibble returned by get_activities().
#'
#' @return Named list containing rows_inserted and rows_updated.
upsert_activities <- function(
  connection,
  activities,
  reconciliation = NULL
) {
  if (nrow(activities) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  if (!is.null(reconciliation)) {
    statuses <- stats::setNames(reconciliation$reconciliation_status, as.character(reconciliation$activity_id))
    activities <- activities[statuses[as.character(activities$activity_id)] %in% c("NEW", "CHANGED"), , drop = FALSE]
    if (nrow(activities) == 0) return(list(rows_inserted = 0L, rows_updated = 0L, rows_unchanged = sum(reconciliation$reconciliation_status == "UNCHANGED")))
  }

  # Get existing activity IDs
  existing_ids <- get_existing_activity_ids(
    connection = connection,
    activity_ids = activities$activity_id
  )

  split_rows <- split_existing_rows(
    data = activities,
    existing_keys = existing_ids,
    key_columns = "activity_id"
  )

  activities_insert <- split_rows$to_insert

  activities_update <- split_rows$to_update

  rows_inserted <- 0L
  rows_updated <- 0L

  # Insert new activities
  if (nrow(activities_insert) > 0) {
    rows_inserted <- insert_activities(
      connection = connection,
      activities = activities_insert
    )
  }

  # Update existing activities
  if (nrow(activities_update) > 0) {
    rows_updated <- update_activities(
      connection = connection,
      activities = activities_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated,
    rows_unchanged = if (is.null(reconciliation)) 0L else sum(reconciliation$reconciliation_status == "UNCHANGED")
  )
}
