#' Insert streams
#'
#' Function to insert new streams into the database
#'
#' @param connection Database connection.
#' @param streams Tibble of streams to insert.
#'
#' @return Number of rows inserted.
insert_streams <- function(
  connection,
  streams
) {
  if (nrow(streams) == 0) {
    return(0L)
  }

  DBI::dbWriteTable(
    conn = connection,
    name = DBI::Id(
      schema = "cycling_platform_raw",
      table = "activity_streams"
    ),
    value = streams,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(streams)
}
