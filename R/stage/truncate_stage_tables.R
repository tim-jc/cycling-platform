#' Truncate Stage Tables
#'
#' Removes all data from one or more stage tables.
#'
#' @param connection DBI connection.
#' @param table_names Optional stage table names. Defaults to all known tables.
#'
#' @return Invisibly returns NULL.
truncate_stage_tables <- function(
  connection,
  table_names = NULL
) {
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
