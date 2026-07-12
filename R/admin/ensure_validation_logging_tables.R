#' Ensure Validation Logging Tables
#'
#' Create validation logging tables if they do not already exist.
#'
#' @param connection Database connection.
#'
#' @return Invisibly returns NULL.
ensure_validation_logging_tables <- function(connection) {
  validation_log_sql_files <- c(
    file.path("sql", "admin", "050_create_validation_run.sql"),
    file.path("sql", "admin", "051_create_validation_run_check.sql")
  )

  purrr::walk(
    validation_log_sql_files,
    execute_sql_file,
    connection = connection
  )

  invisible(NULL)
}
