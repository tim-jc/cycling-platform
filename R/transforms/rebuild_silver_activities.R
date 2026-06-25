#' Get Silver Activity Transform Plan
#'
#' Return planned source row counts and activity ID range for silver activities.
#'
#' @param connection Database connection.
#'
#' @return One-row data frame with activity counts and ID range.
get_silver_activity_transform_plan <- function(connection) {
  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT
        COUNT(*) AS expected_row_count,
        MIN(activity_id) AS min_activity_id,
        MAX(activity_id) AS max_activity_id
      FROM cycling_platform_raw.activities
    "
  )
}

#' Get Silver Activity Row Count
#'
#' Return current silver activity row count.
#'
#' @param connection Database connection.
#'
#' @return Integer row count.
get_silver_activity_row_count <- function(connection) {
  DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT COUNT(*) AS row_count
      FROM cycling_platform_silver.activities
    "
  )$row_count
}

#' Rebuild Silver Activities
#'
#' Rebuild silver activities and log the transform as a single batch.
#'
#' @param connection Database connection.
#' @param sql_dir Directory containing silver SQL scripts.
#' @param mode Transform mode label.
#'
#' @return Invisibly returns NULL.
rebuild_silver_activities <- function(
  connection,
  sql_dir = file.path("sql", "silver"),
  mode = "full"
) {
  ensure_transform_logging_tables(
    connection = connection
  )

  create_sql_file <- file.path(
    sql_dir,
    "200_create_activities.sql"
  )

  transform_sql_file <- file.path(
    sql_dir,
    "210_transform_activities.sql"
  )

  execute_sql_file(
    sql_file = create_sql_file,
    connection = connection
  )

  activity_plan <- get_silver_activity_transform_plan(
    connection = connection
  )

  expected_row_count <- activity_plan$expected_row_count[[1]]

  transform_run_id <- create_transform_run(
    connection = connection,
    layer_name = "silver",
    entity_name = "activities",
    run_mode = mode,
    total_batches = 1L,
    activities_planned = expected_row_count,
    expected_rows_planned = expected_row_count,
    max_batch_activities = expected_row_count,
    max_batch_expected_rows = expected_row_count
  )

  transform_run_batch_id <- create_transform_run_batch(
    connection = connection,
    transform_run_id = transform_run_id,
    batch_number = 1L,
    expected_rows = expected_row_count,
    activity_count = expected_row_count,
    min_activity_id = activity_plan$min_activity_id[[1]],
    max_activity_id = activity_plan$max_activity_id[[1]]
  )

  transform_error <- tryCatch(
    {
      execute_sql_file(
        sql_file = transform_sql_file,
        connection = connection
      )

      NULL
    },
    error = function(e) {
      e
    }
  )

  rows_inserted <- 0L

  if (is.null(transform_error)) {
    rows_inserted <- get_silver_activity_row_count(
      connection = connection
    )

    update_transform_run_batch(
      connection = connection,
      transform_run_batch_id = transform_run_batch_id,
      batch_status = "SUCCESS",
      rows_inserted = rows_inserted
    )

    update_transform_run(
      connection = connection,
      transform_run_id = transform_run_id,
      run_status = "SUCCESS",
      completed_batches = 1L,
      activities_completed = rows_inserted,
      rows_inserted = rows_inserted
    )

    message(glue::glue(
      "Silver activities rebuild complete: ",
      "{rows_inserted} rows inserted."
    ))

    return(invisible(NULL))
  }

  update_transform_run_batch(
    connection = connection,
    transform_run_batch_id = transform_run_batch_id,
    batch_status = "FAILED",
    error_message = conditionMessage(transform_error)
  )

  update_transform_run(
    connection = connection,
    transform_run_id = transform_run_id,
    run_status = "FAILED",
    error_message = conditionMessage(transform_error)
  )

  stop(transform_error)
}
