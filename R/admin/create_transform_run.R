#' Create Transform Run
#'
#' Insert a row into admin.transform_run and return transform_run_id.
#'
#' @param connection Database connection.
#' @param layer_name Layer name, for example silver or gold.
#' @param entity_name Entity name, for example activity_streams.
#' @param run_mode Transform mode, for example full, repair, or incremental.
#' @param total_batches Planned batch count.
#' @param activities_planned Planned activity count.
#' @param expected_rows_planned Planned expected row count.
#' @param max_batch_activities Maximum activities per batch.
#' @param max_batch_expected_rows Maximum expected rows per batch.
#'
#' @return Integer transform run identifier.
create_transform_run <- function(
  connection,
  layer_name,
  entity_name,
  run_mode,
  total_batches = 0L,
  activities_planned = 0L,
  expected_rows_planned = 0L,
  max_batch_activities = NULL,
  max_batch_expected_rows = NULL
) {
  if (is.null(max_batch_activities)) {
    max_batch_activities <- NA_integer_
  }

  if (is.null(max_batch_expected_rows)) {
    max_batch_expected_rows <- NA_integer_
  }

  DBI::dbExecute(
    conn = connection,
    statement = "
      INSERT INTO cycling_platform_admin.transform_run (
        layer_name,
        entity_name,
        run_mode,
        run_status,
        total_batches,
        activities_planned,
        expected_rows_planned,
        max_batch_activities,
        max_batch_expected_rows
      )
      VALUES (?, ?, ?, 'RUNNING', ?, ?, ?, ?, ?)
    ",
    params = list(
      layer_name,
      entity_name,
      toupper(run_mode),
      total_batches,
      activities_planned,
      expected_rows_planned,
      max_batch_activities,
      max_batch_expected_rows
    )
  )

  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT LAST_INSERT_ID() AS transform_run_id
    "
  )$transform_run_id
}
