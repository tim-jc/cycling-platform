#' Update Validation Run
#'
#' Update status and aggregate metrics for a validation run.
#'
#' @param connection Database connection.
#' @param validation_run_id Validation run identifier.
#' @param run_status Character value: RUNNING, SUCCESS, FAILED, or TIMED_OUT.
#' @param checks_planned Number of planned checks.
#' @param checks_completed Number of completed checks.
#' @param checks_failed Number of failed checks.
#' @param error_message Optional error message.
#'
#' @return Invisibly returns NULL.
update_validation_run <- function(
  connection,
  validation_run_id,
  run_status,
  checks_planned = 0L,
  checks_completed = 0L,
  checks_failed = 0L,
  error_message = NULL
) {
  if (is.null(error_message)) {
    error_message <- NA_character_
  }

  is_complete_status <- run_status %in% c(
    "SUCCESS",
    "FAILED",
    "TIMED_OUT"
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
      UPDATE cycling_platform_admin.validation_run
      SET
        run_status = ?,
        checks_planned = ?,
        checks_completed = ?,
        checks_failed = ?,
        completed_at = {completed_at_sql},
        duration_seconds = {duration_sql},
        error_message = ?
      WHERE validation_run_id = ?
    "),
    params = list(
      run_status,
      checks_planned,
      checks_completed,
      checks_failed,
      error_message,
      validation_run_id
    )
  )

  invisible(NULL)
}
