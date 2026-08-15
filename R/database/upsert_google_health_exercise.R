get_existing_google_health_exercise_keys <- function(
  connection,
  exercise_observation_keys
) {
  if (length(exercise_observation_keys) == 0L) {
    return(tibble::tibble(exercise_observation_key = character()))
  }

  placeholders <- paste(rep("?", length(exercise_observation_keys)), collapse = ", ")
  DBI::dbGetQuery(
    connection,
    paste0(
      "SELECT exercise_observation_key
       FROM cycling_platform_raw.google_health_exercise
       WHERE exercise_observation_key IN (",
      placeholders,
      ")"
    ),
    params = as.list(unname(exercise_observation_keys))
  ) |>
    dplyr::mutate(exercise_observation_key = as.character(exercise_observation_key))
}

plan_google_health_exercise_upsert <- function(exercise, existing_keys) {
  duplicate_count <- sum(duplicated(exercise$exercise_observation_key))
  exercise <- dplyr::distinct(
    exercise,
    exercise_observation_key,
    .keep_all = TRUE
  )
  split <- split_existing_rows(
    data = exercise,
    existing_keys = existing_keys,
    key_columns = "exercise_observation_key"
  )
  list(
    to_insert = split$to_insert,
    unchanged = split$to_update,
    duplicate_count = duplicate_count
  )
}

insert_google_health_exercise <- function(connection, exercise) {
  if (nrow(exercise) == 0L) {
    return(0L)
  }
  append_existing_table(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "google_health_exercise"
    ),
    value = exercise,
    append = TRUE,
    overwrite = FALSE
  )
  nrow(exercise)
}

upsert_google_health_exercise <- function(connection, exercise) {
  if (nrow(exercise) == 0L) {
    return(list(rows_inserted = 0L, rows_updated = 0L, rows_unchanged = 0L))
  }

  existing_keys <- get_existing_google_health_exercise_keys(
    connection,
    unique(exercise$exercise_observation_key)
  )
  plan <- plan_google_health_exercise_upsert(exercise, existing_keys)
  rows_inserted <- insert_google_health_exercise(connection, plan$to_insert)

  list(
    rows_inserted = rows_inserted,
    rows_updated = 0L,
    rows_unchanged = nrow(plan$unchanged) + plan$duplicate_count
  )
}
