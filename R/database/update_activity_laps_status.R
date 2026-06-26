#' Update Activity Laps Status
#'
#' Update laps ingestion status for a set of activities.
#'
#' @param connection Database connection.
#' @param activity_ids Integer64 vector of activity IDs.
#' @param laps_status Laps status to apply.
#'
#' @return Number of rows updated.
update_activity_laps_status <- function(
  connection,
  activity_ids,
  laps_status
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
      laps_status = ?,
      laps_attempted_at = CURRENT_TIMESTAMP
    WHERE activity_id IN (",
    placeholders,
    ")
    "
  )

  DBI::dbExecute(
    conn = connection,
    statement = sql,
    params = c(
      list(laps_status),
      as.list(
        unname(activity_ids)
      )
    )
  )
}
