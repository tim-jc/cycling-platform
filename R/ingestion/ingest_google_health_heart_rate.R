#' Build Google Health Date Windows
#'
#' @param start_date Inclusive start date.
#' @param end_date Inclusive end date.
#'
#' @return Data frame with date, start_datetime, and end_datetime.
build_google_health_date_windows <- function(
  start_date,
  end_date
) {
  start_date <- as.Date(start_date)
  end_date <- as.Date(end_date)

  stopifnot(!is.na(start_date))
  stopifnot(!is.na(end_date))
  stopifnot(start_date <= end_date)

  dates <- seq.Date(
    from = start_date,
    to = end_date,
    by = "day"
  )

  tibble::tibble(
    date = dates,
    start_datetime = as.POSIXct(
      paste0(dates, " 00:00:00"),
      tz = "UTC"
    ),
    end_datetime = as.POSIXct(
      paste0(dates + 1L, " 00:00:00"),
      tz = "UTC"
    )
  )
}

#' Ingest Google Health Heart Rate
#'
#' Orchestrates raw ingestion of Google Health heart-rate data points.
#'
#' @param connection Database connection.
#' @param run_id Integer ETL run identifier.
#' @param source_id Integer source identifier.
#' @param config Platform configuration.
#' @param start_date Inclusive start date.
#' @param end_date Inclusive end date.
#'
#' @return invisible(NULL)
ingest_google_health_heart_rate <- function(
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
    entity_name = "google_health_heart_rate"
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
          "Processing Google Health heart-rate batch ",
          "{i}/{length(date_batches)} ",
          "({nrow(batch_windows)} dates)."
        ))

        batch_data_points <- purrr::pmap_dfr(
          batch_windows,
          \(date, start_datetime, end_datetime) {
            message(glue::glue(
              "Retrieving Google Health heart-rate data for {date}."
            ))

            get_google_health_heart_rate(
              run_id = run_id,
              source_id = source_id,
              start_datetime = start_datetime,
              end_datetime = end_datetime,
              config = config
            )
          }
        )

        batch_result <- DBI::dbWithTransaction(
          conn = connection,

          {
            upsert_google_health_data_points(
              connection = connection,
              data_points = batch_data_points
            )
          }
        )

        rows_inserted <- rows_inserted + batch_result$rows_inserted

        rows_updated <- rows_updated + batch_result$rows_updated

        message(glue::glue(
          "Completed Google Health heart-rate batch ",
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
