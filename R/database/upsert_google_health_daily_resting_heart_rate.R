upsert_google_health_daily_resting_heart_rate <- function(
  connection,
  daily_resting_heart_rate,
  get_existing = get_existing_google_health_daily_resting_heart_rate_keys,
  insert_rows = insert_google_health_daily_resting_heart_rate,
  update_rows = update_google_health_daily_resting_heart_rate
) {
  if (nrow(daily_resting_heart_rate) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L,
        rows_unchanged = 0L
      )
    )
  }

  existing_keys <- get_existing(
    connection = connection,
    daily_resting_heart_rate_keys = unique(
      daily_resting_heart_rate$daily_resting_heart_rate_key
    )
  )

  plan <- plan_google_health_daily_resting_heart_rate_upsert(
    daily_resting_heart_rate = daily_resting_heart_rate,
    existing_rows = existing_keys
  )

  rows_inserted <- 0L
  rows_updated <- 0L

  if (nrow(plan$to_insert) > 0) {
    rows_inserted <- insert_rows(
      connection = connection,
      daily_resting_heart_rate = plan$to_insert
    )
  }

  if (nrow(plan$to_update) > 0) {
    rows_updated <- update_rows(
      connection = connection,
      daily_resting_heart_rate = plan$to_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated,
    rows_unchanged = nrow(plan$unchanged) + plan$duplicate_count
  )
}
