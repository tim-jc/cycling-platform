exploration_helpers_path <- file.path("exploration", "helpers.R")
if (!file.exists(exploration_helpers_path)) {
  exploration_helpers_path <- file.path("..", "..", exploration_helpers_path)
}
source(exploration_helpers_path)

testthat::test_that("safe payload parsing distinguishes valid, missing and malformed JSON", {
  testthat::expect_true(parse_json_payload_safe('{"id": 1}')$ok)
  testthat::expect_false(parse_json_payload_safe(NA_character_)$ok)
  testthat::expect_false(parse_json_payload_safe("")$ok)
  testthat::expect_false(parse_json_payload_safe("{broken")$ok)
})

testthat::test_that("nested extraction is safe for present, null and absent fields", {
  payload <- jsonlite::fromJSON(
    '{"activity":{"id":123},"average_watts":null}',
    simplifyVector = FALSE
  )

  testthat::expect_equal(safe_nested_extract(payload, "activity.id"), 123)
  testthat::expect_null(safe_nested_extract(payload, "average_watts"))
  testthat::expect_equal(safe_nested_extract(payload, "athlete.id", "missing"), "missing")
})

testthat::test_that("recursive fields preserve nested names, arrays and nulls", {
  payload <- jsonlite::fromJSON(
    '{"activity":{"id":123},"values":[1,2],"average_watts":null}',
    simplifyVector = FALSE
  )
  fields <- recursive_payload_fields(payload)

  testthat::expect_true(all(c("activity.id", "values", "average_watts") %in% fields$field_name))
  testthat::expect_equal(fields$observed_type[fields$field_name == "values"], "array")
  testthat::expect_true(fields$is_null[fields$field_name == "average_watts"])
})

testthat::test_that("payload coverage reports presence, types and null frequency", {
  coverage <- payload_field_coverage(c(
    '{"activity":{"id":1},"average_watts":200}',
    '{"activity":{"id":2},"average_watts":null}',
    '{"activity":{"id":3}}',
    "{malformed"
  ))

  activity_id <- coverage[coverage$field_name == "activity.id", ]
  watts <- coverage[coverage$field_name == "average_watts", ]
  testthat::expect_equal(activity_id$coverage_percent, 75)
  testthat::expect_equal(activity_id$observed_type, "integer")
  testthat::expect_equal(watts$coverage_percent, 50)
  testthat::expect_equal(watts$null_frequency, 0.5)
})
