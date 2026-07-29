get_unresolved_activity_gear_ids <- function(
  connection,
  retry_days = 30L
) {
  stopifnot(retry_days >= 0)

  DBI::dbGetQuery(
    connection,
    glue::glue("
      SELECT DISTINCT activities.gear_id
      FROM cycling_platform_raw.activities activities
      LEFT JOIN cycling_platform_raw.gear_observations observations
        ON observations.gear_id = activities.gear_id
      LEFT JOIN cycling_platform_raw.gear_resolution_attempts attempts
        ON attempts.gear_id = activities.gear_id
       AND attempts.attempted_at = (
         SELECT MAX(latest_attempt.attempted_at)
         FROM cycling_platform_raw.gear_resolution_attempts latest_attempt
         WHERE latest_attempt.gear_id = activities.gear_id
       )
      WHERE activities.gear_id IS NOT NULL
        AND activities.gear_id <> ''
        AND observations.gear_id IS NULL
        AND (
          attempts.attempted_at IS NULL
          OR attempts.attempted_at
            < UTC_TIMESTAMP() - INTERVAL {as.integer(retry_days)} DAY
        )
      ORDER BY activities.gear_id
    ")
  )$gear_id
}

#' Ingest current and activity-referenced historical Strava gear
ingest_gear <- function(connection, run_id, source_id, config) {
  run_entity_id <- create_etl_run_entity(
    connection = connection,
    run_id = run_id,
    entity_name = "gear"
  )

  endpoint_run_id <- create_api_endpoint_run(
    connection = connection,
    run_id = run_id,
    source_id = source_id,
    entity_name = "gear",
    endpoint_name = "GET /athlete + GET /gear/{id}"
  )

  tryCatch(
    {
      result <- get_gear(
        run_id = run_id,
        source_id = source_id,
        activity_gear_ids = get_unresolved_activity_gear_ids(
          connection,
          retry_days = if (is.null(
            config$ingestion$gear_resolution_retry_days
          )) {
            30L
          } else {
            config$ingestion$gear_resolution_retry_days
          }
        ),
        config = config
      )

      load_result <- DBI::dbWithTransaction(
        connection,
        {
          loaded <- upsert_gear_observations(
            connection,
            result$observations
          )

          if (nrow(result$unresolved) > 0) {
            attempts <- dplyr::mutate(
              result$unresolved,
              run_id = run_id,
              .before = "resolution_status"
            )

            DBI::dbWriteTable(
              connection,
              DBI::Id(
                schema = "cycling_platform_raw",
                table = "gear_resolution_attempts"
              ),
              attempts,
              append = TRUE
            )
          }

          loaded
        }
      )

      update_etl_run_entity(
        connection = connection,
        run_entity_id = run_entity_id,
        entity_status = "SUCCESS",
        rows_inserted = load_result$rows_inserted,
        rows_updated = load_result$rows_unchanged
      )

      update_api_endpoint_run(
        connection = connection,
        endpoint_run_id = endpoint_run_id,
        run_status = "SUCCESS",
        http_request_count = result$request_count,
        source_record_count = result$source_records,
        historical_lookup_count = result$historical_lookup_count,
        rows_inserted = load_result$rows_inserted,
        rows_unchanged = load_result$rows_unchanged,
        unresolved_identifier_count = nrow(result$unresolved)
      )

      message(glue::glue(
        "Gear ingestion complete: {result$source_records} current, ",
        "{result$historical_lookup_count} historical lookups, ",
        "{load_result$rows_inserted} observations inserted, ",
        "{load_result$rows_unchanged} unchanged, ",
        "{nrow(result$unresolved)} unresolved, ",
        "{result$request_count} HTTP requests."
      ))

      invisible(c(result, load_result))
    },
    error = function(e) {
      update_api_endpoint_run(
        connection = connection,
        endpoint_run_id = endpoint_run_id,
        run_status = "FAILED",
        error_message = conditionMessage(e)
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
}
