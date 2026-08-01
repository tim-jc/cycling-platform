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
  stream_rebuild_mode = "full",
  activity_ids = NULL,
  status_callback = NULL
) {
  emit_status <- function(event = list(), force = FALSE) {
    if (!is.null(status_callback)) status_callback(event, force = force)
    invisible(NULL)
  }
  silver_stream_batch_size <- config$transforms$silver_stream_activity_batch_size
  silver_stream_batch_max_expected_rows <-
    config$transforms$silver_stream_batch_max_expected_rows
  silver_stream_insert_chunk_size <-
    config$transforms$silver_stream_insert_chunk_size
  silver_stream_progress_every_batches <-
    config$transforms$silver_stream_progress_every_batches
  silver_stream_progress_every_seconds <-
    config$transforms$silver_stream_progress_every_seconds
  log_level <- config$logging$level

  if (is.null(silver_stream_batch_size)) {
    silver_stream_batch_size <- 10L
  }

  if (is.null(silver_stream_batch_max_expected_rows)) {
    silver_stream_batch_max_expected_rows <- 5000L
  }

  if (is.null(silver_stream_insert_chunk_size)) {
    silver_stream_insert_chunk_size <- 500L
  }
  if (is.null(silver_stream_progress_every_batches)) {
    silver_stream_progress_every_batches <- 10L
  }
  if (is.null(silver_stream_progress_every_seconds)) {
    silver_stream_progress_every_seconds <- 60
  }
  if (is.null(log_level)) log_level <- "INFO"

  emit_status(list(current_phase = "table_creation", current_entity = "silver"), force = TRUE)
  run_sql_directory(
    connection = connection,
    sql_dir = sql_dir,
    layer_name = "silver table creation",
    pattern = "^[0-9]+_create_.*\\.sql$"
  )

  emit_status(list(current_phase = "classification", current_entity = "power_source"), force = TRUE)
  refresh_power_source_classification(
    connection = connection,
    config = config
  )

  emit_status(list(current_phase = "silver_transforms", current_entity = "activities"), force = TRUE)
  rebuild_silver_activities(
    connection = connection,
    sql_dir = sql_dir,
    mode = if (is.null(activity_ids)) "full" else "incremental",
    activity_ids = activity_ids
  )

  emit_status(list(current_phase = "silver_transforms", current_entity = "gear"), force = TRUE)
  rebuild_silver_gear(
    connection = connection,
    sql_dir = sql_dir,
    mode = "full"
  )

  emit_status(list(current_phase = "silver_transforms", current_entity = "activity_streams"), force = TRUE)
  rebuild_silver_activity_streams(
    connection = connection,
    batch_size = silver_stream_batch_size,
    max_expected_rows = silver_stream_batch_max_expected_rows,
    insert_chunk_size = silver_stream_insert_chunk_size,
    progress_every_batches = silver_stream_progress_every_batches,
    progress_every_seconds = silver_stream_progress_every_seconds,
    log_level = log_level,
    status_callback = status_callback,
    mode = stream_rebuild_mode
  )
}
