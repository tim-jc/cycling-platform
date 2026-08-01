#' Ingest activities
#'
#' Orchestrates the end-to-end ingestion of Strava activities.
#'
#' @param
#' @param run_id Integer ETL run identifier.
#' @param source_id Data source ID for the ingestion.
#' @param refresh_days Integer number of days to refresh.
#'
#' @return invisible(NULL)
ingest_activities <- function(
  connection,
  run_id,
  source_id,
  refresh_days,
  config
) {
  run_entity_id <- create_etl_run_entity(
    connection = connection,
    run_id = run_id,
    entity_name = "activities"
  )

  tryCatch(
    {
      activities <- get_activities(
        run_id = run_id,
        source_id = source_id,
        refresh_days = refresh_days,
        config = config
      )

      execute_sql_file("sql/admin/070_create_activity_reconciliation.sql", connection)
      baseline <- get_activity_reconciliation_baseline(connection, refresh_days)
      reconciliation <- classify_activity_summaries(activities, baseline)

      result <- DBI::dbWithTransaction(
        conn = connection,
        {
          upsert_result <- upsert_activities(
            connection = connection,
            activities = activities,
            reconciliation = reconciliation
          )
          changed_ids <- reconciliation$activity_id[reconciliation$reconciliation_status == "CHANGED"]
          mark_changed_activity_children_pending(connection, changed_ids)
          record_activity_reconciliation(connection, run_id, reconciliation)
          upsert_result
        }
      )

      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "SUCCESS",
        rows_inserted = result$rows_inserted,
        rows_updated = result$rows_updated
      )

      message(glue::glue(
        "Activity reconciliation: examined {sum(reconciliation$source_present)}, ",
        "new {sum(reconciliation$reconciliation_status == 'NEW')}, changed {sum(reconciliation$reconciliation_status == 'CHANGED')}, ",
        "unchanged {sum(reconciliation$reconciliation_status == 'UNCHANGED')}, missing {sum(reconciliation$reconciliation_status == 'MISSING')}."
      ))

      invisible(reconciliation)
    },

    error = function(e) {
      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "FAILED",
        error_message = conditionMessage(e)
      )

      stop(e)
    }
  )
}
