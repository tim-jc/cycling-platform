#' Get Existing Google Health Data Point Keys
#'
#' Return existing Google Health raw data point keys.
#'
#' @param connection DBI connection object.
#' @param data_point_keys Character vector of data point keys.
#'
#' @return Tibble of existing data point keys.
get_existing_google_health_data_point_keys <- function(
  connection,
  data_point_keys
) {
  if (length(data_point_keys) == 0) {
    return(
      tibble::tibble(
        data_point_key = character()
      )
    )
  }

  placeholders <- paste(
    rep("?", length(data_point_keys)),
    collapse = ", "
  )

  sql <- paste0(
    "SELECT data_point_key
     FROM cycling_platform_raw.google_health_data_points
     WHERE data_point_key IN (",
    placeholders,
    ")"
  )

  DBI::dbGetQuery(
    connection,
    sql,
    params = as.list(
      unname(data_point_keys)
    )
  ) |>
    dplyr::mutate(
      data_point_key = as.character(data_point_key)
    )
}
