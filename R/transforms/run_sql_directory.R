#' Run SQL Directory
#'
#' Execute SQL files in a directory in filename order.
#'
#' @param connection Database connection.
#' @param sql_dir Directory containing SQL scripts.
#' @param layer_name Human-readable layer name for logging.
#' @param pattern Regex pattern used to select SQL files.
#' @param exclude_pattern Optional regex pattern used to exclude SQL files.
#'
#' @return Invisibly returns NULL.
run_sql_directory <- function(
  connection,
  sql_dir,
  layer_name = basename(sql_dir),
  pattern = "\\.sql$",
  exclude_pattern = NULL
) {
  stopifnot(dir.exists(sql_dir))

  sql_files <- list.files(
    path = sql_dir,
    pattern = pattern,
    full.names = TRUE
  ) |>
    sort()

  if (!is.null(exclude_pattern)) {
    sql_files <- sql_files[
      !grepl(
        exclude_pattern,
        basename(sql_files)
      )
    ]
  }

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
