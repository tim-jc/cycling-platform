lap_exploration_path <- file.path("exploration", "raw", "strava", "S-001_laps.R")
if (!file.exists(lap_exploration_path)) {
  lap_exploration_path <- file.path("..", "..", lap_exploration_path)
}

testthat::test_that("retained lap exploration remains syntactically valid", {
  source_text <- paste(
    readLines(lap_exploration_path, warn = FALSE),
    collapse = "\n"
  )

  # This is a retained interactive exploration, not a production entry point.
  # Do not source it during tests because it intentionally opens MariaDB.
  testthat::expect_silent(parse(lap_exploration_path))
  testthat::expect_match(source_text, 'source("bootstrap.R")', fixed = TRUE)
  testthat::expect_match(
    source_text,
    'source("exploration/helpers.R")',
    fixed = TRUE
  )
  testthat::expect_match(source_text, "get_connection()", fixed = TRUE)
  testthat::expect_match(
    source_text,
    "on.exit(DBI::dbDisconnect(con)",
    fixed = TRUE
  )
})

testthat::test_that("retained lap exploration documents its current evidence", {
  source_text <- paste(readLines(lap_exploration_path, warn = FALSE), collapse = "\n")
  sections <- c(
    "# Sample JSON payload",
    "# Specific activity JSON payload",
    "# Grain",
    "# FINDINGS",
    "# PROVISIONAL DECISIONS",
    "# OPEN QUESTIONS",
    "# CANDIDATE SILVER DESIGN",
    "# CONFIDENCE"
  )

  testthat::expect_true(all(vapply(
    sections, grepl, logical(1), x = source_text, fixed = TRUE
  )))
})
