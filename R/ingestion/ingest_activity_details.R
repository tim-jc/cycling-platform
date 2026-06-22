#' Ingest Activity Details
#'
#' Orchestrates end-to-end ingestion of Strava activity details
#'
#' @param connection Database connection.
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param activity_ids Integer64 vector of activity IDs.
#' @param config Platform configuration.
#'
#' @return invisible(NULL)
ingest_activity_details <- function(
  connection,
  run_id,
  source_id,
  activity_ids,
  config
) {
  run_entity_id <- create_etl_run_entity(
    connection = connection,
    run_id = run_id,
    entity_name = "activity_details"
  )

  tryCatch(
    {
      activity_details_result <- get_activity_details(
        run_id = run_id,
        source_id = source_id,
        activity_ids = activity_ids,
        config = config
      )

      activity_details <- activity_details_result$details

      not_found_ids <- activity_details_result$not_found_ids

      result <- DBI::dbWithTransaction(
        conn = connection,

        {
          upsert_result <- upsert_activity_details(
            connection = connection,
            activity_details = activity_details
          )

          successful_ids <- unique(
            activity_details$activity_id
          )

          update_activity_details_status(
            connection = connection,
            activity_ids = successful_ids,
            details_status = "SUCCESS"
          )

          update_activity_details_status(
            connection = connection,
            activity_ids = not_found_ids,
            details_status = "NOT_FOUND"
          )

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
    },

    error = function(e) {
      update_activity_details_status(
        connection = connection,
        activity_ids = activity_ids,
        details_status = "FAILED"
      )

      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "FAILED",
        error_message = conditionMessage(e)
      )

      stop(e)
    }
  )

  invisible(NULL)
}
