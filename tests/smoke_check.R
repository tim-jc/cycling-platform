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

message("Checking raw SQL table declarations...")

raw_sql_files <- list.files(
  file.path("sql", "raw"),
  pattern = "[.]sql$",
  full.names = TRUE
)

expected_tables <- c(
  "100_create_activities.sql" = "cycling_platform_raw.activities",
  "110_create_activity_streams.sql" = "cycling_platform_raw.activity_streams",
  "120_create_activity_details.sql" = "cycling_platform_raw.activity_details"
)

for (file in raw_sql_files) {
  file_name <- basename(file)

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

message("Smoke checks passed.")
