#' Update Google Health Data Points
#'
#' Update existing Google Health raw data points.
#'
#' @param connection DBI connection object.
#' @param data_points Tibble of Google Health data points to update.
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
    UPDATE cycling_platform_raw.google_health_data_points
    SET
      data_type = ?,
      google_user_id = ?,
      run_id = ?,
      source_id = ?,
      retrieved_at = ?,
      source_name = ?,
      sample_physical_time = ?,
      sample_utc_offset = ?,
      sample_civil_date = ?,
      value_numeric = ?,
      value_name = ?,
      data_point_name = ?,
      data_point_payload = ?
    WHERE data_point_key = ?
  "

  purrr::walk(
    seq_len(nrow(data_points)),
    \(i) {
      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = list(
          data_points$data_type[[i]],
          data_points$google_user_id[[i]],
          data_points$run_id[[i]],
          data_points$source_id[[i]],
          data_points$retrieved_at[[i]],
          data_points$source_name[[i]],
          data_points$sample_physical_time[[i]],
          data_points$sample_utc_offset[[i]],
          data_points$sample_civil_date[[i]],
          data_points$value_numeric[[i]],
          data_points$value_name[[i]],
          data_points$data_point_name[[i]],
          data_points$data_point_payload[[i]],
          data_points$data_point_key[[i]]
        )
      )
    }
  )

  nrow(data_points)
}
