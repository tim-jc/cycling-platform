#' Insert Google Health Data Points
#'
#' Insert new Google Health raw data points.
#'
#' @param connection DBI connection object.
#' @param data_points Tibble of Google Health data points to insert.
#'
#' @return Number of rows inserted.
insert_google_health_data_points <- function(
  connection,
  data_points
) {
  if (nrow(data_points) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "google_health_data_points"
    ),
    value = data_points,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(data_points)
}
