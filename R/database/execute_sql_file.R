#' Execute SQL File
#'
#' Execute a SQL script.
#'
#' @param connection Database connection.
#' @param sql_file Path to SQL file.
#'
#' @return Invisibly returns NULL.
execute_sql_file <- function(
  connection,
  sql_file
) {
  stopifnot(file.exists(sql_file))

  sql <- readr::read_file(sql_file)

  statements <- strsplit(
    sql,
    ";\\s*\n",
    perl = TRUE
  )[[1]]

  statements <- trimws(statements)

  statements <- statements[nzchar(statements)]

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
