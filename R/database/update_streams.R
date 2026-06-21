#' Update Streams
#'
#' Update existing streams.
#'
#' @param connection Database connection.
#' @param streams Tibble of streams to update.
#'
#' @return Integer count of updated rows.
update_streams <- function(
  connection,
  streams
) {
  if (nrow(streams) == 0) {
    return(0L)
  }

  sql <- "
    UPDATE cycling_platform_raw.activity_streams
    SET
      run_id = ?,
      source_id = ?,
      retrieved_at = ?,
      series_type = ?,
      original_size = ?,
      resolution = ?,
      stream_payload = ?
    WHERE activity_id = ?
      AND stream_type = ?
  "

  purrr::walk(
    seq_len(nrow(streams)),
    \(i) {
      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = list(
          streams$run_id[[i]],
          streams$source_id[[i]],
          streams$retrieved_at[[i]],

          streams$series_type[[i]],
          streams$original_size[[i]],
          streams$resolution[[i]],
          streams$stream_payload[[i]],

          streams$activity_id[[i]],
          streams$stream_type[[i]]
        )
      )
    }
  )

  nrow(streams)
}
