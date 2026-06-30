#' Upsert Google Health Sleep Logs
#'
#' Insert new Google Health raw sleep logs and update existing rows.
#'
#' @param connection DBI connection object.
#' @param sleep_logs Tibble returned by Google Health sleep API functions.
#'
#' @return Named list containing rows_inserted and rows_updated.
upsert_google_health_sleep_logs <- function(
  connection,
  sleep_logs
) {
  if (nrow(sleep_logs) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  existing_keys <- get_existing_google_health_sleep_log_keys(
    connection = connection,
    sleep_log_keys = unique(sleep_logs$sleep_log_key)
  )

  split_rows <- split_existing_rows(
    data = sleep_logs,
    existing_keys = existing_keys,
    key_columns = "sleep_log_key"
  )

  sleep_logs_to_insert <- split_rows$to_insert

  sleep_logs_to_update <- split_rows$to_update

  rows_inserted <- 0L
  rows_updated <- 0L

  if (nrow(sleep_logs_to_insert) > 0) {
    rows_inserted <- insert_google_health_sleep_logs(
      connection = connection,
      sleep_logs = sleep_logs_to_insert
    )
  }

  if (nrow(sleep_logs_to_update) > 0) {
    rows_updated <- update_google_health_sleep_logs(
      connection = connection,
      sleep_logs = sleep_logs_to_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated
  )
}
