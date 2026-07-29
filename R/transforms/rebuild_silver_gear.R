rebuild_silver_gear <- function(
  connection,
  sql_dir = file.path("sql", "silver"),
  mode = "full"
) {
  ensure_transform_logging_tables(connection)
  execute_sql_file(file.path(sql_dir, "040_create_gear.sql"), connection)

  expected <- DBI::dbGetQuery(
    connection,
    "SELECT COUNT(DISTINCT gear_id) AS row_count
     FROM cycling_platform_raw.gear_observations"
  )$row_count[[1]]

  transform_run_id <- create_transform_run(
    connection = connection,
    layer_name = "silver",
    entity_name = "gear",
    run_mode = mode,
    total_batches = 1L,
    activities_planned = 0L,
    expected_rows_planned = expected,
    max_batch_activities = 0L,
    max_batch_expected_rows = expected
  )

  error <- tryCatch(
    {
      DBI::dbWithTransaction(
        connection,
        execute_sql_file(
          file.path(sql_dir, "050_transform_gear.sql"),
          connection
        )
      )
      NULL
    },
    error = function(e) e
  )

  if (!is.null(error)) {
    update_transform_run(
      connection, transform_run_id, "FAILED",
      error_message = conditionMessage(error)
    )
    stop(error)
  }

  actual <- DBI::dbGetQuery(
    connection,
    "SELECT COUNT(*) AS row_count FROM cycling_platform_silver.gear"
  )$row_count[[1]]

  update_transform_run(
    connection = connection,
    transform_run_id = transform_run_id,
    run_status = "SUCCESS",
    completed_batches = 1L,
    rows_inserted = actual
  )

  message(glue::glue("Silver gear rebuild complete: {actual} rows."))
  invisible(NULL)
}
