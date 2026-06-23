#' Update Activity Details Status
#'
#' Update details ingestion status for a set of activities.
#'
#' @param connection Database connection.
#' @param activity_ids Integer64 vector of activity IDs.
#' @param details_status Details status to apply.
#'
#' @return Number of rows updated.
update_activity_details_status <- function(
  connection,
  activity_ids,
  details_status
) {
  if (length(activity_ids) == 0) {
    return(0L)
  }

  placeholders <- paste(
    rep("?", length(activity_ids)),
    collapse = ", "
  )

  sql <- paste0(
    "
    UPDATE cycling_platform_raw.activities
    SET
      details_status = ?,
      details_attempted_at = CURRENT_TIMESTAMP
    WHERE activity_id IN (",
    placeholders,
    ")
    "
  )

  DBI::dbExecute(
    conn = connection,
    statement = sql,
    params = c(
      list(details_status),
      as.list(
        unname(activity_ids)
      )
    )
  )
}
