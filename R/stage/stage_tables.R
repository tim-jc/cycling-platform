#' Stage Table Registry
#'
#' @return Character vector of known stage table names.
stage_tables <- function() {
  c(
    "activity_streams_build"
  )
}

#' Validate Stage Table Names
#'
#' @param table_names Optional character vector of stage table names.
#'
#' @return Validated character vector.
validate_stage_tables <- function(table_names = NULL) {
  known_tables <- stage_tables()

  if (is.null(table_names)) {
    return(known_tables)
  }

  unknown_tables <- setdiff(
    table_names,
    known_tables
  )

  if (length(unknown_tables) > 0) {
    stop(
      "Unknown stage table(s): ",
      paste(unknown_tables, collapse = ", "),
      call. = FALSE
    )
  }

  table_names
}
