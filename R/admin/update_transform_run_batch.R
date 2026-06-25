#' Update Transform Run Batch
#'
#' Update status and metrics for one transform batch.
#'
#' @param connection Database connection.
#' @param transform_run_batch_id Transform run batch identifier.
#' @param batch_status Character value: RUNNING, SUCCESS or FAILED.
#' @param rows_inserted Number of inserted rows.
#' @param rows_updated Number of updated rows.
#' @param rows_deleted Number of deleted rows.
#' @param error_message Optional error message.
#'
#' @return Invisibly returns NULL.
update_transform_run_batch <- function(
  connection,
  transform_run_batch_id,
  batch_status,
  rows_inserted = 0L,
  rows_updated = 0L,
  rows_deleted = 0L,
  error_message = NULL
) {
  if (is.null(error_message)) {
    error_message <- NA_character_
  }

  is_complete_status <- batch_status %in% c(
    "SUCCESS",
    "FAILED"
  )

  completed_at_sql <- if (is_complete_status) {
    "UTC_TIMESTAMP()"
  } else {
    "completed_at"
  }

  duration_sql <- if (is_complete_status) {
    "TIMESTAMPDIFF(SECOND, started_at, UTC_TIMESTAMP())"
  } else {
    "duration_seconds"
  }

  DBI::dbExecute(
    conn = connection,
    statement = glue::glue("
      UPDATE cycling_platform_admin.transform_run_batch
      SET
        batch_status = ?,
        rows_inserted = ?,
        rows_updated = ?,
        rows_deleted = ?,
        completed_at = {completed_at_sql},
        duration_seconds = {duration_sql},
        error_message = ?
      WHERE transform_run_batch_id = ?
    "),
    params = list(
      batch_status,
      rows_inserted,
      rows_updated,
      rows_deleted,
      error_message,
      transform_run_batch_id
    )
  )

  invisible(NULL)
}
