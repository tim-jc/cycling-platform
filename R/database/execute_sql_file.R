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
      message(
        "Executing statement: ",
        substr(statement, 1, 80)
      )

      DBI::dbExecute(
        conn = connection,
        statement = statement
      )
    }
  )

  invisible(NULL)
}
