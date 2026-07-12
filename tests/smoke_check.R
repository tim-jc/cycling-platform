fail <- function(message) {
  stop(message, call. = FALSE)
}

message("Checking R syntax...")

r_files <- list.files(
  "R",
  pattern = "[.][Rr]$",
  recursive = TRUE,
  full.names = TRUE
)

r_files <- c(
  r_files,
  "bootstrap.R",
  "bootstrap_platform.R",
  "platform.R",
  "run_google_health_auth_check.R",
  "run_google_health_capability_probe.R",
  "run_google_health_daily_resting_heart_rate.R",
  "run_google_health_daily_heart_rate_variability.R",
  "run_google_health_heart_rate.R",
  "run_google_health_sleep.R",
  "run_daily_platform.R",
  "run_gold_activity_best_efforts.R",
  "run_silver.R",
  "validate_platform.R"
)

parse_failures <- lapply(
  r_files,
  function(file) {
    tryCatch(
      {
        parse(file)
        NULL
      },
      error = function(e) {
        paste(file, conditionMessage(e), sep = ": ")
      }
    )
  }
)

parse_failures <- Filter(
  Negate(is.null),
  parse_failures
)

if (length(parse_failures) > 0) {
  fail(
    paste(parse_failures, collapse = "\n")
  )
}

message("Checking stale activity detail references...")

source_text <- paste(
  unlist(
    lapply(
      r_files,
      readLines,
      warn = FALSE
    )
  ),
  collapse = "\n"
)

stale_patterns <- c(
  "upsert_details\\(",
  "activity_details_result\\$activity_details"
)

for (pattern in stale_patterns) {
  if (grepl(pattern, source_text, perl = TRUE)) {
    fail(
      paste("Found stale reference:", pattern)
    )
  }
}

message("Checking Strava API helper usage...")

api_files <- list.files(
  file.path("R", "api"),
  pattern = "[.][Rr]$",
  full.names = TRUE
)

direct_request_allowed <- c(
  file.path("R", "api", "get_access_token.R"),
  file.path("R", "api", "get_google_health_access_token.R"),
  file.path("R", "api", "perform_google_health_request.R"),
  file.path("R", "api", "perform_strava_request.R")
)

for (file in setdiff(api_files, direct_request_allowed)) {
  text <- paste(
    readLines(file, warn = FALSE),
    collapse = "\n"
  )

  if (grepl("httr2::request\\(|httr2::req_perform\\(", text, perl = TRUE)) {
    fail(
      paste(
        file,
        "should use perform_strava_request() for Strava API calls"
      )
    )
  }
}

message("Checking raw row split helper...")

suppressPackageStartupMessages(
  library(bit64)
)

source(
  file.path("R", "database", "split_existing_rows.R")
)

split_check_data <- data.frame(
  activity_id = c(101, 102, 103),
  stream_type = c(
    "time",
    "time",
    "latlng"
  )
)

split_check_existing <- data.frame(
  activity_id = bit64::as.integer64("102"),
  stream_type = "time"
)

split_check <- split_existing_rows(
  data = split_check_data,
  existing_keys = split_check_existing,
  key_columns = c("activity_id", "stream_type")
)

if (nrow(split_check$to_insert) != 2 || nrow(split_check$to_update) != 1) {
  fail("split_existing_rows() did not split composite keys correctly")
}

message("Checking SQL table declarations...")

sql_files <- list.files(
  "sql",
  pattern = "[.]sql$",
  recursive = TRUE,
  full.names = TRUE
)

expected_tables <- c(
  "admin/040_create_transform_run.sql" = "cycling_platform_admin.transform_run",
  "admin/041_create_transform_run_batch.sql" = "cycling_platform_admin.transform_run_batch",
  "stage/010_create_activity_streams_build.sql" = "cycling_platform_stage.activity_streams_build",
  "raw/010_create_strava_activities.sql" = "cycling_platform_raw.activities",
  "raw/020_create_strava_activity_streams.sql" = "cycling_platform_raw.activity_streams",
  "raw/030_create_strava_activity_details.sql" = "cycling_platform_raw.activity_details",
  "raw/040_create_strava_activity_laps.sql" = "cycling_platform_raw.activity_laps",
  "raw/100_create_google_health_heart_rate_responses.sql" = "cycling_platform_raw.google_health_heart_rate_responses",
  "raw/110_create_google_health_sleep_logs.sql" = "cycling_platform_raw.google_health_sleep_logs",
  "raw/120_create_google_health_daily_resting_heart_rate.sql" = "cycling_platform_raw.google_health_daily_resting_heart_rate",
  "raw/130_create_google_health_daily_heart_rate_variability.sql" = "cycling_platform_raw.google_health_daily_heart_rate_variability",
  "silver/010_create_activities.sql" = "cycling_platform_silver.activities",
  "silver/030_create_activity_streams.sql" = "cycling_platform_silver.activity_streams",
  "gold/010_create_activity_best_efforts.sql" = "cycling_platform_gold.activity_best_efforts"
)

missing_expected_files <- setdiff(
  names(expected_tables),
  sub(
    "^sql/",
    "",
    sql_files
  )
)

if (length(missing_expected_files) > 0) {
  stop(
    "Expected SQL files missing from smoke check input: ",
    paste(
      missing_expected_files,
      collapse = ", "
    )
  )
}

for (file in sql_files) {
  file_name <- sub(
    "^sql/",
    "",
    file
  )

  if (!file_name %in% names(expected_tables)) {
    next
  }

  sql <- paste(
    readLines(file, warn = FALSE),
    collapse = "\n"
  )

  expected <- paste(
    "CREATE TABLE IF NOT EXISTS",
    expected_tables[[file_name]]
  )

  if (!grepl(expected, sql, fixed = TRUE)) {
    fail(
      paste(
        file,
        "does not declare expected table",
        expected_tables[[file_name]]
      )
    )
  }
}

message("Checking bootstrap excludes transformation SQL...")

bootstrap_text <- paste(
  readLines("bootstrap_platform.R", warn = FALSE),
  collapse = "\n"
)

if (!grepl("^[0-9]+_create_", bootstrap_text, fixed = TRUE)) {
  fail("bootstrap_platform.R should only run create SQL for derived layers")
}

message("Smoke checks passed.")
