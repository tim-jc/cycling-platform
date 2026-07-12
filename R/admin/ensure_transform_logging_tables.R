#' Ensure Transform Logging Tables
#'
#' Create transform logging tables if they do not already exist.
#'
#' @param connection Database connection.
#'
#' @return Invisibly returns NULL.
ensure_transform_logging_tables <- function(connection) {
  transform_log_sql_files <- c(
    file.path("sql", "admin", "040_create_transform_run.sql"),
    file.path("sql", "admin", "041_create_transform_run_batch.sql")
  )

  purrr::walk(
    transform_log_sql_files,
    execute_sql_file,
    connection = connection
  )

  invisible(NULL)
}
