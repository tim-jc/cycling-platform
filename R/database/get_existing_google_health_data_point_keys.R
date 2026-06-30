#' Get Existing Google Health Heart Rate Response Keys
#'
#' Return existing Google Health heart-rate raw response keys.
#'
#' @param connection DBI connection object.
#' @param heart_rate_responses Incoming heart-rate response rows.
#'
#' @return Tibble of existing natural keys.
get_existing_google_health_data_point_keys <- function(
  connection,
  heart_rate_responses
) {
  if (nrow(heart_rate_responses) == 0) {
    return(
      tibble::tibble(
        source_id = integer(),
        fitbit_user_id = character(),
        activity_date = as.Date(character()),
        detail_level = character()
      )
    )
  }

  key_rows <- heart_rate_responses[
    c(
      "source_id",
      "fitbit_user_id",
      "activity_date",
      "detail_level"
    )
  ] |>
    unique()

  sql <- "
    SELECT
      source_id,
      fitbit_user_id,
      activity_date,
      detail_level
    FROM cycling_platform_raw.google_health_heart_rate_responses
    WHERE source_id = ?
      AND fitbit_user_id = ?
      AND activity_date = ?
      AND detail_level = ?
  "

  purrr::map_dfr(
    seq_len(nrow(key_rows)),
    \(i) {
      DBI::dbGetQuery(
        connection,
        sql,
        params = list(
          key_rows$source_id[[i]],
          key_rows$fitbit_user_id[[i]],
          key_rows$activity_date[[i]],
          key_rows$detail_level[[i]]
        )
      )
    }
  ) |>
    dplyr::mutate(
      source_id = as.integer(source_id),
      fitbit_user_id = as.character(fitbit_user_id),
      activity_date = as.Date(activity_date),
      detail_level = as.character(detail_level)
    )
}
