create_api_endpoint_run <- function(
  connection,
  run_id,
  source_id,
  entity_name,
  endpoint_name
) {
  DBI::dbExecute(
    connection,
    "
      INSERT INTO cycling_platform_admin.api_endpoint_run (
        run_id,
        source_id,
        entity_name,
        endpoint_name,
        run_mode,
        run_status
      )
      SELECT ?, ?, ?, ?, run_mode, 'RUNNING'
      FROM cycling_platform_admin.etl_run
      WHERE run_id = ?
    ",
    params = list(
      run_id, source_id, entity_name, endpoint_name, run_id
    )
  )

  DBI::dbGetQuery(
    connection,
    "SELECT LAST_INSERT_ID() AS endpoint_run_id"
  )$endpoint_run_id[[1]]
}

update_api_endpoint_run <- function(
  connection,
  endpoint_run_id,
  run_status,
  http_request_count = 0L,
  source_record_count = 0L,
  historical_lookup_count = 0L,
  rows_inserted = 0L,
  rows_unchanged = 0L,
  unresolved_identifier_count = 0L,
  error_message = NULL
) {
  DBI::dbExecute(
    connection,
    "
      UPDATE cycling_platform_admin.api_endpoint_run
      SET
        run_status = ?,
        http_request_count = ?,
        source_record_count = ?,
        historical_lookup_count = ?,
        rows_inserted = ?,
        rows_unchanged = ?,
        unresolved_identifier_count = ?,
        completed_at = UTC_TIMESTAMP(),
        duration_seconds = TIMESTAMPDIFF(SECOND, started_at, UTC_TIMESTAMP()),
        error_message = ?
      WHERE endpoint_run_id = ?
    ",
    params = list(
      run_status,
      http_request_count,
      source_record_count,
      historical_lookup_count,
      rows_inserted,
      rows_unchanged,
      unresolved_identifier_count,
      if (is.null(error_message)) NA_character_ else error_message,
      endpoint_run_id
    )
  )

  invisible(NULL)
}
