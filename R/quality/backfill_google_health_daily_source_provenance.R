google_health_parse_daily_payload_provenance <- function(payload) {
  tryCatch(
    {
      data_point <- jsonlite::fromJSON(
        payload,
        simplifyVector = FALSE
      )

      provenance <- google_health_daily_source_provenance(
        data_point = data_point
      )

      list(
        source_ecosystem = provenance$source_ecosystem[[1]],
        source_platform = provenance$source_platform[[1]],
        source_recording_method = provenance$source_recording_method[[1]],
        source_device_manufacturer =
          provenance$source_device_manufacturer[[1]],
        source_device_model = provenance$source_device_model[[1]],
        parse_status = "parsed"
      )
    },
    error = function(e) {
      list(
        source_ecosystem = "unknown",
        source_platform = NA_character_,
        source_recording_method = NA_character_,
        source_device_manufacturer = NA_character_,
        source_device_model = NA_character_,
        parse_status = "unparseable"
      )
    }
  )
}

google_health_daily_provenance_populated <- function(row) {
  !is.na(row$source_ecosystem[[1]]) &&
    nzchar(row$source_ecosystem[[1]]) &&
    !is.na(row$source_platform[[1]]) &&
    nzchar(row$source_platform[[1]]) &&
    !is.na(row$source_recording_method[[1]]) &&
    nzchar(row$source_recording_method[[1]])
}

google_health_daily_provenance_backfill_plan <- function(rows) {
  if (nrow(rows) == 0) {
    rows$backfill_action <- character()
    rows$parsed_source_ecosystem <- character()
    rows$parsed_source_platform <- character()
    rows$parsed_source_recording_method <- character()
    rows$parsed_source_device_manufacturer <- character()
    rows$parsed_source_device_model <- character()
    return(rows)
  }

  planned <- purrr::map_dfr(
    seq_len(nrow(rows)),
    \(row_index) {
      row <- rows[row_index, , drop = FALSE]

      if (google_health_daily_provenance_populated(row)) {
        return(
          dplyr::mutate(
            row,
            backfill_action = "already_populated",
            parsed_source_ecosystem = source_ecosystem,
            parsed_source_platform = source_platform,
            parsed_source_recording_method = source_recording_method,
            parsed_source_device_manufacturer = source_device_manufacturer,
            parsed_source_device_model = source_device_model
          )
        )
      }

      provenance <- google_health_parse_daily_payload_provenance(
        payload = row$payload[[1]]
      )

      action <- if (identical(provenance$parse_status, "unparseable")) {
        "unparseable"
      } else if (
        is.na(provenance$source_platform) ||
          !nzchar(provenance$source_platform)
      ) {
        "unknown_source"
      } else {
        "update"
      }

      dplyr::mutate(
        row,
        backfill_action = action,
        parsed_source_ecosystem = provenance$source_ecosystem,
        parsed_source_platform = provenance$source_platform,
        parsed_source_recording_method = provenance$source_recording_method,
        parsed_source_device_manufacturer =
          provenance$source_device_manufacturer,
        parsed_source_device_model = provenance$source_device_model
      )
    }
  )

  planned
}

backfill_google_health_daily_provenance_table <- function(
  connection,
  table_name,
  key_column,
  payload_column,
  dry_run = FALSE
) {
  rows <- DBI::dbGetQuery(
    conn = connection,
    statement = glue::glue("
      SELECT
        {key_column} AS row_key,
        source_ecosystem,
        source_platform,
        source_recording_method,
        source_device_manufacturer,
        source_device_model,
        {payload_column} AS payload
      FROM cycling_platform_raw.{table_name}
    ")
  )

  if (nrow(rows) == 0) {
    return(
      tibble::tibble(
        table_name = table_name,
        examined = 0L,
        updated = 0L,
        already_populated = 0L,
        unknown_source = 0L,
        unparseable = 0L
      )
    )
  }

  counts <- list(
    examined = nrow(rows),
    updated = 0L,
    already_populated = 0L,
    unknown_source = 0L,
    unparseable = 0L
  )

  update_sql <- glue::glue("
    UPDATE cycling_platform_raw.{table_name}
    SET
      source_ecosystem = ?,
      source_platform = ?,
      source_recording_method = ?,
      source_device_manufacturer = ?,
      source_device_model = ?
    WHERE {key_column} = ?
  ")

  planned_rows <- google_health_daily_provenance_backfill_plan(rows)

  counts$already_populated <- sum(
    planned_rows$backfill_action == "already_populated"
  )
  counts$unknown_source <- sum(
    planned_rows$backfill_action == "unknown_source"
  )
  counts$unparseable <- sum(
    planned_rows$backfill_action == "unparseable"
  )

  update_rows <- planned_rows[
    planned_rows$backfill_action %in% c("update", "unknown_source"),
    ,
    drop = FALSE
  ]

  for (row_index in seq_len(nrow(update_rows))) {
    row <- update_rows[row_index, , drop = FALSE]

    if (!isTRUE(dry_run)) {
      DBI::dbExecute(
        conn = connection,
        statement = update_sql,
        params = list(
          row$parsed_source_ecosystem[[1]],
          row$parsed_source_platform[[1]],
          row$parsed_source_recording_method[[1]],
          row$parsed_source_device_manufacturer[[1]],
          row$parsed_source_device_model[[1]],
          row$row_key[[1]]
        )
      )
    }

    counts$updated <- counts$updated + 1L
  }

  tibble::tibble(
    table_name = table_name,
    examined = counts$examined,
    updated = counts$updated,
    already_populated = counts$already_populated,
    unknown_source = counts$unknown_source,
    unparseable = counts$unparseable
  )
}

backfill_google_health_daily_source_provenance <- function(
  connection,
  dry_run = FALSE
) {
  dplyr::bind_rows(
    backfill_google_health_daily_provenance_table(
      connection = connection,
      table_name = "google_health_daily_resting_heart_rate",
      key_column = "daily_resting_heart_rate_key",
      payload_column = "daily_resting_heart_rate_payload",
      dry_run = dry_run
    ),
    backfill_google_health_daily_provenance_table(
      connection = connection,
      table_name = "google_health_daily_heart_rate_variability",
      key_column = "daily_heart_rate_variability_key",
      payload_column = "daily_heart_rate_variability_payload",
      dry_run = dry_run
    )
  )
}
