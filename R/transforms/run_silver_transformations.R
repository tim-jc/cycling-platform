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

  if (is.null(silver_stream_batch_size)) {
    silver_stream_batch_size <- 10L
  }

  run_sql_directory(
    connection = connection,
    sql_dir = sql_dir,
    layer_name = "silver table and activity transformation",
    exclude_pattern = "^230_transform_activity_streams\\.sql$"
  )

  rebuild_silver_activity_streams(
    connection = connection,
    batch_size = silver_stream_batch_size,
    mode = stream_rebuild_mode
  )
}
