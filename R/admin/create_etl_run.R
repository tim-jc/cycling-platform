#' Create ETL run
#'
#' Creates an ETL run for the specific data source and run_mode
#' @param source_id Integer value corresponding to the data source.
#' @param run_mode Character value: MANUAL, SCHEDULED or BACKFILL.
#'
#' @return Integer ETL run identifier.
create_etl_run <- function(source_id, run_mode) {
  stop("Not implemented")
}
