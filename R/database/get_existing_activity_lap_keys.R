#' Get Existing Activity Lap Keys
#'
#' Return activity/lap keys already present in raw activity laps.
#'
#' @param connection Database connection.
#' @param activity_ids Vector of activity IDs to check.
#'
#' @return Tibble of activity_id and lap_index pairs.
get_existing_activity_lap_keys <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(
      tibble::tibble(
        activity_id = bit64::integer64(),
        lap_index = integer()
      )
    )
  }

  placeholders <- paste(
    rep("?", length(activity_ids)),
    collapse = ", "
  )

  sql <- paste0(
    "SELECT activity_id, lap_index
     FROM cycling_platform_raw.activity_laps
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
      lap_index = as.integer(lap_index)
    )
}
