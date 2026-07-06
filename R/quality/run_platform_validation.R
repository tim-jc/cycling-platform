#' Run Platform Validation
#'
#' Execute lightweight post-automation validation checks.
#'
#' @param connection DBI connection.
#'
#' @return Data frame of validation results.
run_platform_validation <- function(connection) {
  validation_checks <- list(
    list(
      check_name = "silver_streams_have_silver_activities",
      severity = "CRITICAL",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_silver.activity_streams streams
        LEFT JOIN cycling_platform_silver.activities activities
          ON activities.activity_id = streams.activity_id
        WHERE activities.activity_id IS NULL
      "
    ),
    list(
      check_name = "silver_activity_has_streams_matches_rows",
      severity = "CRITICAL",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM cycling_platform_silver.activities activities
        WHERE activities.has_streams <> EXISTS (
          SELECT 1
          FROM cycling_platform_silver.activity_streams streams
          WHERE streams.activity_id = activities.activity_id
        )
      "
    ),
    list(
      check_name = "silver_stream_sample_key_unique",
      severity = "CRITICAL",
      sql = "
        SELECT COUNT(*) AS failure_count
        FROM (
          SELECT
            activity_id,
            sample_index
          FROM cycling_platform_silver.activity_streams
          GROUP BY
            activity_id,
            sample_index
          HAVING COUNT(*) > 1
        ) duplicate_samples
      "
    ),
    list(
      check_name = "raw_and_silver_activity_counts_match",
      severity = "CRITICAL",
      sql = "
        SELECT
          CASE
            WHEN raw_counts.row_count = silver_counts.row_count THEN 0
            ELSE 1
          END AS failure_count
        FROM (
          SELECT COUNT(*) AS row_count
          FROM cycling_platform_raw.activities
        ) raw_counts
        CROSS JOIN (
          SELECT COUNT(*) AS row_count
          FROM cycling_platform_silver.activities
        ) silver_counts
      "
    )
  )

  results <- lapply(
    validation_checks,
    \(validation_check) {
      failure_count <- DBI::dbGetQuery(
        conn = connection,
        statement = validation_check$sql
      )$failure_count[[1]]

      data.frame(
        check_name = validation_check$check_name,
        severity = validation_check$severity,
        failure_count = as.integer(failure_count),
        check_status = if (failure_count == 0) "PASS" else "FAIL"
      )
    }
  )

  validation_results <- do.call(rbind, results)

  failed_critical <- validation_results[
    validation_results$severity == "CRITICAL" &
      validation_results$check_status == "FAIL",
    ,
    drop = FALSE
  ]

  if (nrow(failed_critical) > 0) {
    stop(
      "Platform validation failed: ",
      paste(
        paste0(
          failed_critical$check_name,
          "=",
          failed_critical$failure_count
        ),
        collapse = "; "
      ),
      call. = FALSE
    )
  }

  validation_results
}
