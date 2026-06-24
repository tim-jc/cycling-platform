#' Get Silver Stream Activity IDs
#'
#' Return activity IDs with raw stream data.
#'
#' @param connection Database connection.
#'
#' @return Vector of activity IDs.
get_silver_stream_activity_ids <- function(connection) {
  activity_ids <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      SELECT activity_id
      FROM cycling_platform_raw.activity_streams
      GROUP BY activity_id
      ORDER BY activity_id
    "
  )

  activity_ids$activity_id
}

#' Get Silver Stream Repair Activity IDs
#'
#' Return activity IDs where silver stream rows are missing or incomplete.
#'
#' @param connection Database connection.
#'
#' @return Vector of activity IDs.
get_silver_stream_repair_activity_ids <- function(connection) {
  activity_ids <- DBI::dbGetQuery(
    conn = connection,
    statement = "
      WITH raw_summary AS (
          SELECT
              activity_id,
              MAX(original_size) AS expected_row_count
          FROM cycling_platform_raw.activity_streams
          GROUP BY activity_id
      ),
      silver_summary AS (
          SELECT
              activity_id,
              COUNT(*) AS actual_row_count
          FROM cycling_platform_silver.activity_streams
          GROUP BY activity_id
      )
      SELECT raw_summary.activity_id
      FROM raw_summary
      LEFT JOIN silver_summary
          ON silver_summary.activity_id = raw_summary.activity_id
      WHERE COALESCE(silver_summary.actual_row_count, 0)
          <> raw_summary.expected_row_count
      ORDER BY raw_summary.activity_id
    "
  )

  activity_ids$activity_id
}

#' Format Activity ID Filter
#'
#' Format activity IDs for use in SQL IN clauses.
#'
#' @param activity_ids Activity IDs.
#'
#' @return Comma-separated activity IDs.
format_activity_id_filter <- function(activity_ids) {
  activity_ids_sql <- as.character(activity_ids)

  if (any(!grepl("^[0-9]+$", activity_ids_sql))) {
    stop("Activity IDs must contain digits only.", call. = FALSE)
  }

  paste(
    activity_ids_sql,
    collapse = ", "
  )
}

#' Delete Silver Activity Streams
#'
#' Delete existing silver stream samples for activity IDs.
#'
#' @param connection Database connection.
#' @param activity_ids Activity IDs.
#'
#' @return Number of rows deleted.
delete_silver_activity_streams <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(0L)
  }

  activity_id_filter <- format_activity_id_filter(activity_ids)

  DBI::dbExecute(
    conn = connection,
    statement = glue::glue("
      DELETE FROM cycling_platform_silver.activity_streams
      WHERE activity_id IN ({activity_id_filter})
    ")
  )
}

