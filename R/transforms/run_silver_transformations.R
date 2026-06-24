#' Run Silver Transformations
#'
#' Execute silver-layer SQL files in sequence.
#'
#' @param connection Database connection.
#' @param sql_dir Directory containing silver SQL scripts.
#'
#' @return Invisibly returns NULL.
run_silver_transformations <- function(
  connection,
  sql_dir = file.path("sql", "silver")
) {
  stopifnot(dir.exists(sql_dir))

  sql_files <- list.files(
    path = sql_dir,
    pattern = "\\.sql$",
    full.names = TRUE
  ) |>
    sort()

  if (length(sql_files) == 0) {
    message("No silver transformation SQL files found.")

    return(invisible(NULL))
  }

  purrr::walk(
    sql_files,
    execute_sql_file,
    connection = connection
  )

  invisible(NULL)
}
