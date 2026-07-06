#' Remove Old Stage Data
#'
#' Deletes stage rows older than a configured retention window.
#'
#' @param connection DBI connection.
#' @param retention_days Positive integer retention window.
#' @param table_names Optional stage table names. Defaults to all known tables.
#'
#' @return Data frame of deleted row counts.
remove_old_stage_data <- function(
  connection,
  retention_days,
  table_names = NULL
) {
  stopifnot(retention_days > 0)

  table_names <- validate_stage_tables(table_names)

  cutoff_time <- Sys.time() - (as.integer(retention_days) * 86400)

  results <- lapply(
    table_names,
    \(table_name) {
      rows_deleted <- DBI::dbExecute(
        conn = connection,
        statement = paste0(
          "DELETE FROM cycling_platform_stage.",
          table_name,
          " WHERE staged_at < ?"
        ),
        params = list(cutoff_time)
      )

      data.frame(
        table_name = table_name,
        retention_days = as.integer(retention_days),
        rows_deleted = rows_deleted
      )
    }
  )

  do.call(rbind, results)
}
