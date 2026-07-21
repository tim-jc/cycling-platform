google_health_sleep_metadata_populated <- function(row) {
  has_interval <- (
    !is.na(row$start_physical_time[[1]]) ||
      !is.na(row$end_physical_time[[1]]) ||
      !is.na(row$start_civil_date[[1]]) ||
      !is.na(row$end_civil_date[[1]])
  )

  has_stage_metadata <- (
    !is.na(row$sleep_type[[1]]) ||
      !is.na(row$stages_status[[1]]) ||
      !is.na(row$has_sleep_stages[[1]]) ||
      !is.na(row$has_sleep_summary[[1]])
  )

  has_interval && has_stage_metadata
}

google_health_parse_sleep_metadata_payload <- function(row) {
  tryCatch(
    {
      sleep_log <- jsonlite::fromJSON(
        row$sleep_log_payload[[1]],
        simplifyVector = FALSE
      )

      shaped <- google_health_shape_sleep_logs(
        sleep_logs = list(sleep_log),
        google_user_id = row$google_user_id[[1]],
        run_id = row$run_id[[1]],
        source_id = row$source_id[[1]],
        retrieved_at = row$retrieved_at[[1]]
      )

      if (nrow(shaped) != 1) {
        return(
          list(
            parse_status = "unparseable"
          )
        )
      }

      list(
        parse_status = "parsed",
        shaped = shaped
      )
    },
    error = function(e) {
      list(
        parse_status = "unparseable",
        error_message = conditionMessage(e)
      )
    }
  )
}

backfill_google_health_sleep_metadata <- function(
  connection,
  dry_run = FALSE
) {
  rows <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT
        sleep_log_key,
        source_log_id,
        google_user_id,
        run_id,
        source_id,
        retrieved_at,
        source_name,
        start_physical_time,
        end_physical_time,
        start_utc_offset,
        end_utc_offset,
        start_civil_date,
        end_civil_date,
        sleep_type,
        stages_status,
        is_processed,
        is_nap,
        is_manually_edited,
        has_sleep_stages,
        sleep_stage_count,
        has_sleep_summary,
        sleep_log_payload
      FROM cycling_platform_raw.google_health_sleep_logs
    "
  )

  counts <- list(
    examined = nrow(rows),
    updated = 0L,
    already_populated = 0L,
    unparseable = 0L,
    still_missing_interval = 0L
  )

  if (nrow(rows) == 0) {
    return(
      tibble::as_tibble(counts)
    )
  }

  update_sql <- "
    UPDATE cycling_platform_raw.google_health_sleep_logs
    SET
      source_log_id = ?,
      source_name = ?,
      start_physical_time = ?,
      end_physical_time = ?,
      start_utc_offset = ?,
      end_utc_offset = ?,
      start_civil_date = ?,
      end_civil_date = ?,
      sleep_type = ?,
      stages_status = ?,
      is_processed = ?,
      is_nap = ?,
      is_manually_edited = ?,
      has_sleep_stages = ?,
      sleep_stage_count = ?,
      has_sleep_summary = ?
    WHERE sleep_log_key = ?
  "

  for (row_index in seq_len(nrow(rows))) {
    row <- rows[row_index, , drop = FALSE]

    if (google_health_sleep_metadata_populated(row)) {
      counts$already_populated <- counts$already_populated + 1L
      next
    }

    parsed <- google_health_parse_sleep_metadata_payload(row)

    if (!identical(parsed$parse_status, "parsed")) {
      counts$unparseable <- counts$unparseable + 1L
      next
    }

    shaped <- parsed$shaped

    if (
      is.na(shaped$start_physical_time[[1]]) &&
        is.na(shaped$end_physical_time[[1]]) &&
        is.na(shaped$start_civil_date[[1]]) &&
        is.na(shaped$end_civil_date[[1]])
    ) {
      counts$still_missing_interval <- counts$still_missing_interval + 1L
    }

    if (!isTRUE(dry_run)) {
      DBI::dbExecute(
        conn = connection,
        statement = update_sql,
        params = list(
          shaped$source_log_id[[1]],
          shaped$source_name[[1]],
          shaped$start_physical_time[[1]],
          shaped$end_physical_time[[1]],
          shaped$start_utc_offset[[1]],
          shaped$end_utc_offset[[1]],
          shaped$start_civil_date[[1]],
          shaped$end_civil_date[[1]],
          shaped$sleep_type[[1]],
          shaped$stages_status[[1]],
          shaped$is_processed[[1]],
          shaped$is_nap[[1]],
          shaped$is_manually_edited[[1]],
          shaped$has_sleep_stages[[1]],
          shaped$sleep_stage_count[[1]],
          shaped$has_sleep_summary[[1]],
          row$sleep_log_key[[1]]
        )
      )
    }

    counts$updated <- counts$updated + 1L
  }

  tibble::as_tibble(counts)
}
