upsert_google_health_daily_heart_rate_variability <- function(
  connection,
  daily_heart_rate_variability
) {
  if (nrow(daily_heart_rate_variability) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  existing_keys <- get_existing_google_health_daily_heart_rate_variability_keys(
    connection = connection,
    daily_heart_rate_variability_keys = unique(
      daily_heart_rate_variability$daily_heart_rate_variability_key
    )
  )

  split_rows <- split_existing_rows(
    data = daily_heart_rate_variability,
    existing_keys = existing_keys,
    key_columns = "daily_heart_rate_variability_key"
  )

  rows_inserted <- 0L
  rows_updated <- 0L

  if (nrow(split_rows$to_insert) > 0) {
    rows_inserted <- insert_google_health_daily_heart_rate_variability(
      connection = connection,
      daily_heart_rate_variability = split_rows$to_insert
    )
  }

  if (nrow(split_rows$to_update) > 0) {
    rows_updated <- update_google_health_daily_heart_rate_variability(
      connection = connection,
      daily_heart_rate_variability = split_rows$to_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated
  )
}
