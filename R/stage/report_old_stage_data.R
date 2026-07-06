#' Report Old Stage Data
#'
#' Reports stage rows older than a configured retention window without deleting
#' them.
#'
#' @param connection DBI connection.
#' @param retention_days Positive integer retention window.
#' @param table_names Optional stage table names. Defaults to all known tables.
#'
#' @return Data frame summarising old stage data.
report_old_stage_data <- function(
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
      DBI::dbGetQuery(
        conn = connection,
        statement = paste0(
          "
          SELECT
            '", table_name, "' AS table_name,
            run_id,
            COUNT(*) AS row_count,
            MIN(staged_at) AS oldest_staged_at,
            MAX(staged_at) AS newest_staged_at
          FROM cycling_platform_stage.", table_name, "
          WHERE staged_at < ?
          GROUP BY
            run_id
          ORDER BY
            oldest_staged_at,
            run_id
          "
        ),
        params = list(cutoff_time)
      )
    }
  )

  do.call(rbind, results)
}
