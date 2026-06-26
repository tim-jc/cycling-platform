#' Run Silver Transformations
#'
#' Execute silver-layer SQL files in sequence.
#'
#' @param connection Database connection.
#' @param sql_dir Directory containing silver SQL scripts.
#' @param config Platform configuration.
#' @param stream_rebuild_mode Use `full` to truncate/rebuild streams, or
#'   `repair` to rebuild only missing or incomplete stream activities.
#'
#' @return Invisibly returns NULL.
run_silver_transformations <- function(
  connection,
  sql_dir = file.path("sql", "silver"),
  config = list(),
  stream_rebuild_mode = "full"
) {
  silver_stream_batch_size <- config$transforms$silver_stream_activity_batch_size
  silver_stream_batch_max_expected_rows <-
    config$transforms$silver_stream_batch_max_expected_rows

  if (is.null(silver_stream_batch_size)) {
    silver_stream_batch_size <- 10L
  }

  if (is.null(silver_stream_batch_max_expected_rows)) {
    silver_stream_batch_max_expected_rows <- 5000L
  }

  run_sql_directory(
    connection = connection,
    sql_dir = sql_dir,
    layer_name = "silver table creation",
    pattern = "^[0-9]+_create_.*\\.sql$"
  )

  rebuild_silver_activities(
    connection = connection,
    sql_dir = sql_dir,
    mode = "full"
  )

  rebuild_silver_activity_streams(
    connection = connection,
    batch_size = silver_stream_batch_size,
    max_expected_rows = silver_stream_batch_max_expected_rows,
    mode = stream_rebuild_mode
  )
}
