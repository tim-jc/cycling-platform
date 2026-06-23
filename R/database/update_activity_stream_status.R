#' Update Activity Stream Status
#'
#' Update stream ingestion status for a set of activities.
#'
#' @param connection Database connection.
#' @param activity_ids Integer64 vector of activity IDs.
#' @param stream_status Stream status to apply.
#'
#' @return Number of rows updated.
update_activity_stream_status <- function(
  connection,
  activity_ids,
  stream_status
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
      stream_status = ?,
      stream_attempted_at = CURRENT_TIMESTAMP
    WHERE activity_id IN (",
    placeholders,
    ")
    "
  )

  DBI::dbExecute(
    conn = connection,
    statement = sql,
    params = c(
      list(stream_status),
      as.list(
        unname(activity_ids)
      )
    )
  )
}
