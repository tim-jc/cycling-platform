gps_qualification_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(gps_qualification_path("R", "quality", "profile_activity_track_integrity.R"))
source(gps_qualification_path("R", "quality", "profile_geographic_calibration_evidence.R"))
source(gps_qualification_path("R", "quality", "gps_qualification_prototype.R"))

qualification_samples <- function(
  latitude = c(53, 53.001, 53.002),
  longitude = c(-1, -1, -1),
  time_seconds = c(0, 1, 2),
  distance_metres = c(0, 100, 200),
  sample_index = seq_along(latitude),
  complete_activity = TRUE
) {
  result <- data.frame(
    activity_id = "123", sample_index = sample_index, latitude = latitude,
    longitude = longitude, time_seconds = time_seconds,
    distance_metres = distance_metres, stringsAsFactors = FALSE
  )
  attr(result, "complete_activity") <- complete_activity
  result
}

qualification_run_context <- function(id = "test-run") list(evaluation_run_id = id)

testthat::test_that("missing and invalid observations are deterministically rejected", {
  samples <- qualification_samples(latitude = c(NA, 91, 53))
  result <- qualify_activity_gps(samples, default_gps_qualification_policy(), qualification_run_context())
  testthat::expect_equal(result$observation_decisions$classification, c("REJECTED", "REJECTED", "UNCERTAIN"))
  testthat::expect_equal(
    result$observation_decisions$primary_reason_code[1:2],
    c("COORDINATE_MISSING", "COORDINATE_OUT_OF_RANGE")
  )
})

testthat::test_that("isolated valid observations retain unknown source context", {
  samples <- qualification_samples(
    latitude = 53, longitude = -1, time_seconds = 0,
    distance_metres = 0, complete_activity = FALSE
  )
  result <- qualify_activity_gps(samples, default_gps_qualification_policy(), qualification_run_context())
  testthat::expect_equal(result$observation_decisions$classification, "UNCERTAIN")
  testthat::expect_equal(result$observation_decisions$primary_reason_code, "CONTEXT_INCOMPLETE")
  testthat::expect_false(result$observation_features$source_boundary_before_known)
  testthat::expect_false(result$observation_features$source_boundary_after_known)
})

testthat::test_that("an absent stream is a coverage condition without rejected entities", {
  samples <- qualification_samples()[0, ]
  result <- qualify_activity_gps(
    samples, default_gps_qualification_policy(), qualification_run_context()
  )
  testthat::expect_equal(result$coverage$coverage_status, "GPS_STREAM_ABSENT")
  testthat::expect_equal(nrow(result$observation_decisions), 0L)
  testthat::expect_equal(nrow(result$segment_decisions), 0L)
  testthat::expect_equal(nrow(result$reasons), 0L)
})

testthat::test_that("stationary duplicates are supporting evidence and not rejection", {
  samples <- qualification_samples(
    latitude = c(53, 53, 53.001), longitude = c(-1, -1, -1),
    time_seconds = c(0, 0, 1), distance_metres = c(0, 0, 100)
  )
  result <- qualify_activity_gps(samples, default_gps_qualification_policy(), qualification_run_context())
  testthat::expect_equal(result$segment_decisions$classification[[1]], "UNCERTAIN")
  reason <- result$reasons[result$reasons$entity_type == "SEGMENT" &
    result$reasons$from_sample_index == 1L &
    result$reasons$reason_code == "DUPLICATE_TIMESTAMP_STATIONARY", , drop = FALSE]
  testthat::expect_equal(nrow(reason), 1L)
  testthat::expect_equal(reason$evidence_role, "SUPPORTING")
})

testthat::test_that("movement over non-positive time rejects only the segment", {
  samples <- qualification_samples(time_seconds = c(0, 0, 1))
  result <- qualify_activity_gps(samples, default_gps_qualification_policy(), qualification_run_context())
  testthat::expect_equal(result$segment_decisions$classification[[1]], "REJECTED")
  testthat::expect_equal(
    result$segment_decisions$primary_reason_code[[1]],
    "TIME_NON_INCREASING_WITH_DISPLACEMENT"
  )
  testthat::expect_false(any(result$observation_decisions$classification == "REJECTED"))
})

testthat::test_that("unusable endpoint rejects a segment independently", {
  samples <- qualification_samples(latitude = c(53, NA, 53.002))
  result <- qualify_activity_gps(samples, default_gps_qualification_policy(), qualification_run_context())
  testthat::expect_true(all(result$segment_decisions$classification == "REJECTED"))
  testthat::expect_true(all(result$segment_decisions$primary_reason_code == "ENDPOINT_UNUSABLE"))
})

testthat::test_that("missing device distance remains source-faithful and non-deterministic", {
  samples <- qualification_samples(distance_metres = c(0, NA, 200))
  result <- qualify_activity_gps(samples, default_gps_qualification_policy(), qualification_run_context())
  testthat::expect_true(all(is.na(result$segment_features$device_distance_difference_metres)))
  testthat::expect_true(all(result$segment_decisions$classification == "UNCERTAIN"))
})

testthat::test_that("malformed source order is an execution defect", {
  testthat::expect_error(
    prepare_gps_qualification_features(qualification_samples(sample_index = c(1, 1, 2))),
    "strictly increasing"
  )
  testthat::expect_error(
    prepare_gps_qualification_features(qualification_samples(sample_index = c(1, 3, 2))),
    "strictly increasing"
  )
})

