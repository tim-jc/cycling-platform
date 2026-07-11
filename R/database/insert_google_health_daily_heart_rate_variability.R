insert_google_health_daily_heart_rate_variability <- function(
  connection,
  daily_heart_rate_variability
) {
  if (nrow(daily_heart_rate_variability) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "google_health_daily_heart_rate_variability"
    ),
    value = daily_heart_rate_variability,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(daily_heart_rate_variability)
}
