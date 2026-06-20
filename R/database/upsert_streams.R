#' Upsert Streams
#'
#' Insert new streams and update existing streams
#'
#' @param connection DBI connection object.
#' @param streams Tibble returned by get_streams().
#'
#' @return Named list containing rows_inserted and rows_updated.
upsert_streams <- function(
  connection,
  streams
) {
  stop("Not yet implemented")
}
