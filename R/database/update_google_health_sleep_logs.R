#' Update Google Health Sleep Logs
#'
#' Update existing Google Health raw sleep logs.
#'
#' @param connection DBI connection object.
#' @param sleep_logs Tibble of Google Health sleep logs to update.
#'
#' @return Integer count of updated rows.
update_google_health_sleep_logs <- function(
  connection,
  sleep_logs
) {
  if (nrow(sleep_logs) == 0) {
    return(0L)
  }

  sql <- "
    UPDATE cycling_platform_raw.google_health_sleep_logs
    SET
      source_log_id = ?,
      google_user_id = ?,
      run_id = ?,
      source_id = ?,
      retrieved_at = ?,
      source_name = ?,
      start_physical_time = ?,
      end_physical_time = ?,
      start_utc_offset = ?,
      end_utc_offset = ?,
      start_civil_date = ?,
      end_civil_date = ?,
      sleep_log_payload = ?
    WHERE sleep_log_key = ?
  "

  purrr::walk(
    seq_len(nrow(sleep_logs)),
    \(i) {
      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = list(
          sleep_logs$source_log_id[[i]],
          sleep_logs$google_user_id[[i]],
          sleep_logs$run_id[[i]],
          sleep_logs$source_id[[i]],
          sleep_logs$retrieved_at[[i]],
          sleep_logs$source_name[[i]],
          sleep_logs$start_physical_time[[i]],
          sleep_logs$end_physical_time[[i]],
          sleep_logs$start_utc_offset[[i]],
          sleep_logs$end_utc_offset[[i]],
          sleep_logs$start_civil_date[[i]],
          sleep_logs$end_civil_date[[i]],
          sleep_logs$sleep_log_payload[[i]],
          sleep_logs$sleep_log_key[[i]]
        )
      )
    }
  )

  nrow(sleep_logs)
}
