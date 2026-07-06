#' Report Orphaned Stage Data
#'
#' Reports stage data that is not owned by a running ETL run.
#'
#' @param connection DBI connection.
#' @param table_names Optional stage table names. Defaults to all known tables.
#'
#' @return Data frame summarising orphaned stage data.
report_orphaned_stage_data <- function(
  connection,
  table_names = NULL
) {
  table_names <- validate_stage_tables(table_names)

  results <- lapply(
    table_names,
    \(table_name) {
      DBI::dbGetQuery(
        conn = connection,
        statement = paste0(
          "
          SELECT
            '", table_name, "' AS table_name,
            stage.run_id,
            COALESCE(etl.run_status, 'MISSING_RUN') AS run_status,
            COUNT(*) AS row_count,
            MIN(stage.staged_at) AS oldest_staged_at,
            MAX(stage.staged_at) AS newest_staged_at
          FROM cycling_platform_stage.", table_name, " stage
          LEFT JOIN cycling_platform_admin.etl_run etl
            ON etl.run_id = stage.run_id
          WHERE etl.run_id IS NULL
             OR etl.run_status <> 'RUNNING'
          GROUP BY
            stage.run_id,
            COALESCE(etl.run_status, 'MISSING_RUN')
          ORDER BY
            oldest_staged_at,
            stage.run_id
          "
        )
      )
    }
  )

  do.call(rbind, results)
}
