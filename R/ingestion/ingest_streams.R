#' Ingest Streams
#'
#' Orchestrates end-to-end ingestion of Strava activity streams.
#'
#' @param connection Database connection.
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param activity_ids Integer64 vector of activity IDs.
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
      stream_result <- get_streams(
        run_id = run_id,
        source_id = source_id,
        activity_ids = activity_ids,
        config = config
      )

      streams <- stream_result$streams

      not_found_ids <- stream_result$not_found_ids

      result <- DBI::dbWithTransaction(
        conn = connection,

        {
          upsert_result <- upsert_streams(
            connection = connection,
            streams = streams
          )

          successful_ids <- unique(
            streams$activity_id
          )

          update_activity_stream_status(
            connection = connection,
            activity_ids = successful_ids,
            stream_status = "SUCCESS"
          )

          update_activity_stream_status(
            connection = connection,
            activity_ids = not_found_ids,
            stream_status = "NOT_FOUND"
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
      update_activity_stream_status(
        connection = connection,
        activity_ids = activity_ids,
        stream_status = "FAILED"
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
