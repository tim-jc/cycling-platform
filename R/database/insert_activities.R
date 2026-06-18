#' Insert Activities
#'
#' Function to insert new activities into the database
#'
#' @param connection Database connection.
#' @param activities Tibble of activities to insert.
#'
#' @return Number of rows inserted.
insert_activities <- function(
  connection,
  activities
) {
  if (nrow(activities) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = "activities",
    value = activities,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(activities)
}
