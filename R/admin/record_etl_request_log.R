record_etl_request_log <- function(
  connection,
  run_id,
  run_entity_id,
  entity_name,
  request_status,
  requested_start_date,
  requested_end_date,
  returned_data_point_count = 0L,
  retrieved_at = NULL,
  error_message = NULL
) {
  if (is.null(retrieved_at)) {
    retrieved_at <- as.POSIXct(NA)
  }

  if (is.null(error_message)) {
    error_message <- NA_character_
  }

  DBI::dbExecute(
    conn = connection,
    statement = "
      INSERT INTO cycling_platform_admin.etl_request_log (
        run_id,
        run_entity_id,
        entity_name,
        request_status,
        requested_start_date,
        requested_end_date,
        returned_data_point_count,
        is_successfully_empty,
        retrieved_at,
        error_message
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ",
    params = list(
      run_id,
      run_entity_id,
      entity_name,
      request_status,
      requested_start_date,
      requested_end_date,
      returned_data_point_count,
      as.integer(
        identical(request_status, "SUCCESS") &&
          returned_data_point_count == 0L
      ),
      retrieved_at,
      error_message
    )
  )

  invisible(NULL)
}
