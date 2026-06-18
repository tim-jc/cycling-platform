#' Create ETL run
#'
#' Insert a row into admin.etl_run and return run_id.
#' @param source_id Integer value corresponding to the data source.
#' @param run_mode Character value: MANUAL, SCHEDULED or BACKFILL.
#'
#' @return Integer ETL run identifier.
create_etl_run <- function(
  connection,
  source_id,
  run_mode
) {
  DBI::dbExecute(
    conn = connection,
    statement = "
      INSERT INTO cycling_platform_admin.etl_run (
        source_id,
        run_mode,
        run_status
      )
      VALUES (?, ?, 'RUNNING')
    ",
    params = list(
      source_id,
      run_mode
    )
  )

  run_id <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT LAST_INSERT_ID() AS run_id
    "
  )$run_id

  run_id
}
