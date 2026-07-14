insert_google_health_daily_respiratory_rate <- function(
  connection,
  daily_respiratory_rate
) {
  if (nrow(daily_respiratory_rate) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "google_health_daily_respiratory_rate"
    ),
    value = daily_respiratory_rate,
    append = TRUE
  )

  nrow(daily_respiratory_rate)
}
