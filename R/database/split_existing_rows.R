#' Split Existing Rows
#'
#' Split incoming raw rows into insert and update sets using business keys.
#'
#' @param data Data frame of incoming rows.
#' @param existing_keys Data frame or vector of existing keys.
#' @param key_columns Character vector of key columns.
#'
#' @return Named list with `to_insert` and `to_update` data frames.
split_existing_rows <- function(
  data,
  existing_keys,
  key_columns
) {
  stopifnot(all(key_columns %in% names(data)))

  if (nrow(data) == 0) {
    return(
      list(
        to_insert = data,
        to_update = data
      )
    )
  }

  if (is.null(dim(existing_keys))) {
    stopifnot(length(key_columns) == 1)

    existing_keys <- data.frame(
      existing_keys,
      stringsAsFactors = FALSE
    )

    names(existing_keys) <- key_columns
  }

  existing_keys <- as.data.frame(
    existing_keys,
    stringsAsFactors = FALSE
  )

  existing_keys <- existing_keys[
    ,
    key_columns,
    drop = FALSE
  ]

  list(
    to_insert = dplyr::anti_join(
      data,
      existing_keys,
      by = key_columns
    ),

    to_update = dplyr::semi_join(
      data,
      existing_keys,
      by = key_columns
    )
  )
}
