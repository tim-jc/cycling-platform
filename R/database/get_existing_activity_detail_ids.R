#' Get Existing Activity Detail IDs
#'
#' Return activity IDs already present in raw activity details.
#'
#' @param connection Database connection.
#' @param activity_ids Vector of activity IDs to check.
#'
#' @return Vector of activity IDs present in raw activity details.
get_existing_activity_detail_ids <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(bit64::integer64())
  }

  placeholders <- paste(
    rep("?", length(activity_ids)),
    collapse = ", "
  )

  sql <- paste0(
    "SELECT activity_id
     FROM cycling_platform_raw.activity_details
     WHERE activity_id IN (",
    placeholders,
    ")"
  )

  DBI::dbGetQuery(
    connection,
    sql,
    params = as.list(
      unname(activity_ids)
    )
  )$activity_id
}
