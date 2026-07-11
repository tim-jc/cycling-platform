insert_google_health_daily_resting_heart_rate <- function(
  connection,
  daily_resting_heart_rate
) {
  if (nrow(daily_resting_heart_rate) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "google_health_daily_resting_heart_rate"
    ),
    value = daily_resting_heart_rate,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(daily_resting_heart_rate)
}
