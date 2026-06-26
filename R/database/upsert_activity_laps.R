#' Upsert Activity Laps
#'
#' Insert new activity laps and update existing activity laps.
#'
#' @param connection DBI connection object.
#' @param activity_laps Tibble returned by get_activity_laps().
#'
#' @return Named list containing rows_inserted and rows_updated.
upsert_activity_laps <- function(
  connection,
  activity_laps
) {
  if (nrow(activity_laps) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  existing_keys <- get_existing_activity_lap_keys(
    connection = connection,
    activity_ids = unique(activity_laps$activity_id)
  )

  split_rows <- split_existing_rows(
    data = activity_laps,
    existing_keys = existing_keys,
    key_columns = c(
      "activity_id",
      "lap_index"
    )
  )

  activity_laps_to_insert <- split_rows$to_insert

  activity_laps_to_update <- split_rows$to_update

  rows_inserted <- 0L
  rows_updated <- 0L

  if (nrow(activity_laps_to_insert) > 0) {
    rows_inserted <- insert_activity_laps(
      connection = connection,
      activity_laps = activity_laps_to_insert
    )
  }

  if (nrow(activity_laps_to_update) > 0) {
    rows_updated <- update_activity_laps(
      connection = connection,
      activity_laps = activity_laps_to_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated
  )
}
