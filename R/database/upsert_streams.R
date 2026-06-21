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
  if (nrow(streams) == 0) {
    return(
      list(
        rows_inserted = 0L,
        rows_updated = 0L
      )
    )
  }

  existing_keys <- get_existing_stream_keys(
    connection = connection,
    activity_ids = unique(streams$activity_id)
  )

  # Split incoming data
  streams_to_insert <- dplyr::anti_join(
    streams,
    existing_keys,
    by = c("activity_id", "stream_type")
  )

  streams_to_update <- dplyr::semi_join(
    streams,
    existing_keys,
    by = c("activity_id", "stream_type")
  )

  rows_inserted <- 0L
  rows_updated <- 0L

  # Insert new streams
  if (nrow(streams_to_insert) > 0) {
    rows_inserted <- insert_streams(
      connection = connection,
      streams = streams_to_insert
    )
  }

  # Update existing streams
  if (nrow(streams_to_update) > 0) {
    rows_updated <- update_streams(
      connection = connection,
      streams = streams_to_update
    )
  }

  list(
    rows_inserted = rows_inserted,
    rows_updated = rows_updated
  )
}
