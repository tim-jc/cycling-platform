#' Get Existing Google Health Sleep Log Keys
#'
#' Return existing Google Health raw sleep log keys.
#'
#' @param connection DBI connection object.
#' @param sleep_log_keys Character vector of sleep log keys.
#'
#' @return Tibble of existing sleep log keys.
get_existing_google_health_sleep_log_keys <- function(
  connection,
  sleep_log_keys
) {
  if (length(sleep_log_keys) == 0) {
    return(
      tibble::tibble(
        sleep_log_key = character()
      )
    )
  }

  placeholders <- paste(
    rep("?", length(sleep_log_keys)),
    collapse = ", "
  )

  sql <- paste0(
    "SELECT sleep_log_key
     FROM cycling_platform_raw.google_health_sleep_logs
     WHERE sleep_log_key IN (",
    placeholders,
    ")"
  )

  DBI::dbGetQuery(
    connection,
    sql,
    params = as.list(
      unname(sleep_log_keys)
    )
  ) |>
    dplyr::mutate(
      sleep_log_key = as.character(sleep_log_key)
    )
}
