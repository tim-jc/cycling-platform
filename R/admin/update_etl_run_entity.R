#' Update ETL run entity
#'
#' Mark an entity load as complete.
#'
#' @param run_entity_id Integer ETL run entity identifier.
#' @param entity_status Character value: RUNNING, SUCCESS or FAILED.
#' @param rows_inserted Integer number of inserted rows.
#' @param rows_updated Integer number of updated rows.
#' @param error_message Optional error message.
#'
#' @return invisible(NULL)
update_etl_run_entity <- function(
  connection,
  run_entity_id,
  entity_status,
  rows_inserted = 0L,
  rows_updated = 0L,
  rows_deleted = 0L,
  error_message = NULL
) {
  if (is.null(error_message)) {
    error_message <- NA_character_
  }

  DBI::dbExecute(
    conn = connection,
    statement = "
      UPDATE cycling_platform_admin.etl_run_entity
      SET
        entity_status = ?,
        rows_inserted = ?,
        rows_updated = ?,
        rows_deleted = ?,
        completed_at = UTC_TIMESTAMP(),
        duration_seconds = TIMESTAMPDIFF(
          SECOND,
          started_at,
          UTC_TIMESTAMP()
        ),
        error_message = ?
      WHERE run_entity_id = ?
    ",
    params = list(
      entity_status,
      rows_inserted,
      rows_updated,
      rows_deleted,
      error_message,
      run_entity_id
    )
  )

  invisible(NULL)
}
