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
  "run_raw_ingestion.R",
  "scripts/google_health/check_authentication.R",
  "scripts/google_health/probe_capabilities.R",
  "scripts/google_health/run_daily_resting_heart_rate.R",
  "scripts/google_health/run_daily_heart_rate_variability.R",
  "scripts/google_health/run_daily_respiratory_rate.R",
  "scripts/google_health/run_heart_rate.R",
  "scripts/google_health/run_sleep.R",
  "run_daily_platform.R",
  "scripts/gold/run_activity_achievements.R",
  "scripts/gold/run_activity_best_efforts.R",
  "scripts/audits/audit_power_source_classification.R",
  "scripts/operations/run_notifications.R",
  file.path("scripts", "strava", "bootstrap_oauth.R"),
  file.path("scripts", "audits", "audit_silver_activity_population.R"),
  file.path("scripts", "contracts", "generate_metadata.R"),
  file.path("scripts", "operations", "show_job_status.R"),
  file.path("scripts", "contracts", "validate.R"),
  "run_silver.R",
  "run_platform_validation.R"
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

root_r_files <- sort(basename(list.files(
  ".",
  pattern = "[.][Rr]$",
  recursive = FALSE,
  full.names = TRUE
)))
expected_root_r_files <- sort(c(
  "bootstrap.R",
  "bootstrap_platform.R",
  "run_daily_platform.R",
  "run_platform_validation.R",
  "run_raw_ingestion.R",
  "run_silver.R"
))

if (!identical(root_r_files, expected_root_r_files)) {
  fail(paste(
    "Unexpected root-level R entry points:",
    paste(setdiff(root_r_files, expected_root_r_files), collapse = ", ")
  ))
}

message("Checking MariaDB connection entry schemas...")

source(
  file.path("R", "database", "get_connection.R")
)

default_database_name <- eval(
  formals(get_connection)$database_name
)

if (!identical(default_database_name, "cycling_platform_admin")) {
  fail(
    paste(
      "get_connection() must default to cycling_platform_admin, not",
      default_database_name
    )
  )
}

connection_files <- c(
  list.files(
    "R",
    pattern = "[.][Rr]$",
    recursive = TRUE,
    full.names = TRUE
  ),
  list.files(
    ".",
    pattern = "[.][Rr]$",
    recursive = FALSE,
    full.names = TRUE
  )
)

connection_source_text <- paste(
  unlist(
    lapply(
      connection_files,
      readLines,
      warn = FALSE
    )
  ),
  collapse = "\n"
)

forbidden_connection_patterns <- c(
  "get_connection\\s*\\([^)]*[\"']mysql[\"']",
  "dbname\\s*=\\s*[\"']mysql[\"']",
  "database_name\\s*=\\s*[\"']mysql[\"']"
)

