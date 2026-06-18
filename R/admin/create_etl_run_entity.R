#' Create ETL run entity
#'
#' Insert a row into admin.etl_run_entity and return run_entity_id.
#' @param run_id Integer ID of ETL run to create an entity for.
#' @param entity_name Name of entity.
#'
#' @return Integer ETL run entity identifier.
create_etl_run_entity <- function(
  connection,
  run_id,
  entity_name
) {
  DBI::dbExecute(
    conn = connection,
    statement = "
      INSERT INTO cycling_platform_admin.etl_run_entity (
        run_id,
        entity_name,
        entity_status
      )
      VALUES (?, ?, 'RUNNING')
    ",
    params = list(
      run_id,
      entity_name
    )
  )

  run_entity_id <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT LAST_INSERT_ID() AS run_entity_id
    "
  )$run_entity_id

  run_entity_id
}
