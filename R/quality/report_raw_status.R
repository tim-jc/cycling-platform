#' Report Raw Status
#'
#' Return and print a compact operational summary of raw ingestion state.
#'
#' @param connection Database connection.
#'
#' @return Named list of data frames.
report_raw_status <- function(connection) {
  get_query <- function(sql) {
    DBI::dbGetQuery(
      conn = connection,
      statement = sql
    )
  }

  latest_run <- get_query(
    "
    SELECT
      run_id,
      source_id,
      run_mode,
      run_status,
      started_at,
      completed_at,
      duration_seconds,
      error_message
    FROM cycling_platform_admin.etl_run
    ORDER BY run_id DESC
    LIMIT 1
    "
  )

  recent_failed_entities <- get_query(
    "
    SELECT
      run_entity_id,
      run_id,
      entity_name,
      entity_status,
      rows_inserted,
      rows_updated,
      started_at,
      completed_at,
      error_message
    FROM cycling_platform_admin.etl_run_entity
    WHERE entity_status = 'FAILED'
    ORDER BY run_entity_id DESC
    LIMIT 10
    "
  )

  stream_status_counts <- get_query(
    "
    SELECT
      stream_status,
      COUNT(*) AS activity_count
    FROM cycling_platform_raw.activities
    GROUP BY stream_status
    ORDER BY stream_status
    "
  )

  detail_status_counts <- get_query(
    "
    SELECT
      details_status,
      COUNT(*) AS activity_count
    FROM cycling_platform_raw.activities
    GROUP BY details_status
    ORDER BY details_status
    "
  )

  lap_status_counts <- get_query(
    "
    SELECT
      laps_status,
      COUNT(*) AS activity_count
    FROM cycling_platform_raw.activities
    GROUP BY laps_status
    ORDER BY laps_status
    "
  )

  raw_row_counts <- get_query(
    "
    SELECT 'activities' AS table_name, COUNT(*) AS row_count
    FROM cycling_platform_raw.activities
    UNION ALL
    SELECT 'activity_streams' AS table_name, COUNT(*) AS row_count
    FROM cycling_platform_raw.activity_streams
    UNION ALL
    SELECT 'activity_details' AS table_name, COUNT(*) AS row_count
    FROM cycling_platform_raw.activity_details
    UNION ALL
    SELECT 'activity_laps' AS table_name, COUNT(*) AS row_count
    FROM cycling_platform_raw.activity_laps
    "
  )

  summary <- list(
    latest_run = latest_run,
    recent_failed_entities = recent_failed_entities,
    stream_status_counts = stream_status_counts,
    detail_status_counts = detail_status_counts,
    lap_status_counts = lap_status_counts,
    raw_row_counts = raw_row_counts
  )

  message("Latest ETL run")
  print(latest_run)

  message("Stream status counts")
  print(stream_status_counts)

  message("Detail status counts")
  print(detail_status_counts)

  message("Lap status counts")
  print(lap_status_counts)

  message("Raw row counts")
  print(raw_row_counts)

  message("Recent failed entity runs")
  print(recent_failed_entities)

  invisible(summary)
}
