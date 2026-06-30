#' Insert Google Health Sleep Logs
#'
#' Insert new Google Health raw sleep logs.
#'
#' @param connection DBI connection object.
#' @param sleep_logs Tibble of Google Health sleep logs to insert.
#'
#' @return Number of rows inserted.
insert_google_health_sleep_logs <- function(
  connection,
  sleep_logs
) {
  if (nrow(sleep_logs) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "google_health_sleep_logs"
    ),
    value = sleep_logs,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(sleep_logs)
}
