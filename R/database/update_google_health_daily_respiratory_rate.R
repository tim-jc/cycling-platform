update_google_health_daily_respiratory_rate <- function(
  connection,
  daily_respiratory_rate
) {
  if (nrow(daily_respiratory_rate) == 0) {
    return(0L)
  }

  sql <- "
    UPDATE cycling_platform_raw.google_health_daily_respiratory_rate
    SET
      source_id = ?,
      google_health_user_id = ?,
      source_data_point_id = ?,
      activity_date = ?,
      respiratory_rate_brpm = ?,
      source_name = ?,
      source_ecosystem = ?,
      source_platform = ?,
      source_recording_method = ?,
      source_device_manufacturer = ?,
      source_device_model = ?,
      run_id = ?,
      retrieved_at = ?,
      daily_respiratory_rate_payload = ?
    WHERE daily_respiratory_rate_key = ?
  "

  purrr::walk(
    seq_len(nrow(daily_respiratory_rate)),
    \(i) {
      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = list(
          daily_respiratory_rate$source_id[[i]],
          daily_respiratory_rate$google_health_user_id[[i]],
          daily_respiratory_rate$source_data_point_id[[i]],
          daily_respiratory_rate$activity_date[[i]],
          daily_respiratory_rate$respiratory_rate_brpm[[i]],
          daily_respiratory_rate$source_name[[i]],
          daily_respiratory_rate$source_ecosystem[[i]],
          daily_respiratory_rate$source_platform[[i]],
          daily_respiratory_rate$source_recording_method[[i]],
          daily_respiratory_rate$source_device_manufacturer[[i]],
          daily_respiratory_rate$source_device_model[[i]],
          daily_respiratory_rate$run_id[[i]],
          daily_respiratory_rate$retrieved_at[[i]],
          daily_respiratory_rate$daily_respiratory_rate_payload[[i]],
          daily_respiratory_rate$daily_respiratory_rate_key[[i]]
        )
      )
    }
  )

  nrow(daily_respiratory_rate)
}
