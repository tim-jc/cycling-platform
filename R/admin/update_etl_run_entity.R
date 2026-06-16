#' Update ETL run entity
#'
#' Updates an existing ETL run entity
#' @param run_entity_id Integer ETL run entity identifier.
#' @param entity_status Character value: RUNNING, SUCCESS or FAILED.
#' @param rows_inserted Integer number of inserted rows.
#' @param rows_updated Integer number of updated rows.
#' @param error_message Optional error message.
#'
#' @return invisible(NULL)
update_etl_run_entity <- function(
  run_entity_id,
  entity_status,
  rows_inserted = 0L,
  rows_updated = 0L,
  error_message = NULL
) {
  stop("Not implemented")
}
