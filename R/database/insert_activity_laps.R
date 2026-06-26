#' Insert Activity Laps
#'
#' Insert new activity laps into the database.
#'
#' @param connection Database connection.
#' @param activity_laps Tibble of activity laps to insert.
#'
#' @return Number of rows inserted.
insert_activity_laps <- function(
  connection,
  activity_laps
) {
  if (nrow(activity_laps) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "activity_laps"
    ),
    value = activity_laps,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(activity_laps)
}
