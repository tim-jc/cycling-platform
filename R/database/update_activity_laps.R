#' Update Activity Laps
#'
#' Update existing activity laps.
#'
#' @param connection Database connection.
#' @param activity_laps Tibble of activity laps to update.
#'
#' @return Integer count of updated rows.
update_activity_laps <- function(
  connection,
  activity_laps
) {
  if (nrow(activity_laps) == 0) {
    return(0L)
  }

  sql <- "
    UPDATE cycling_platform_raw.activity_laps
    SET
      run_id = ?,
      source_id = ?,
      retrieved_at = ?,
      lap_payload = ?
    WHERE activity_id = ?
      AND lap_index = ?
  "

  purrr::walk(
    seq_len(nrow(activity_laps)),
    \(i) {
      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = list(
          activity_laps$run_id[[i]],
          activity_laps$source_id[[i]],
          activity_laps$retrieved_at[[i]],
          activity_laps$lap_payload[[i]],
          activity_laps$activity_id[[i]],
          activity_laps$lap_index[[i]]
        )
      )
    }
  )

  nrow(activity_laps)
}
