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
#' @param validation_summary Optional validation summary tibble.
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
  validation_summary = NULL,
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

  has_summary_columns <- validation_run_has_summary_columns(
    connection = connection
  )

  if (
    isTRUE(has_summary_columns) &&
      !is.null(validation_summary) &&
      nrow(validation_summary) > 0
  ) {
    DBI::dbExecute(
      conn = connection,
      statement = glue::glue("
        UPDATE cycling_platform_admin.validation_run
        SET
          run_status = ?,
          validation_outcome = ?,
          checks_planned = ?,
          checks_completed = ?,
          checks_failed = ?,
          total_check_count = ?,
          warning_check_count = ?,
          warning_issue_count = ?,
          error_check_count = ?,
          error_issue_count = ?,
          skipped_check_count = ?,
          completed_at = {completed_at_sql},
          duration_seconds = {duration_sql},
          error_message = ?
        WHERE validation_run_id = ?
      "),
      params = list(
        run_status,
        validation_summary$validation_outcome[[1]],
        checks_planned,
        checks_completed,
        checks_failed,
        validation_summary$total_check_count[[1]],
        validation_summary$warning_check_count[[1]],
        validation_summary$warning_issue_count[[1]],
        validation_summary$error_check_count[[1]],
        validation_summary$error_issue_count[[1]],
        validation_summary$skipped_check_count[[1]],
        error_message,
        validation_run_id
      )
    )

    return(invisible(NULL))
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

validation_run_has_summary_columns <- function(connection) {
  required_columns <- c(
    "validation_outcome",
    "total_check_count",
    "warning_check_count",
    "warning_issue_count",
    "error_check_count",
    "error_issue_count",
    "skipped_check_count"
  )

  columns <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT column_name
      FROM information_schema.columns
      WHERE table_schema = 'cycling_platform_admin'
        AND table_name = 'validation_run'
        AND column_name IN (?, ?, ?, ?, ?, ?, ?)
    ",
    params = as.list(required_columns)
  )$column_name

  all(required_columns %in% columns)
}
