update_google_health_daily_heart_rate_variability <- function(
  connection,
  daily_heart_rate_variability
) {
  if (nrow(daily_heart_rate_variability) == 0) {
    return(0L)
  }

  sql <- "
    UPDATE cycling_platform_raw.google_health_daily_heart_rate_variability
    SET
      source_id = ?,
      google_health_user_id = ?,
      source_data_point_id = ?,
      activity_date = ?,
      average_hrv_milliseconds = ?,
      deep_sleep_rmssd_milliseconds = ?,
      non_rem_heart_rate_bpm = ?,
      entropy = ?,
      source_name = ?,
      source_ecosystem = ?,
      source_platform = ?,
      source_recording_method = ?,
      source_device_manufacturer = ?,
      source_device_model = ?,
      run_id = ?,
      retrieved_at = ?,
      daily_heart_rate_variability_payload = ?
    WHERE daily_heart_rate_variability_key = ?
  "

  purrr::walk(
    seq_len(nrow(daily_heart_rate_variability)),
    \(i) {
      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = list(
          daily_heart_rate_variability$source_id[[i]],
          daily_heart_rate_variability$google_health_user_id[[i]],
          daily_heart_rate_variability$source_data_point_id[[i]],
          daily_heart_rate_variability$activity_date[[i]],
          daily_heart_rate_variability$average_hrv_milliseconds[[i]],
          daily_heart_rate_variability$deep_sleep_rmssd_milliseconds[[i]],
          daily_heart_rate_variability$non_rem_heart_rate_bpm[[i]],
          daily_heart_rate_variability$entropy[[i]],
          daily_heart_rate_variability$source_name[[i]],
          daily_heart_rate_variability$source_ecosystem[[i]],
          daily_heart_rate_variability$source_platform[[i]],
          daily_heart_rate_variability$source_recording_method[[i]],
          daily_heart_rate_variability$source_device_manufacturer[[i]],
          daily_heart_rate_variability$source_device_model[[i]],
          daily_heart_rate_variability$run_id[[i]],
          daily_heart_rate_variability$retrieved_at[[i]],
          daily_heart_rate_variability$daily_heart_rate_variability_payload[[i]],
          daily_heart_rate_variability$daily_heart_rate_variability_key[[i]]
        )
      )
    }
  )

  nrow(daily_heart_rate_variability)
}
