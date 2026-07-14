upsert_google_health_daily_respiratory_rate <- function(
  connection,
  daily_respiratory_rate
) {
  if (nrow(daily_respiratory_rate) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  existing_keys <- get_existing_google_health_daily_respiratory_rate_keys(
    connection = connection,
    daily_respiratory_rate_keys = unique(
      daily_respiratory_rate$daily_respiratory_rate_key
    )
  )

  split_rows <- split_existing_rows(
    data = daily_respiratory_rate,
    existing_keys = existing_keys,
    key_columns = "daily_respiratory_rate_key"
  )

  rows_inserted <- 0L
  rows_updated <- 0L

  if (nrow(split_rows$to_insert) > 0) {
    rows_inserted <- insert_google_health_daily_respiratory_rate(
      connection = connection,
      daily_respiratory_rate = split_rows$to_insert
    )
  }

  if (nrow(split_rows$to_update) > 0) {
    rows_updated <- update_google_health_daily_respiratory_rate(
      connection = connection,
      daily_respiratory_rate = split_rows$to_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated
  )
}
