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
  run_sql_directory(
    connection = connection,
    sql_dir = sql_dir,
    layer_name = "silver transformation"
  )
}