testthat::test_that("policy fingerprints are stable across list ordering", {
  policy <- default_gps_qualification_policy()
  reordered <- policy[rev(names(policy))]
  reordered$rules <- reordered$rules[rev(names(reordered$rules))]
  testthat::expect_identical(
    fingerprint_gps_qualification_policy(policy),
    fingerprint_gps_qualification_policy(reordered)
  )
  invalid <- policy
  invalid$rules$local_excursion$state <- "ENABLED_EXPERIMENTAL"
  testthat::expect_error(validate_gps_qualification_policy(invalid), "explicit approved")
})

testthat::test_that("decisions and reasons are stable and keyed", {
  result_a <- qualify_activity_gps(
    qualification_samples(), default_gps_qualification_policy(), qualification_run_context("stable")
  )
  result_b <- qualify_activity_gps(
    qualification_samples(), default_gps_qualification_policy(), qualification_run_context("stable")
  )
  testthat::expect_identical(result_a$observation_decisions, result_b$observation_decisions)
  testthat::expect_identical(result_a$segment_decisions, result_b$segment_decisions)
  testthat::expect_identical(result_a$reasons, result_b$reasons)
})

evaluation_labels <- function() {
  data.frame(
    entity_type = c("OBSERVATION", "OBSERVATION", "SEGMENT", "SEGMENT"),
    activity_id = "123", sample_index = c(1L, 2L, NA, NA),
    from_sample_index = c(NA, NA, 1L, 2L), to_sample_index = c(NA, NA, 2L, 3L),
    case_key = c("a", "a", "a", "a"), calibration_partition = c("CALIBRATION", "HOLDOUT", "CALIBRATION", "HOLDOUT"),
    manual_label = c("UNCERTAIN", "UNREVIEWED", "REJECTED", "UNCERTAIN"),
    evidence_version = "v1", stringsAsFactors = FALSE
  )
}

testthat::test_that("evaluation keeps unreviewed and holdout evidence separate", {
  result <- qualify_activity_gps(
    qualification_samples(time_seconds = c(0, 0, 1)),
    default_gps_qualification_policy(), qualification_run_context()
  )
  evaluation <- evaluate_gps_qualification(
    result$observation_decisions, result$segment_decisions, evaluation_labels()
  )
  testthat::expect_equal(evaluation$counts$evidence_rows, 4L)
  testthat::expect_equal(evaluation$counts$reviewed_rows, 3L)
  testthat::expect_equal(nrow(evaluation$holdout_cases), 1L)
  testthat::expect_equal(nrow(evaluation$confusion), 36L)
})

testthat::test_that("evaluation rejects duplicate and conflicting label evidence", {
  result <- qualify_activity_gps(
    qualification_samples(), default_gps_qualification_policy(), qualification_run_context()
  )
  labels <- evaluation_labels()
  testthat::expect_error(
    evaluate_gps_qualification(result$observation_decisions, result$segment_decisions, rbind(labels, labels[1, ])),
    "duplicate evidence"
  )
  conflicting <- labels
  duplicate <- conflicting[1, ]
  duplicate$case_key <- "b"
  duplicate$manual_label <- "ACCEPTED"
  testthat::expect_error(
    evaluate_gps_qualification(result$observation_decisions, result$segment_decisions, rbind(conflicting, duplicate)),
    "conflict"
  )
})

testthat::test_that("writer refuses repository paths and all collisions before writing", {
  result <- qualify_activity_gps(
    qualification_samples(), default_gps_qualification_policy(), qualification_run_context()
  )
  result$evaluation <- evaluate_gps_qualification(
    result$observation_decisions, result$segment_decisions, evaluation_labels()
  )
  manifest <- data.frame(evaluation_run_id = "test-run", stringsAsFactors = FALSE)
  repository <- normalizePath(gps_qualification_path("."), mustWork = TRUE)
  testthat::expect_error(
    write_gps_qualification_outputs(result, manifest, tempfile(tmpdir = repository), repository),
    "outside the repository"
  )
  output <- tempfile("gps-qualification-")
  dir.create(output)
  writeLines("preserve", file.path(output, "holdout_cases.csv"))
  testthat::expect_error(
    write_gps_qualification_outputs(result, manifest, output, repository),
    "Refusing to overwrite"
  )
  testthat::expect_false(file.exists(file.path(output, "observation_features.csv")))
  testthat::expect_equal(readLines(file.path(output, "holdout_cases.csv")), "preserve")
})

testthat::test_that("writer succeeds in a new external directory with stable schemas", {
  result <- qualify_activity_gps(
    qualification_samples(), default_gps_qualification_policy(), qualification_run_context()
  )
  result$evaluation <- evaluate_gps_qualification(
    result$observation_decisions, result$segment_decisions, evaluation_labels()
  )
  output <- tempfile("gps-qualification-")
  write_gps_qualification_outputs(
    result, data.frame(evaluation_run_id = "test-run"), output,
    normalizePath(gps_qualification_path("."), mustWork = TRUE)
  )
  testthat::expect_equal(length(list.files(output)), 11L)
  testthat::expect_equal(
    names(utils::read.csv(file.path(output, "observation_decisions.csv"))),
    names(result$observation_decisions)
  )
})
