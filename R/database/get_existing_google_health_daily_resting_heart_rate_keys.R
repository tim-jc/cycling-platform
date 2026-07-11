get_existing_google_health_daily_resting_heart_rate_keys <- function(
  connection,
  daily_resting_heart_rate_keys
) {
  if (length(daily_resting_heart_rate_keys) == 0) {
    return(
      tibble::tibble(
        daily_resting_heart_rate_key = character()
      )
    )
  }

  placeholders <- paste(
    rep("?", length(daily_resting_heart_rate_keys)),
    collapse = ", "
  )

  sql <- paste0(
    "SELECT daily_resting_heart_rate_key
     FROM cycling_platform_raw.google_health_daily_resting_heart_rate
     WHERE daily_resting_heart_rate_key IN (",
    placeholders,
    ")"
  )

  DBI::dbGetQuery(
    connection,
    sql,
    params = as.list(
      unname(daily_resting_heart_rate_keys)
    )
  ) |>
    dplyr::mutate(
      daily_resting_heart_rate_key = as.character(daily_resting_heart_rate_key)
    )
}
