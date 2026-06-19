#' Bootstrap platform
#'
#' R function to build out SQL platform
bootstrap_platform <- function() {
  connection <- get_connection("mysql")

  on.exit(DBI::dbDisconnect(connection))

  sql_files <- list.files(
    path = "sql",
    recursive = TRUE,
    full.names = TRUE,
    pattern = "\\.sql$"
  ) |>
    sort()

  purrr::walk(
    sql_files,
    execute_sql_file,
    connection = connection
  )
}
