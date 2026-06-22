#' Update Activity Details
#'
#' Update existing activity details.
#'
#' @param connection Database connection.
#' @param activity_details Tibble of activity details to update.
#'
#' @return Integer count of updated rows.
update_activity_details <- function(
  connection,
  activity_details
) {
  key_column <- "activity_id"

  update_columns <- setdiff(
    names(activity_details),
    key_column
  )

  set_clause <- paste(
    paste0(update_columns, " = ?"),
    collapse = ", "
  )

  sql <- glue::glue(
    "
    UPDATE cycling_platform_raw.activity_details
    SET {set_clause}
    WHERE {key_column} = ?
    "
  )

  purrr::walk(
    seq_len(nrow(activity_details)),
    \(i) {
      row <- activity_details[i, ]

      params <- c(
        unname(as.list(row[update_columns])),
        list(row[[key_column]])
      )

      DBI::dbExecute(
        conn = connection,
        statement = sql,
        params = params
      )
    }
  )

  nrow(activity_details)
}
