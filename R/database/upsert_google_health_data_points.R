#' Upsert Google Health Data Points
#'
#' Insert new Google Health raw data points and update existing rows.
#'
#' @param connection DBI connection object.
#' @param data_points Tibble returned by Google Health API functions.
#'
#' @return Named list containing rows_inserted and rows_updated.
upsert_google_health_data_points <- function(
  connection,
  data_points
) {
  if (nrow(data_points) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  existing_keys <- get_existing_google_health_data_point_keys(
    connection = connection,
    data_point_keys = unique(data_points$data_point_key)
  )

  split_rows <- split_existing_rows(
    data = data_points,
    existing_keys = existing_keys,
    key_columns = "data_point_key"
  )

  data_points_to_insert <- split_rows$to_insert

  data_points_to_update <- split_rows$to_update

  rows_inserted <- 0L
  rows_updated <- 0L

  if (nrow(data_points_to_insert) > 0) {
    rows_inserted <- insert_google_health_data_points(
      connection = connection,
      data_points = data_points_to_insert
    )
  }

  if (nrow(data_points_to_update) > 0) {
    rows_updated <- update_google_health_data_points(
      connection = connection,
      data_points = data_points_to_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated
  )
}
