#' Get Existing Stream Keys
#'
#' Function to return which stream keys (activity_id + stream_type pairs)
#' are present in the database for a given set of activity_ids
#'
#' @param connection Database connection.
#' @param activity_ids Vector of activity IDs to check
#'
#' @return Tibble of activity ID / stream_type pairs present in the database
get_existing_stream_keys <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(
      tibble::tibble(
        activity_id = bit64::integer64(),
        stream_type = character()
      )
    )
  }

  placeholders <- paste(
    rep("?", length(activity_ids)),
    collapse = ", "
  )

  sql <- paste0(
    "SELECT activity_id, stream_type
     FROM cycling_platform_raw.activity_streams
     WHERE activity_id IN (",
    placeholders,
    ")"
  )

  DBI::dbGetQuery(
    connection,
    sql,
    params = as.list(
      unname(activity_ids)
    )
  ) |>
    dplyr::mutate(
      stream_type = as.character(stream_type)
    )
}
