#' Upsert Activity Details
#'
#' Insert new activity details and update existing activity details.
#'
#' @param connection DBI connection object.
#' @param activity_details Tibble returned by get_activity_details().
#'
#' @return Named list containing rows_inserted and rows_updated.
upsert_activity_details <- function(
  connection,
  activity_details
) {
  if (nrow(activity_details) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  existing_ids <- get_existing_activity_detail_ids(
    connection = connection,
    activity_ids = activity_details$activity_id
  )

  split_rows <- split_existing_rows(
    data = activity_details,
    existing_keys = existing_ids,
    key_columns = "activity_id"
  )

  activity_details_insert <- split_rows$to_insert

  activity_details_update <- split_rows$to_update

  rows_inserted <- 0L
  rows_updated <- 0L

  # Insert new activity details
  if (nrow(activity_details_insert) > 0) {
    rows_inserted <- insert_activity_details(
      connection = connection,
      activity_details = activity_details_insert
    )
  }

  # Update existing activity details
  if (nrow(activity_details_update) > 0) {
    rows_updated <- update_activity_details(
      connection = connection,
      activity_details = activity_details_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated
  )
}
