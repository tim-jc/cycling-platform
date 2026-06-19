#' Update Activities
#'
#' Update existing activities.
#'
#' @param connection Database connection.
#' @param activities Tibble of activities to update.
#'
#' @return Integer count of updated rows.
update_activities <- function(
  connection,
  activities
) {
  key_column <- "activity_id"

  update_columns <- setdiff(
    names(activities),
    key_column
  )

  set_clause <- paste(
    paste0(update_columns, " = ?"),
    collapse = ", "
  )

  sql <- glue::glue(
    "
    UPDATE cycling_platform_raw.activities
    SET {set_clause}
    WHERE {key_column} = ?
    "
  )

  purrr::walk(
    seq_len(nrow(activities)),
    \(i) {
      row <- activities[i, ]

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

  nrow(activities)
}
