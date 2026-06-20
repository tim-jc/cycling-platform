#' Insert streams
#'
#' Function to insert new streams into the database
#'
#' @param connection Database connection.
#' @param streams Tibble of activities to insert.
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
    name = "activity_streams",
    value = streams,
    append = TRUE,
    overwrite = FALSE
  )

  nrow(streams)
}
