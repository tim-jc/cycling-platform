#' Remove Stage Data For A Run
#'
#' Deletes rows owned by a specific run_id from one or more stage tables.
#'
#' @param connection DBI connection.
#' @param run_id ETL run identifier.
#' @param table_names Optional stage table names. Defaults to all known tables.
#'
#' @return Data frame of deleted row counts.
remove_stage_run_data <- function(
  connection,
  run_id,
  table_names = NULL
) {
  stopifnot(!is.null(run_id))

  table_names <- validate_stage_tables(table_names)

  results <- lapply(
    table_names,
    \(table_name) {
      rows_deleted <- DBI::dbExecute(
        conn = connection,
        statement = paste0(
          "DELETE FROM cycling_platform_stage.",
          table_name,
          " WHERE run_id = ?"
        ),
        params = list(run_id)
      )

      data.frame(
        table_name = table_name,
        run_id = as.character(run_id),
        rows_deleted = rows_deleted
      )
    }
  )

  do.call(rbind, results)
}
