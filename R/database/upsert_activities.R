#' Upsert Activities
#'
#' Upserts activities in DB with data from latest ETL run
#' @param activities tibble returned by get_activities()
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#'
#' @return Named list containing rows_inserted and rows_updated.
upsert_activities <- function(activities, run_id, source_id) {
  stop("Not implemented")
}
