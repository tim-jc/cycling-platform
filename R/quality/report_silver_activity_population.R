report_silver_activity_population <- function(connection) {
  columns <- DBI::dbGetQuery(connection, "SELECT column_name FROM information_schema.columns WHERE table_schema='cycling_platform_silver' AND table_name='activities' ORDER BY ordinal_position")$column_name
  raw_columns <- DBI::dbGetQuery(connection, "SELECT column_name FROM information_schema.columns WHERE table_schema='cycling_platform_raw' AND table_name='activities'")$column_name
  total <- DBI::dbGetQuery(connection, "SELECT COUNT(*) AS n FROM cycling_platform_silver.activities")$n[[1]]
  json_source <- c(
    is_manual = "CASE WHEN LOWER(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(raw_payload, '$.manual'), JSON_EXTRACT(raw_payload, '$[0].manual')))) IN ('true','false','1','0') THEN 1 END",
    is_trainer = "CASE WHEN LOWER(JSON_UNQUOTE(COALESCE(JSON_EXTRACT(raw_payload, '$.trainer'), JSON_EXTRACT(raw_payload, '$[0].trainer')))) IN ('true','false','1','0') THEN 1 END"
  )
  derived <- c("activity_type", "start_date_local", "start_time_local", "distance_kilometres", "distance_miles", "average_speed_kilometres_per_hour", "average_speed_miles_per_hour", "power_source_type", "power_source_status", "is_measured_power", "is_power_record_eligible", "power_record_exclusion_reason", "power_classification_rule", "power_classification_method", "power_classification_version", "power_meter_cutover_at", "has_streams", "has_details", "has_laps", "raw_detail_retrieved_at", "transformed_at")

  rows <- lapply(columns, function(column) {
    identifier <- as.character(DBI::dbQuoteIdentifier(connection, column))
    silver <- DBI::dbGetQuery(connection, paste0("SELECT COUNT(", identifier, ") AS non_null_count, COUNT(DISTINCT ", identifier, ") AS distinct_count, GROUP_CONCAT(DISTINCT CAST(", identifier, " AS CHAR) ORDER BY ", identifier, " SEPARATOR ', ') AS distinct_values FROM cycling_platform_silver.activities"))
    raw_source <- if (column %in% names(json_source)) paste0("raw_payload.", sub("^is_", "", column)) else if (column == "activity_type") "sport_type" else if (column %in% raw_columns) column else NA_character_
    raw_non_null <- if (column %in% names(json_source)) {
      DBI::dbGetQuery(connection, paste0("SELECT COUNT(", json_source[[column]], ") AS n FROM cycling_platform_raw.activities"))$n[[1]]
    } else if (!is.na(raw_source) && raw_source %in% raw_columns) {
      raw_identifier <- as.character(DBI::dbQuoteIdentifier(connection, raw_source))
      DBI::dbGetQuery(connection, paste0("SELECT COUNT(", raw_identifier, ") AS n FROM cycling_platform_raw.activities"))$n[[1]]
    } else NA_integer_
    issue <- if (!is.na(raw_non_null) && raw_non_null > 0 && silver$non_null_count[[1]] == 0) "Silver unpopulated while Raw has values" else if (silver$non_null_count[[1]] == 0) "All NULL; review if intentional" else if (silver$distinct_count[[1]] == 1 && total > 1) "Constant value; review if intentional" else if (total > 0 && silver$non_null_count[[1]] / total < 0.05) "Overwhelmingly NULL; review source coverage" else "No population anomaly detected"
    action <- if (grepl("review|unpopulated", issue, ignore.case = TRUE)) "Review mapping and contract before changing" else if (column %in% derived) "Retain; derived field" else "Retain"
    data.frame(silver_column=column,raw_source=raw_source,silver_non_null_count=silver$non_null_count[[1]],silver_distinct_values=ifelse(is.na(silver$distinct_values[[1]]),"",silver$distinct_values[[1]]),raw_non_null_count=raw_non_null,suspected_issue=issue,recommended_action=action)
  })
  do.call(rbind, rows)
}
