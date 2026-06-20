#' Execute SQL File
#'
#' Execute a SQL script.
#'
#' @param sql_file Path to SQL file.
#' @param connection Database connection.
#'
#' @return Invisibly returns NULL.
execute_sql_file <- function(
  sql_file,
  connection
) {
  stopifnot(file.exists(sql_file))

  sql <- readr::read_file(sql_file)

  split_sql_statements <- function(sql) {
    # Assumptions:
    # - SQL statements are terminated by ';'
    # - Semicolons do not appear inside strings
    # - Procedures and triggers are not supported

    statements <- strsplit(
      sql,
      ";\\s*\n",
      perl = TRUE
    )[[1]]

    statements <- trimws(statements)

    statements[nzchar(statements)]
  }

  statements <- split_sql_statements(sql)

  message("Executing: ", sql_file)

  purrr::walk(
    statements,
    \(statement) {
      DBI::dbExecute(
        conn = connection,
        statement = statement
      )
    }
  )

  invisible(NULL)
}
