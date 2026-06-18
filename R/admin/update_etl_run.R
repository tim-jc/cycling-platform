#' Update ETL run
#'
#' Updates an ETL run already created
#' @param run_id Integer ETL run identifier.
#' @param run_status Character value: RUNNING, SUCCESS or FAILED.
#' @param error_message Optional error message.
#'
#' @return invisible(NULL)
update_etl_run <- function(
  connection,
  run_id,
  run_status,
  error_message = NULL
) {
  if (is.null(error_message)) {
    error_message <- NA_character_
  }

  DBI::dbExecute(
    conn = connection,
    statement = "
      UPDATE cycling_platform_admin.etl_run
      SET
        run_status = ?,
        completed_at = UTC_TIMESTAMP(),
        duration_seconds = TIMESTAMPDIFF(
          SECOND,
          started_at,
          UTC_TIMESTAMP()
        ),
        error_message = ?
      WHERE run_id = ?
    ",
    params = list(
      run_status,
      error_message,
      run_id
    )
  )

  invisible(NULL)
}
