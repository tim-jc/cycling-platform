#' Run SQL Directory
#'
#' Execute SQL files in a directory in filename order.
#'
#' @param connection Database connection.
#' @param sql_dir Directory containing SQL scripts.
#' @param layer_name Human-readable layer name for logging.
#'
#' @return Invisibly returns NULL.
run_sql_directory <- function(
  connection,
  sql_dir,
  layer_name = basename(sql_dir)
) {
  stopifnot(dir.exists(sql_dir))

  sql_files <- list.files(
    path = sql_dir,
    pattern = "\\.sql$",
    full.names = TRUE
  ) |>
    sort()

  if (length(sql_files) == 0) {
    message(glue::glue(
      "No {layer_name} SQL files found."
    ))

    return(invisible(NULL))
  }

  message(glue::glue(
    "Running {layer_name} SQL files."
  ))

  purrr::walk(
    sql_files,
    execute_sql_file,
    connection = connection
  )

  invisible(NULL)
}
