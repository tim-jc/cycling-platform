stage2ca_test_path <- function(...) {
  path <- file.path(...)
  if (!file.exists(path)) path <- file.path("..", "..", path)
  path
}

source(stage2ca_test_path("R", "quality", "extract_gps_episode_context.R"))
source(stage2ca_test_path("R", "quality", "reconcile_gps_stage2ca_scientific_evidence.R"))

stage2ca_prior_fixture <- function() {
  data.frame(
    entity_type = c(rep("OBSERVATION", 7L), rep("SEGMENT", 7L), "OBSERVATION"),
    activity_id = c(rep("158147957", 14L), "31722499"),
    sample_index = c(1009:1015, rep(NA_integer_, 7L), 1L),
    from_sample_index = c(rep(NA_integer_, 7L), 1008:1014, NA_integer_),
    to_sample_index = c(rep(NA_integer_, 7L), 1009:1015, NA_integer_),
    case_key = "CASE",
    decision_status = c(rep("OWNER_CONFIRMED_RESEARCH_DECISION", 14L),
      "OWNER_CONFIRMED_CONDITIONAL_RESEARCH_DECISION"),
    conditional_acceptance = c(rep("FALSE", 14L), "TRUE"),
    review_provenance = "PRIOR",
    reviewer_rationale = "prior rationale",
    confirmed_research_label = c(rep("REJECTED", 13L), "REJECTED", "ACCEPTED"),
    governance_status = "RESEARCH_RECONCILIATION_NOT_GOVERNED_LABEL_SNAPSHOT",
    stringsAsFactors = FALSE
  )
}

testthat::test_that("scientific reconciliation preserves and supersedes explicitly", {
  result <- build_stage2ca_decision_ledger(stage2ca_prior_fixture())
  sample_1009 <- result$activity_id == "158147957" &
    !is.na(result$sample_index) & result$sample_index == 1009L
  testthat::expect_equal(result$prior_research_label[sample_1009], "REJECTED")
  testthat::expect_equal(result$current_research_label[sample_1009], "UNCERTAIN")
  testthat::expect_equal(
    result$reconciliation_action[sample_1009], "SUPERSEDED_BY_OWNER_REASSESSMENT"
  )
  final_observations <- result$entity_type == "OBSERVATION" & result$activity_id == "158147957"
  testthat::expect_equal(
    result$current_research_label[final_observations],
    c(rep("UNCERTAIN", 5L), "REJECTED", "REJECTED")
  )
  final_segments <- result$entity_type == "SEGMENT" & result$activity_id == "158147957"
  testthat::expect_equal(
    result$current_research_label[final_segments],
    c(rep("UNCERTAIN", 5L), "REJECTED", "REJECTED")
  )
  testthat::expect_false(any(result$current_decision_status == "OUTSTANDING_OWNER_REVIEW"))
  conditional <- result$activity_id == "31722499"
  testthat::expect_equal(result$reconciliation_action[conditional], "CONDITION_SATISFIED")
  testthat::expect_equal(result$current_conditional_acceptance[conditional], "FALSE")
  testthat::expect_true(all(
    result$governance_status == "SCIENTIFIC_RESEARCH_DECISION_NOT_GOVERNED_LABEL"
  ))
})

testthat::test_that("context and boundaries never become individual labels", {
  context <- stage2ca_contextual_findings()
  boundaries <- stage2ca_boundary_register()
  testthat::expect_false(any(context$creates_individual_label))
  testthat::expect_true(all(boundaries$individual_qualification_label == ""))
  testthat::expect_true(all(
    boundaries$governance_status == "CONTEXTUAL_BOUNDARY_NOT_INDIVIDUAL_LABEL"
  ))
  testthat::expect_true(any(
    boundaries$activity_id == "31856627" &
      boundaries$milestone_type == "LAST_DEFINITELY_RELIABLE" &
      boundaries$from_sample_index == 5357L
  ))
})

testthat::test_that("supplementary request is bounded calibration-only context", {
  source_path <- tempfile(fileext = ".csv")
  writeLines("source", source_path)
  result <- build_stage2ca_supplementary_request(source_path, "revision")
  testthat::expect_equal(result$activity_id, "31856627")
  testthat::expect_equal(result$window_from_sample_index, 5327L)
  testthat::expect_equal(result$window_to_sample_index, 5387L)
  testthat::expect_equal(result$focus_from_sample_index, 5357L)
  testthat::expect_equal(result$focus_to_sample_index, 5357L)
  testthat::expect_equal(result$calibration_partition, "CALIBRATION")
  testthat::expect_equal(result$source_evidence_sha256, stage2ca_sha256(source_path))
})

testthat::test_that("coverage closes owner-confirmed review without inventing labels", {
  registry <- data.frame(
    request_id = c(
      "STAGE2C_STANDARD_STATIONARY_GAP_31690375_7",
      "STAGE2C_STANDARD_DISTURBANCE_BOUNDARY_158147957_1013",
      "STAGE2C_STANDARD_HIGH_SPEED_AGREEMENT_31856627_5392"
    ),
    activity_id = c("31690375", "158147957", "31856627"),
    request_type = "STANDARD_CONTEXT", overlap_group = "GROUP",
    stringsAsFactors = FALSE
  )
  result <- build_stage2ca_coverage_register(registry)
  testthat::expect_equal(result$review_coverage_status[[1L]], "OWNER_CONFIRMED_PRIOR_DECISIONS_RETAINED")
  testthat::expect_equal(result$review_coverage_status[[2L]], "OWNER_REVIEW_COMPLETE_FINAL_DECISIONS_RECONCILED")
  testthat::expect_equal(result$review_coverage_status[[3L]], "OWNER_REVIEW_COMPLETE_WITH_ACCEPTED_SUPPLEMENTARY_CONTEXT")
  testthat::expect_true(all(result$outstanding_review_requirement == ""))
  testthat::expect_false(any(result$holdout_inspected))
})

