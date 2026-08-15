ingest_google_health_exercise <- function(
  connection,
  run_id,
  source_id,
  config,
  start_date,
  end_date,
  exercise_fetcher = get_google_health_exercise
) {
  started_at <- Sys.time()
  run_entity_id <- create_etl_run_entity(
    connection = connection,
    run_id = run_id,
    entity_name = "google_health_exercise"
  )
  batch_size <- config$ingestion$google_health_date_batch_size %||% 1L
  stopifnot(batch_size > 0L)
  date_windows <- build_google_health_date_windows(start_date, end_date)
  date_batches <- chunk_vector(seq_len(nrow(date_windows)), batch_size)
  rows_inserted <- 0L
  rows_unchanged <- 0L
  source_records <- 0L
  request_count <- 0L
  page_count <- 0L

  tryCatch(
    {
      for (batch_index in seq_along(date_batches)) {
        indexes <- date_batches[[batch_index]]
        batch_rows <- google_health_empty_exercise()

        for (index in indexes) {
          window <- date_windows[index, , drop = FALSE]
          requested_start_date <- as.Date(window$date[[1]])
          requested_end_date <- requested_start_date + 1L
          message("Retrieving Google Health Exercise for ", requested_start_date, ".")

          request_rows <- tryCatch(
            exercise_fetcher(
              run_id = run_id,
              source_id = source_id,
              start_datetime = window$start_datetime[[1]],
              end_datetime = window$end_datetime[[1]],
              config = config
            ),
            error = function(e) {
              record_etl_request_log(
                connection,
                run_id,
                run_entity_id,
                "google_health_exercise",
                "FAILED",
                requested_start_date,
                requested_end_date,
                error_message = conditionMessage(e)
              )
              stop(e)
            }
          )
          window_pages <- attr(request_rows, "page_count") %||% 1L
          window_requests <- attr(request_rows, "request_count") %||% window_pages
          page_count <- page_count + as.integer(window_pages)
          request_count <- request_count + as.integer(window_requests)
          source_records <- source_records + nrow(request_rows)

          record_etl_request_log(
            connection,
            run_id,
            run_entity_id,
            "google_health_exercise",
            "SUCCESS",
            requested_start_date,
            requested_end_date,
            returned_data_point_count = nrow(request_rows),
            retrieved_at = Sys.time()
          )
          batch_rows <- dplyr::bind_rows(batch_rows, request_rows)
        }

        batch_result <- DBI::dbWithTransaction(
          conn = connection,
          {
            upsert_google_health_exercise(connection, batch_rows)
          }
        )
        rows_inserted <- rows_inserted + batch_result$rows_inserted
        rows_unchanged <- rows_unchanged + batch_result$rows_unchanged
        message(
          "Completed Google Health Exercise batch ",
          batch_index,
          "/",
          length(date_batches),
          ": ",
          batch_result$rows_inserted,
          " inserted, ",
          batch_result$rows_unchanged,
          " unchanged."
        )
      }

      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "SUCCESS",
        rows_inserted = rows_inserted,
        rows_updated = 0L
      )
      elapsed_seconds <- as.numeric(difftime(Sys.time(), started_at, units = "secs"))
      message(
        "Google Health Exercise complete: requests=", request_count,
        "; pages=", page_count,
        "; source_records=", source_records,
        "; inserted=", rows_inserted,
        "; unchanged=", rows_unchanged,
        "; elapsed=", format_platform_duration(elapsed_seconds),
        "."
      )
    },
    error = function(e) {
      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "FAILED",
        rows_inserted = rows_inserted,
        rows_updated = 0L,
        error_message = conditionMessage(e)
      )
      stop(e)
    }
  )

  invisible(list(
    request_count = request_count,
    page_count = page_count,
    source_records = source_records,
    rows_inserted = rows_inserted,
    rows_updated = 0L,
    rows_unchanged = rows_unchanged,
    elapsed_seconds = as.numeric(difftime(Sys.time(), started_at, units = "secs"))
  ))
}
