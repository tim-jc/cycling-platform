lap_exploration_path <- file.path("exploration", "raw", "strava", "S-001_laps.R")
if (!file.exists(lap_exploration_path)) {
  lap_exploration_path <- file.path("..", "..", lap_exploration_path)
}

testthat::test_that("retained lap exploration is safe and deliberately compact", {
  lines <- readLines(lap_exploration_path, warn = FALSE)
  source_text <- paste(lines, collapse = "\n")

  testthat::expect_silent(parse(lap_exploration_path))
  testthat::expect_lte(length(lines), 240L)
  testthat::expect_false(grepl("rm(list = ls())", source_text, fixed = TRUE))
  testthat::expect_false(grepl("Sys.getenv", source_text, fixed = TRUE))
  testthat::expect_match(source_text, "main <- function()", fixed = TRUE)
  testthat::expect_match(source_text, "on.exit(DBI::dbDisconnect(connection)", fixed = TRUE)
})

testthat::test_that("retained lap exploration keeps the requested evidence", {
  source_text <- paste(readLines(lap_exploration_path, warn = FALSE), collapse = "\n")
  sections <- c(
    "1. Dataset overview", "2. Representative payloads", "3. Identity and grain",
    "4. Lap-index sequencing", "5. Stream-boundary semantics",
    "6. Parent-activity reconciliation", "7. Payload field coverage",
    "# FINDINGS", "# PROVISIONAL DECISIONS", "# OPEN QUESTIONS",
    "# CANDIDATE SILVER DESIGN", "# CONFIDENCE"
  )
  testthat::expect_true(all(vapply(
    sections, grepl, logical(1), x = source_text, fixed = TRUE
  )))
  testthat::expect_false(grepl("field suitability", source_text, ignore.case = TRUE))
})
