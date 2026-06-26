#' Ingest Activity Laps
#'
#' Orchestrates end-to-end ingestion of Strava activity laps.
#'
#' @param connection Database connection.
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param activity_ids Integer64 vector of activity IDs.
#' @param config Platform configuration.
#'
#' @return invisible(NULL)
ingest_activity_laps <- function(
  connection,
  run_id,
  source_id,
  activity_ids,
  config
) {
  run_entity_id <- create_etl_run_entity(
    connection = connection,
    run_id = run_id,
    entity_name = "activity_laps"
  )

  batch_size <- config$ingestion$lap_activity_batch_size

  if (is.null(batch_size)) {
    batch_size <- 25
  }

  stopifnot(batch_size > 0)

  activity_id_batches <- chunk_vector(
    activity_ids,
    batch_size
  )

  current_batch <- NA_integer_

  completed_batches <- 0L

  rows_inserted <- 0L

  rows_updated <- 0L

  tryCatch(
    {
      for (i in seq_along(activity_id_batches)) {
        current_batch <- i

        batch_activity_ids <- activity_id_batches[[i]]

        message(glue::glue(
          "Processing activity lap batch {i}/{length(activity_id_batches)} ",
          "({length(batch_activity_ids)} activities)."
        ))

        activity_laps_result <- get_activity_laps(
          run_id = run_id,
          source_id = source_id,
          activity_ids = batch_activity_ids,
          config = config
        )

        activity_laps <- activity_laps_result$laps

        not_found_ids <- activity_laps_result$not_found_ids

        batch_result <- DBI::dbWithTransaction(
          conn = connection,

          {
            upsert_result <- upsert_activity_laps(
              connection = connection,
              activity_laps = activity_laps
            )

            successful_ids <- unique(
              activity_laps$activity_id
            )

            update_activity_laps_status(
              connection = connection,
              activity_ids = successful_ids,
              laps_status = "SUCCESS"
            )

            update_activity_laps_status(
              connection = connection,
              activity_ids = not_found_ids,
              laps_status = "NOT_FOUND"
            )

            upsert_result
          }
        )

        rows_inserted <- rows_inserted + batch_result$rows_inserted

        rows_updated <- rows_updated + batch_result$rows_updated

        completed_batches <- i

        message(glue::glue(
          "Completed activity lap batch {i}/{length(activity_id_batches)}: ",
          "{batch_result$rows_inserted} inserted, ",
          "{batch_result$rows_updated} updated."
        ))
      }

      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "SUCCESS",
        rows_inserted = rows_inserted,
        rows_updated = rows_updated
      )
    },

    error = function(e) {
      failed_ids <- bit64::integer64()

      first_failed_batch <- completed_batches + 1L

      if (first_failed_batch <= length(activity_id_batches)) {
        failed_ids <- do.call(
          c,
          activity_id_batches[first_failed_batch:length(activity_id_batches)]
        )

        failed_ids <- unname(failed_ids)
      } else if (is.na(current_batch)) {
        failed_ids <- unname(activity_ids)
      }

      update_activity_laps_status(
        connection = connection,
        activity_ids = failed_ids,
        laps_status = "FAILED"
      )

      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "FAILED",
        rows_inserted = rows_inserted,
        rows_updated = rows_updated,
        error_message = conditionMessage(e)
      )

      stop(e)
    }
  )

  invisible(NULL)
}
