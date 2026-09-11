#' Create Validation Run
#'
#' Insert a row into admin.validation_run and return validation_run_id.
#'
#' @param connection Database connection.
#' @param validation_scope Validation scope, for example publication or deep.
#' @param run_mode Run mode, for example automated or manual.
#' @param per_check_timeout_seconds Optional per-check timeout in seconds.
#' @param overall_timeout_seconds Optional overall timeout in seconds.
#'
#' @return Integer validation run identifier.
create_validation_run <- function(
  connection,
  validation_scope,
  run_mode,
  per_check_timeout_seconds = NULL,
  overall_timeout_seconds = NULL,
  pipeline_run_id = NULL
) {
  if (is.null(per_check_timeout_seconds)) {
    per_check_timeout_seconds <- NA_integer_
  }

  if (is.null(overall_timeout_seconds)) {
    overall_timeout_seconds <- NA_integer_
  }

  DBI::dbExecute(
    conn = connection,
    statement = "
      INSERT INTO cycling_platform_admin.validation_run (
        pipeline_run_id,
        validation_scope,
        run_mode,
        run_status,
        per_check_timeout_seconds,
        overall_timeout_seconds
      )
      VALUES (?, ?, ?, 'RUNNING', ?, ?)
    ",
    params = list(
      if (is.null(pipeline_run_id)) NA else pipeline_run_id,
      toupper(validation_scope),
      toupper(run_mode),
      per_check_timeout_seconds,
      overall_timeout_seconds
    )
  )

  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT LAST_INSERT_ID() AS validation_run_id
    "
  )$validation_run_id
}
