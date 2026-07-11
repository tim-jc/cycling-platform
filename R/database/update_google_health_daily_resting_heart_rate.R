update_google_health_daily_resting_heart_rate <- function(
  connection,
  daily_resting_heart_rate
) {
  if (nrow(daily_resting_heart_rate) == 0) {
    return(0L)
  }

  sql <- "
    UPDATE cycling_platform_raw.google_health_daily_resting_heart_rate
    SET
      source_id = ?,
      google_health_user_id = ?,
      source_data_point_id = ?,
      activity_date = ?,
      resting_heart_rate_bpm = ?,
      calculation_method = ?,
      source_name = ?,
      run_id = ?,
      retrieved_at = ?,
      daily_resting_heart_rate_payload = ?
    WHERE daily_resting_heart_rate_key = ?
  "

  purrr::walk(
    seq_len(nrow(daily_resting_heart_rate)),
    \(i) {
      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = list(
          daily_resting_heart_rate$source_id[[i]],
          daily_resting_heart_rate$google_health_user_id[[i]],
          daily_resting_heart_rate$source_data_point_id[[i]],
          daily_resting_heart_rate$activity_date[[i]],
          daily_resting_heart_rate$resting_heart_rate_bpm[[i]],
          daily_resting_heart_rate$calculation_method[[i]],
          daily_resting_heart_rate$source_name[[i]],
          daily_resting_heart_rate$run_id[[i]],
          daily_resting_heart_rate$retrieved_at[[i]],
          daily_resting_heart_rate$daily_resting_heart_rate_payload[[i]],
          daily_resting_heart_rate$daily_resting_heart_rate_key[[i]]
        )
      )
    }
  )

  nrow(daily_resting_heart_rate)
}
