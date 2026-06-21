#' Get Existing Activity IDs
#'
#' Function to return which of a given set of activity_ids is present in the database
#'
#' @param connection Database connection.
#' @param activity_ids Vector of activity IDs to check
#'
#' @return Vector of activity IDs present in the database
get_existing_activity_ids <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(numeric())
  }

  placeholders <- paste(
    rep("?", length(activity_ids)),
    collapse = ", "
  )

  sql <- paste0(
    "SELECT activity_id
     FROM cycling_platform_raw.activities
     WHERE activity_id IN (",
    placeholders,
    ")"
  )

  existing_activity_ids <- DBI::dbGetQuery(
    connection,
    sql,
    params = as.list(activity_ids)
  )$activity_id

  existing_activity_ids
}
