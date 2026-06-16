#' Create ETL run
#'
#' Creates an ETL run for the specific data source and run_mode
#' @param source_id integer value corresponding to the data source
#' @param run_mode Character value: MANUAL, SCHEDULED or BACKFILL.
#' @return integer the run_id of the run created
create_etl_run <- function(source_id, run_mode) {
  stop("Not implemented")
}
