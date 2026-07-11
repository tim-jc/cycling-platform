ingest_google_health_daily_resting_heart_rate <- function(
  connection,
  run_id,
  source_id,
  config,
  start_date,
  end_date
) {
  run_entity_id <- create_etl_run_entity(
    connection = connection,
    run_id = run_id,
    entity_name = "google_health_daily_resting_heart_rate"
  )

  batch_size <- config$ingestion$google_health_date_batch_size

  if (is.null(batch_size)) {
    batch_size <- 1L
  }

  stopifnot(batch_size > 0)

  date_windows <- build_google_health_date_windows(
    start_date = start_date,
    end_date = end_date
  )

  date_batches <- chunk_vector(
    seq_len(nrow(date_windows)),
    batch_size
  )

  rows_inserted <- 0L
  rows_updated <- 0L

  tryCatch(
    {
      for (i in seq_along(date_batches)) {
        batch_indexes <- date_batches[[i]]

        batch_windows <- date_windows[
          batch_indexes,
          ,
          drop = FALSE
        ]

        message(glue::glue(
          "Processing Google Health daily resting heart-rate batch ",
          "{i}/{length(date_batches)} ",
          "({nrow(batch_windows)} dates)."
        ))

        batch_rows <- purrr::pmap_dfr(
          batch_windows,
          \(date, start_datetime, end_datetime) {
            message(glue::glue(
              "Retrieving Google Health daily resting heart rate for {date}."
            ))

            requested_start_date <- as.Date(date)
            requested_end_date <- as.Date(date) + 1L

            request_rows <- tryCatch(
              get_google_health_daily_resting_heart_rate(
                run_id = run_id,
                source_id = source_id,
                start_date = requested_start_date,
                end_date = requested_end_date,
                config = config
              ),
              error = function(e) {
                record_etl_request_log(
                  connection = connection,
                  run_id = run_id,
                  run_entity_id = run_entity_id,
                  entity_name = "google_health_daily_resting_heart_rate",
                  request_status = "FAILED",
                  requested_start_date = requested_start_date,
                  requested_end_date = requested_end_date,
                  returned_data_point_count = 0L,
                  error_message = conditionMessage(e)
                )

                stop(e)
              }
            )

            record_etl_request_log(
              connection = connection,
              run_id = run_id,
              run_entity_id = run_entity_id,
              entity_name = "google_health_daily_resting_heart_rate",
              request_status = "SUCCESS",
              requested_start_date = requested_start_date,
              requested_end_date = requested_end_date,
              returned_data_point_count = nrow(request_rows),
              retrieved_at = Sys.time()
            )

            request_rows
          }
        )

        batch_result <- DBI::dbWithTransaction(
          conn = connection,
          {
            upsert_google_health_daily_resting_heart_rate(
              connection = connection,
              daily_resting_heart_rate = batch_rows
            )
          }
        )

        rows_inserted <- rows_inserted + batch_result$rows_inserted
        rows_updated <- rows_updated + batch_result$rows_updated

        message(glue::glue(
          "Completed Google Health daily resting heart-rate batch ",
          "{i}/{length(date_batches)}: ",
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
