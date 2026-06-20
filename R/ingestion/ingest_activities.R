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

      result <- DBI::dbWithTransaction(
        conn = connection,
        {
          upsert_activities(
            connection = connection,
            activities = activities
          )
        }
      )

      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "SUCCESS",
        rows_inserted = result$rows_inserted,
        rows_updated = result$rows_updated
      )
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
