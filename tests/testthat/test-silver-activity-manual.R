source_payload_helpers <- function() {
  path <- file.path("R", "transforms", "strava_activity_payload.R")
  if (!file.exists(path)) path <- file.path("..", "..", path)
  source(path)
}
source_payload_helpers()

testthat::test_that("manual TRUE and FALSE are source faithful", {
  testthat::expect_true(strava_activity_payload_boolean('[{"manual":true}]', "manual"))
  testthat::expect_false(strava_activity_payload_boolean('[{"manual":false}]', "manual"))
  testthat::expect_true(strava_activity_payload_boolean('{"manual":true}', "manual"))
})

testthat::test_that("manual null and absence remain unknown", {
  testthat::expect_true(is.na(strava_activity_payload_boolean('[{"manual":null}]', "manual")))
  testthat::expect_true(is.na(strava_activity_payload_boolean('[{"name":"Ride"}]', "manual")))
})

testthat::test_that("stream absence never changes manual classification", {
  manual_without_streams <- '[{"manual":true,"has_streams":false}]'
  non_manual_without_streams <- '[{"manual":false,"has_streams":false}]'
  testthat::expect_true(strava_activity_payload_boolean(manual_without_streams, "manual"))
  testthat::expect_false(strava_activity_payload_boolean(non_manual_without_streams, "manual"))
})

testthat::test_that("Silver SQL supports historical array and object payloads", {
  root <- if (file.exists("sql/silver/020_transform_activities.sql")) "." else file.path("..", "..")
  sql <- paste(readLines(file.path(root, "sql/silver/020_transform_activities.sql")), collapse="\n")
  testthat::expect_match(sql, "JSON_EXTRACT(a.raw_payload, '$.manual')", fixed=TRUE)
  testthat::expect_match(sql, "JSON_EXTRACT(a.raw_payload, '$[0].manual')", fixed=TRUE)
  manual_case <- regmatches(sql, regexpr("CASE LOWER\\(JSON_UNQUOTE\\(COALESCE\\([\\s\\S]*?END AS is_manual_raw", sql, perl=TRUE))
  testthat::expect_match(manual_case, "WHEN 'true' THEN TRUE", fixed=TRUE)
  testthat::expect_match(manual_case, "WHEN 'false' THEN FALSE", fixed=TRUE)
  testthat::expect_false(grepl("has_streams", manual_case, fixed=TRUE))
})

testthat::test_that("manual alignment validation ignores legitimate source nulls", {
  root <- if (file.exists("R/validation/validate_platform_completeness.R")) "." else file.path("..", "..")
  source <- paste(readLines(file.path(root,"R/validation/validate_platform_completeness.R")),collapse="\n")
  check <- regmatches(source,regexpr("check_name = \"silver_activity_manual_source_alignment\"[\\s\\S]*?per_check_timeout_seconds",source,perl=TRUE))
  testthat::expect_match(check,"source.is_manual IS NOT NULL",fixed=TRUE)
  testthat::expect_match(check,"LEFT JOIN cycling_platform_silver.activities",fixed=TRUE)
  testthat::expect_match(check,"silver.is_manual IS NULL",fixed=TRUE)
  testthat::expect_match(check,"silver.is_manual <> source.is_manual",fixed=TRUE)
})
