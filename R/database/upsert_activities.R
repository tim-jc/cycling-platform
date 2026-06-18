#' Upsert Activities
#'
#' Upserts activities in DB with data from latest ETL run
#' @param connection Database connection.
#' @param activities Tibble returned by get_activities().
#'
#' @return Named list containing rows_inserted and rows_updated.
upsert_activities <- function(
  connection,
  activities
) {
  stop("Not implemented")
}
