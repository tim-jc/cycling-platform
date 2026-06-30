#' Update Google Health Heart Rate Responses
#'
#' Update existing Google Health raw heart-rate response rows.
#'
#' @param connection DBI connection object.
#' @param data_points Tibble of Google Health heart-rate responses to update.
#'
#' @return Integer count of updated rows.
update_google_health_data_points <- function(
  connection,
  data_points
) {
  if (nrow(data_points) == 0) {
    return(0L)
  }

  sql <- "
    UPDATE cycling_platform_raw.google_health_heart_rate_responses
    SET
      run_id = ?,
      retrieved_at = ?,
      dataset_interval = ?,
      heart_rate_payload = ?
    WHERE source_id = ?
      AND fitbit_user_id = ?
      AND activity_date = ?
      AND detail_level = ?
  "

  purrr::walk(
    seq_len(nrow(data_points)),
    \(i) {
      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = list(
          data_points$run_id[[i]],
          data_points$retrieved_at[[i]],
          data_points$dataset_interval[[i]],
          data_points$heart_rate_payload[[i]],
          data_points$source_id[[i]],
          data_points$fitbit_user_id[[i]],
          data_points$activity_date[[i]],
          data_points$detail_level[[i]]
        )
      )
    }
  )

  nrow(data_points)
}