testthat::test_that("supplementary overlap requires exact source-faithful agreement", {
  supplementary_root <- tempfile("stage2ca-supplementary-")
  existing_root <- tempfile("stage2c-existing-")
  supplementary_request <- "STAGE2CA_SUPPLEMENTARY_31856627_OFFICE_ONSET_5327_5387"
  existing_request <- "STAGE2C_STANDARD_HIGH_SPEED_AGREEMENT_31856627_5392"
  dir.create(file.path(supplementary_root, supplementary_request), recursive = TRUE)
  dir.create(file.path(existing_root, existing_request), recursive = TRUE)
  observations <- data.frame(
    activity_id = "31856627", sample_index = 5327:5423,
    latitude = 51 + (5327:5423) / 1e6,
    longitude = -0.1 - (5327:5423) / 1e6,
    time_seconds = 5327:5423, distance_metres = 5327:5423,
    stringsAsFactors = FALSE
  )
  segments <- data.frame(
    activity_id = "31856627", from_sample_index = 5327:5422,
    to_sample_index = 5328:5423,
    from_latitude = observations$latitude[-nrow(observations)],
    from_longitude = observations$longitude[-nrow(observations)],
    to_latitude = observations$latitude[-1L],
    to_longitude = observations$longitude[-1L],
    elapsed_time_difference_seconds = 1,
    geographic_displacement_metres = 1,
    device_distance_difference_metres = 1,
    gps_device_distance_signed_difference_metres = 0,
    stringsAsFactors = FALSE
  )
  utils::write.csv(
    observations[observations$sample_index <= 5387L, ],
    file.path(supplementary_root, supplementary_request, "reference_window_observations.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    observations[observations$sample_index >= 5362L, ],
    file.path(existing_root, existing_request, "reference_window_observations.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    segments[segments$to_sample_index <= 5387L, ],
    file.path(supplementary_root, supplementary_request, "reference_window_segments.csv"),
    row.names = FALSE
  )
  utils::write.csv(
    segments[segments$from_sample_index >= 5362L, ],
    file.path(existing_root, existing_request, "reference_window_segments.csv"),
    row.names = FALSE
  )
  result <- validate_stage2ca_supplementary_overlap(supplementary_root, existing_root)
  testthat::expect_equal(result$matching_observation_count, 26L)
  testthat::expect_equal(result$matching_segment_count, 25L)
  testthat::expect_equal(result$overlap_status, "EXACT_MATCH")

  changed <- utils::read.csv(file.path(
    supplementary_root, supplementary_request, "reference_window_observations.csv"
  ))
  changed$latitude[changed$sample_index == 5362L] <- 0
  utils::write.csv(changed, file.path(
    supplementary_root, supplementary_request, "reference_window_observations.csv"
  ), row.names = FALSE)
  testthat::expect_error(
    validate_stage2ca_supplementary_overlap(supplementary_root, existing_root),
    "does not match"
  )
})

testthat::test_that("offline quantitative claims reproduce Stage 2C evidence", {
  root <- path.expand("~/Documents/Cycling/audits/gps-qualification-stage2c-evidence-new")
  testthat::skip_if_not(file.exists(file.path(root, "extraction_manifest.csv")))
  result <- build_stage2ca_quantitative_verification(root)
  testthat::expect_gt(nrow(result), 30L)
  testthat::expect_true(all(result$verification_status %in% c(
    "CONFIRMED", "CONFIRMED_QUALITATIVE", "CORRECTS_EARLIER_DESCRIPTION"
  )))
  kingston <- result$activity_id == "15562928333" &
    result$claim == "Signed discrepancy across segments 1459-1460 through 1470-1471"
  testthat::expect_equal(result$recomputed_value[kingston], -44.4569537928347, tolerance = 1e-9)
  testthat::expect_true(all(grepl("Geographic distance", result$terminology)))
})

testthat::test_that("supplementary onset measurements remain distinct from owner route geometry", {
  root <- path.expand(paste0(
    "~/Documents/Cycling/audits/",
    "gps-qualification-stage2ca-supplementary-office-onset-31856627-2026-11-20"
  ))
  testthat::skip_if_not(file.exists(file.path(root, "extraction_manifest.csv")))
  result <- build_stage2ca_supplementary_quantitative_verification(root)
  focus <- result$claim == "Calculated bearing change at focus"
  testthat::expect_equal(result$recomputed_value[focus], 11.4618907858196, tolerance = 1e-9)
  route <- result$claim == "Owner-reported real route turn"
  testthat::expect_true(is.na(result$recomputed_value[route]))
  testthat::expect_match(result$verification_status[route], "NOT_CALCULABLE")
})
