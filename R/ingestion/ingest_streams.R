#' Ingest Streams
#'
#' Orchestrates end-to-end ingestion of Strava activity streams.
#'
#' @param connection Database connection.
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param activity_ids Integer vector of activity IDs.
#' @param config Platform configuration.
#'
#' @return invisible(NULL)
ingest_streams <- function(
  connection,
  run_id,
  source_id,
  activity_ids,
  config
) {
  run_entity_id <- create_etl_run_entity(
    connection = connection,
    run_id = run_id,
    entity_name = "activity_streams"
  )

  tryCatch(
    {
      streams <- get_streams(
        run_id = run_id,
        source_id = source_id,
        activity_ids = activity_ids,
        config = config
      )

      if (nrow(streams) == 0) {
        update_etl_run_entity(
          connection = connection,
          run_entity_id = run_entity_id,
          entity_status = "SUCCESS",
          rows_inserted = 0L,
          rows_updated = 0L
        )

        return(invisible(NULL))
      }

      result <- DBI::dbWithTransaction(
        conn = connection,
        {
          upsert_streams(
            connection = connection,
            streams = streams
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

  invisible(NULL)
}