#' Insert Silver Activity Stream Batch
#'
#' Expand raw stream arrays into wide silver stream samples for one batch of
#' activities.
#'
#' @param connection Database connection.
#' @param activity_ids Activity IDs to transform.
#'
#' @return Number of rows inserted.
insert_silver_activity_stream_batch <- function(
  connection,
  activity_ids
) {
  if (length(activity_ids) == 0) {
    return(0L)
  }

  activity_id_filter <- format_activity_id_filter(activity_ids)

  sql <- glue::glue("
    INSERT INTO cycling_platform_silver.activity_streams (
        activity_id,
        sample_index,
        time_seconds,
        distance_metres,
        latitude,
        longitude,
        altitude_metres,
        velocity_smooth_metres_per_second,
        heartrate_bpm,
        cadence_rpm,
        watts,
        temperature_celsius,
        is_moving,
        grade_smooth_percent,
        raw_stream_count,
        raw_max_original_size,
        raw_stream_retrieved_at,
        transformed_at
    )
    WITH digits AS (
        SELECT 0 AS n UNION ALL
        SELECT 1 UNION ALL
        SELECT 2 UNION ALL
        SELECT 3 UNION ALL
        SELECT 4 UNION ALL
        SELECT 5 UNION ALL
        SELECT 6 UNION ALL
        SELECT 7 UNION ALL
        SELECT 8 UNION ALL
        SELECT 9
    ),
    sequence_numbers AS (
        SELECT
            ones.n
            + tens.n * 10
            + hundreds.n * 100
            + thousands.n * 1000
            + ten_thousands.n * 10000
            + 1 AS sample_index
        FROM digits ones
        CROSS JOIN digits tens
        CROSS JOIN digits hundreds
        CROSS JOIN digits thousands
        CROSS JOIN digits ten_thousands
    ),
    activity_stream_summary AS (
        SELECT
            activity_id,
            COUNT(*) AS raw_stream_count,
            MAX(original_size) AS raw_max_original_size,
            MAX(retrieved_at) AS raw_stream_retrieved_at
        FROM cycling_platform_raw.activity_streams
        WHERE activity_id IN ({activity_id_filter})
        GROUP BY activity_id
    ),
    activity_samples AS (
        SELECT
            summary.activity_id,
            sequence_numbers.sample_index,
            summary.raw_stream_count,
            summary.raw_max_original_size,
            summary.raw_stream_retrieved_at
        FROM activity_stream_summary summary
        JOIN sequence_numbers
            ON sequence_numbers.sample_index <= summary.raw_max_original_size
    )
    SELECT
        samples.activity_id,
        samples.sample_index,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            time_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS time_seconds,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            distance_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS DECIMAL(18,6)) AS distance_metres,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            latlng_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, '][0]')
        )) AS DECIMAL(11,8)) AS latitude,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            latlng_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, '][1]')
        )) AS DECIMAL(11,8)) AS longitude,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            altitude_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS DECIMAL(18,6)) AS altitude_metres,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            velocity_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS DECIMAL(18,6)) AS velocity_smooth_metres_per_second,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            heartrate_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS heartrate_bpm,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            cadence_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS cadence_rpm,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            watts_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS watts,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            temp_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS SIGNED) AS temperature_celsius,
        CASE JSON_UNQUOTE(JSON_EXTRACT(
            moving_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        ))
            WHEN 'true' THEN TRUE
            WHEN 'false' THEN FALSE
            ELSE NULL
        END AS is_moving,
        CAST(JSON_UNQUOTE(JSON_EXTRACT(
            grade_stream.stream_payload,
            CONCAT('$[', samples.sample_index - 1, ']')
        )) AS DECIMAL(18,6)) AS grade_smooth_percent,
        samples.raw_stream_count,
        samples.raw_max_original_size,
        samples.raw_stream_retrieved_at,
        UTC_TIMESTAMP() AS transformed_at
    FROM activity_samples samples
    LEFT JOIN cycling_platform_raw.activity_streams time_stream
        ON time_stream.activity_id = samples.activity_id
        AND time_stream.stream_type = 'time'
    LEFT JOIN cycling_platform_raw.activity_streams distance_stream
        ON distance_stream.activity_id = samples.activity_id
        AND distance_stream.stream_type = 'distance'
    LEFT JOIN cycling_platform_raw.activity_streams latlng_stream
        ON latlng_stream.activity_id = samples.activity_id
        AND latlng_stream.stream_type = 'latlng'
    LEFT JOIN cycling_platform_raw.activity_streams altitude_stream
        ON altitude_stream.activity_id = samples.activity_id
        AND altitude_stream.stream_type = 'altitude'
    LEFT JOIN cycling_platform_raw.activity_streams velocity_stream
        ON velocity_stream.activity_id = samples.activity_id
        AND velocity_stream.stream_type = 'velocity_smooth'
    LEFT JOIN cycling_platform_raw.activity_streams heartrate_stream
        ON heartrate_stream.activity_id = samples.activity_id
        AND heartrate_stream.stream_type = 'heartrate'
    LEFT JOIN cycling_platform_raw.activity_streams cadence_stream
        ON cadence_stream.activity_id = samples.activity_id
        AND cadence_stream.stream_type = 'cadence'
    LEFT JOIN cycling_platform_raw.activity_streams watts_stream
        ON watts_stream.activity_id = samples.activity_id
        AND watts_stream.stream_type = 'watts'
    LEFT JOIN cycling_platform_raw.activity_streams temp_stream
        ON temp_stream.activity_id = samples.activity_id
        AND temp_stream.stream_type = 'temp'
    LEFT JOIN cycling_platform_raw.activity_streams moving_stream
        ON moving_stream.activity_id = samples.activity_id
        AND moving_stream.stream_type = 'moving'
    LEFT JOIN cycling_platform_raw.activity_streams grade_stream
        ON grade_stream.activity_id = samples.activity_id
        AND grade_stream.stream_type = 'grade_smooth'
  ")

  DBI::dbExecute(
    conn = connection,
    statement = sql
  )
}

#' Rebuild Silver Activity Streams
#'
#' Truncate and rebuild silver stream samples in activity batches.
#'
#' @param connection Database connection.
#' @param batch_size Number of activities to process per batch.
#' @param mode Use `full` to truncate and rebuild every activity, or `repair`
#'   to rebuild only activities with missing or incomplete silver rows.
#'
#' @return Invisibly returns NULL.
rebuild_silver_activity_streams <- function(
  connection,
  batch_size = 10L,
  mode = c(
    "full",
    "repair"
  )
) {
  mode <- match.arg(mode)

  stopifnot(batch_size > 0)

  if (mode == "full") {
    message("Truncating silver activity streams.")

    DBI::dbExecute(
      conn = connection,
      statement = "TRUNCATE TABLE cycling_platform_silver.activity_streams"
    )

    activity_ids <- get_silver_stream_activity_ids(
      connection = connection
    )
  } else {
    message("Repairing incomplete silver activity streams.")

    activity_ids <- get_silver_stream_repair_activity_ids(
      connection = connection
    )
  }

  activity_batches <- chunk_vector(
    x = activity_ids,
    chunk_size = batch_size
  )

  if (length(activity_batches) == 0) {
    message("No silver activity streams require rebuild.")

    return(invisible(NULL))
  }

  message(glue::glue(
    "Rebuilding silver activity streams for ",
    "{length(activity_ids)} activities in ",
    "{length(activity_batches)} batches."
  ))

  total_rows_deleted <- 0L
  total_rows_inserted <- 0L

  purrr::iwalk(
    activity_batches,
    \(activity_batch, batch_index) {
      message(glue::glue(
        "Processing silver stream batch {batch_index}/",
        "{length(activity_batches)} ",
        "({length(activity_batch)} activities)."
      ))

      rows_deleted <- delete_silver_activity_streams(
        connection = connection,
        activity_ids = activity_batch
      )

      rows_inserted <- insert_silver_activity_stream_batch(
        connection = connection,
        activity_ids = activity_batch
      )

      total_rows_deleted <<- total_rows_deleted + rows_deleted
      total_rows_inserted <<- total_rows_inserted + rows_inserted

      message(glue::glue(
        "Completed silver stream batch {batch_index}/",
        "{length(activity_batches)}: ",
        "{rows_deleted} rows deleted, ",
        "{rows_inserted} rows inserted."
      ))
    }
  )

  message(glue::glue(
    "Silver activity streams rebuild complete: ",
    "{total_rows_deleted} rows deleted, ",
    "{total_rows_inserted} rows inserted."
  ))

  invisible(NULL)
}
