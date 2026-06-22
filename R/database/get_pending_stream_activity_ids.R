#' Get Pending Stream Activity IDs
#'
#' Return activity IDs requiring stream ingestion.
#'
#' @param connection Database connection.
#'
#' @return Integer64 vector of activity IDs.
get_pending_stream_activity_ids <- function(
  connection
) {
  sql <- "
    SELECT activity_id
    FROM cycling_platform_raw.activities
    WHERE stream_status IN (
      'PENDING',
      'FAILED'
    )
  "

  DBI::dbGetQuery(
    conn = connection,
    statement = sql
  )$activity_id
}
