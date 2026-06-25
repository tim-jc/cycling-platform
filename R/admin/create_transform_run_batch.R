#' Create Transform Run Batch
#'
#' Insert a row into admin.transform_run_batch.
#'
#' @param connection Database connection.
#' @param transform_run_id Transform run identifier.
#' @param batch_number Batch number within the run.
#' @param activity_ids Activity IDs included in the batch.
#' @param expected_rows Expected rows for the batch.
#' @param activity_count Optional activity count override.
#' @param min_activity_id Optional minimum activity ID.
#' @param max_activity_id Optional maximum activity ID.
#'
#' @return Integer transform run batch identifier.
create_transform_run_batch <- function(
  connection,
  transform_run_id,
  batch_number,
  activity_ids = NULL,
  expected_rows,
  activity_count = NULL,
  min_activity_id = NULL,
  max_activity_id = NULL
) {
  if (is.null(activity_count)) {
    activity_count <- length(activity_ids)
  }

  if (is.null(min_activity_id) || is.null(max_activity_id)) {
    activity_ids_integer64 <- bit64::as.integer64(
      as.character(activity_ids)
    )

    min_activity_id <- min(activity_ids_integer64)
    max_activity_id <- max(activity_ids_integer64)
  }

  DBI::dbExecute(
    conn = connection,
    statement = "
      INSERT INTO cycling_platform_admin.transform_run_batch (
        transform_run_id,
        batch_number,
        batch_status,
        activity_count,
        expected_rows,
        min_activity_id,
        max_activity_id
      )
      VALUES (?, ?, 'RUNNING', ?, ?, ?, ?)
    ",
    params = list(
      transform_run_id,
      batch_number,
      activity_count,
      expected_rows,
      min_activity_id,
      max_activity_id
    )
  )

  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT LAST_INSERT_ID() AS transform_run_batch_id
    "
  )$transform_run_batch_id
}
