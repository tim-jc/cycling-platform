#' Get Pending Lap Activity IDs
#'
#' Return activity IDs requiring lap ingestion.
#'
#' @param connection Database connection.
#'
#' @return Integer64 vector of activity IDs.
get_pending_lap_activity_ids <- function(
  connection
) {
  sql <- "
    SELECT activity_id
    FROM cycling_platform_raw.activities
    WHERE laps_status IN (
      'PENDING',
      'FAILED'
    )
    ORDER BY activity_id
  "

  result <- DBI::dbGetQuery(
    conn = connection,
    statement = sql
  )

  if (nrow(result) == 0) {
    return(bit64::integer64())
  }

  bit64::as.integer64(
    result$activity_id
  )
}
