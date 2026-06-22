#' Insert Activity Details
#'
#' Function to insert new activity_details into the database
#'
#' @param connection Database connection.
#' @param activity_details Tibble of activity details to insert.
#'
#' @return Number of rows inserted.
insert_activity_details <- function(
  connection,
  activity_details
) {
  if (nrow(activity_details) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "activity_details"
    ),
    value = activity_details,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(activity_details)
}
