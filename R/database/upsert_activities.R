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
  activities
) {
  if (nrow(activities) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  # Get existing activity IDs
  existing_ids <- get_existing_activity_ids(
    connection = connection,
    activity_ids = activities$activity_id
  )

  # Split incoming data
  activities_insert <- dplyr::filter(
    activities,
    !activity_id %in% existing_ids
  )

  activities_update <- dplyr::filter(
    activities,
    activity_id %in% existing_ids
  )

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
    rows_updated = rows_updated
  )
}