for (pattern in forbidden_connection_patterns) {
  if (grepl(pattern, connection_source_text, perl = TRUE)) {
    fail(
      paste(
        "Found forbidden MariaDB system-schema connection pattern:",
        pattern
      )
    )
  }
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
  file.path("R", "api", "bootstrap_strava_oauth.R"),
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
  "admin/032_create_api_endpoint_run.sql" = "cycling_platform_admin.api_endpoint_run",
  "admin/040_create_transform_run.sql" = "cycling_platform_admin.transform_run",
  "admin/041_create_transform_run_batch.sql" = "cycling_platform_admin.transform_run_batch",
  "admin/060_create_notification_outbox.sql" = "cycling_platform_admin.notification_outbox",
  "admin/070_create_power_source_classification.sql" = "cycling_platform_admin.power_source_classification",
  "admin/080_create_backup_run.sql" = "cycling_platform_admin.backup_run",
  "admin/081_create_backup_run_file.sql" = "cycling_platform_admin.backup_run_file",
  "admin/082_create_backup_reconciliation_run.sql" = "cycling_platform_admin.backup_reconciliation_run",
  "stage/010_create_activity_streams_build.sql" = "cycling_platform_stage.activity_streams_build",
  "raw/010_create_strava_activities.sql" = "cycling_platform_raw.activities",
  "raw/020_create_strava_activity_streams.sql" = "cycling_platform_raw.activity_streams",
  "raw/030_create_strava_activity_details.sql" = "cycling_platform_raw.activity_details",
  "raw/040_create_strava_activity_laps.sql" = "cycling_platform_raw.activity_laps",
  "raw/050_create_strava_gear_observations.sql" = "cycling_platform_raw.gear_observations",
  "raw/100_create_google_health_heart_rate_responses.sql" = "cycling_platform_raw.google_health_heart_rate_responses",
  "raw/110_create_google_health_sleep_logs.sql" = "cycling_platform_raw.google_health_sleep_logs",
  "raw/120_create_google_health_daily_resting_heart_rate.sql" = "cycling_platform_raw.google_health_daily_resting_heart_rate",
  "raw/130_create_google_health_daily_heart_rate_variability.sql" = "cycling_platform_raw.google_health_daily_heart_rate_variability",
  "raw/140_create_google_health_daily_respiratory_rate.sql" = "cycling_platform_raw.google_health_daily_respiratory_rate",
  "silver/010_create_activities.sql" = "cycling_platform_silver.activities",
  "silver/030_create_activity_streams.sql" = "cycling_platform_silver.activity_streams",
  "silver/040_create_gear.sql" = "cycling_platform_silver.gear",
  "gold/010_create_activity_best_efforts.sql" = "cycling_platform_gold.activity_best_efforts",
  "gold/020_create_activity_achievements.sql" = "cycling_platform_gold.activity_achievements"
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

message("Checking deterministic MariaDB table definitions...")

create_sql_files <- list.files(
  "sql",
  pattern = "create.*[.]sql$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)

for (file in create_sql_files) {
  sql <- paste(readLines(file, warn = FALSE), collapse = "\n")
  create_count <- lengths(
    gregexpr(
      "CREATE[[:space:]]+TABLE",
      sql,
      ignore.case = TRUE,
      perl = TRUE
    )
  )

  required_options <- c(
    "ENGINE=InnoDB",
    "DEFAULT CHARACTER SET utf8mb4",
    "DEFAULT COLLATE utf8mb4_general_ci"
  )

  for (required_option in required_options) {
    option_count <- lengths(
      gregexpr(required_option, sql, fixed = TRUE)
    )

    if (!identical(option_count, create_count)) {
      fail(
        paste(
          file,
          "must specify",
          required_option,
          "for every CREATE TABLE"
        )
      )
    }
  }
}

message("Checking bootstrap excludes transformation SQL...")

source(file.path("R", "database", "bootstrap_platform_schema.R"))
bootstrap_sql_files <- list_platform_bootstrap_sql_files()
derived_bootstrap_files <- bootstrap_sql_files[
  grepl("/sql/(reference|silver|gold)/", bootstrap_sql_files)
]

if (!all(grepl("^[0-9]+_create_", basename(derived_bootstrap_files)))) {
  fail("bootstrap_platform.R should only run create SQL for derived layers")
}

if (any(grepl("/sql/install/", bootstrap_sql_files))) {
  fail("Platform bootstrap must validate databases, not create them")
}

bootstrap_helper_text <- paste(
  readLines(
    file.path("R", "database", "bootstrap_platform_schema.R"),
    warn = FALSE
  ),
  collapse = "\n"
)

if (!grepl("run_schema_migrations", bootstrap_helper_text, fixed = TRUE)) {
  fail("bootstrap_platform.R must apply versioned schema migrations")
}

message("Checking loaders cannot create persistent tables implicitly...")

direct_write_files <- r_files[vapply(
  r_files,
  function(file) {
    text <- paste(readLines(file, warn = FALSE), collapse = "\n")
    grepl("DBI::dbWriteTable(", text, fixed = TRUE)
  },
  logical(1)
)]

allowed_direct_write <- file.path(
  "R",
  "database",
  "append_existing_table.R"
)

if (!identical(direct_write_files, allowed_direct_write)) {
  fail(
    paste(
      "Only append_existing_table.R may call DBI::dbWriteTable directly; found:",
      paste(direct_write_files, collapse = ", ")
    )
  )
}

message("Smoke checks passed.")
