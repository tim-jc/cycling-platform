get_existing_google_health_daily_heart_rate_variability_keys <- function(
  connection,
  daily_heart_rate_variability_keys
) {
  if (length(daily_heart_rate_variability_keys) == 0) {
    return(
      tibble::tibble(
        daily_heart_rate_variability_key = character()
      )
    )
  }

  placeholders <- paste(
    rep("?", length(daily_heart_rate_variability_keys)),
    collapse = ", "
  )

  sql <- paste0(
    "SELECT daily_heart_rate_variability_key
     FROM cycling_platform_raw.google_health_daily_heart_rate_variability
     WHERE daily_heart_rate_variability_key IN (",
    placeholders,
    ")"
  )

  DBI::dbGetQuery(
    connection,
    sql,
    params = as.list(
      unname(daily_heart_rate_variability_keys)
    )
  ) |>
    dplyr::mutate(
      daily_heart_rate_variability_key = as.character(
        daily_heart_rate_variability_key
      )
    )
}
