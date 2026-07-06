#' Truncate Stage Tables
#'
#' Removes all data from one or more stage tables.
#'
#' @param connection DBI connection.
#' @param table_names Optional stage table names. Defaults to all known tables.
#' @param force Must be TRUE to confirm destructive truncation.
#'
#' @return Invisibly returns NULL.
truncate_stage_tables <- function(
  connection,
  table_names = NULL,
  force = FALSE
) {
  if (!isTRUE(force)) {
    stop(
      "truncate_stage_tables() is destructive; call with force = TRUE.",
      call. = FALSE
    )
  }

  table_names <- validate_stage_tables(table_names)

  lapply(
    table_names,
    \(table_name) {
      DBI::dbExecute(
        conn = connection,
        statement = paste0(
          "TRUNCATE TABLE cycling_platform_stage.",
          table_name
        )
      )
    }
  )

  invisible(NULL)
}
