geographic_foundation_root <- local({
  candidates <- c(".", "..", "../..")
  match <- candidates[file.exists(file.path(
    candidates, "R/geography/explorer_tile_geometry.R"
  ))]
  normalizePath(match[[1L]], mustWork = TRUE)
})

source(file.path(
  geographic_foundation_root, "R/geography/explorer_tile_geometry.R"
), local = TRUE)
source(file.path(
  geographic_foundation_root, "R/geography/geographic_tile_evidence.R"
), local = TRUE)

PINNED_EXPLORER_REVISION <- "f93beddc07a0d2b6378a596cc1b2a9ac7f4b55ca"
PINNED_EXPLORER_FIXTURES <- c(
  "tile_geometry.json" = "f11fd577cbcdd938ed325c120d1c7e416e2ff1b0a78aae56e61147519cf187b6",
  "tile_evidence.json" = "4627340c8c6466933a0b9c167e664dfc12ab9c59e2f12ccd622b49bd6a6bd87f",
  "history.json" = "3c4c2f6625ccb4b2163414de3ae0d1ff2d346cda5332dcc39f41762eea25b485"
)

explorer_fixture_root <- function() {
  explorer_root <- Sys.getenv(
    "EXPLORER_REPOSITORY",
    unset = normalizePath(
      file.path(testthat::test_path(), "..", "..", "..", "explorer"),
      mustWork = FALSE
    )
  )
  file.path(explorer_root, "fixtures")
}

assert_pinned_explorer_fixtures <- function() {
  fixture_root <- explorer_fixture_root()
  explorer_root <- dirname(fixture_root)
  revision <- system2(
    "git", c("-C", explorer_root, "rev-parse", "HEAD"),
    stdout = TRUE, stderr = TRUE
  )
  if (!is.null(attr(revision, "status")) || length(revision) != 1L ||
      !identical(trimws(revision[[1L]]), PINNED_EXPLORER_REVISION)) {
    stop("Explorer checkout does not match the pinned G3A revision.", call. = FALSE)
  }
  for (fixture_name in names(PINNED_EXPLORER_FIXTURES)) {
    path <- file.path(fixture_root, fixture_name)
    if (!file.exists(path)) stop("Pinned Explorer fixture is missing.", call. = FALSE)
    actual_hash <- local({
      connection <- file(path, "rb")
      on.exit(close(connection))
      unclass(as.character(openssl::sha256(connection)))
    })
    if (!identical(actual_hash, unname(PINNED_EXPLORER_FIXTURES[[fixture_name]]))) {
      stop("Explorer fixture content does not match the recorded pin.", call. = FALSE)
    }
    payload <- jsonlite::read_json(path, simplifyVector = FALSE)
    if (!identical(payload$format_version, 1L)) {
      stop("Explorer fixture format is unsupported.", call. = FALSE)
    }
  }
  fixture_root
}

make_geographic_observations <- function(
  activity_key = "9007199254740993",
  sample_index = seq_along(longitude) - 1L,
  longitude,
  latitude,
  qualification_status = rep("ACCEPTED", length(longitude)),
  full_resolution_eligible = rep(TRUE, length(longitude)),
  observed_at_utc = rep(NA_character_, length(longitude)),
  representation = "synthetic-stream-v1",
  policy = "synthetic-policy-v1"
) {
  size <- length(longitude)
  data.frame(
    activity_key = rep(activity_key, length.out = size),
    stream_representation_id = rep(representation, length.out = size),
    sample_index = sample_index,
    longitude = longitude,
    latitude = latitude,
    qualification_status = qualification_status,
    full_resolution_eligible = full_resolution_eligible,
    observed_at_utc = observed_at_utc,
    qualification_policy_version = rep(policy, length.out = size),
    source_lineage = rep("synthetic-source", length.out = size),
    representation_lineage = rep("synthetic-full-resolution", length.out = size),
    stringsAsFactors = FALSE
  )
}

test_that("zoom-14 tile geometry follows explicit half-open conventions", {
  expect_equal(
    longitude_latitude_to_explorer_tile(0, 0)$tile_id,
    "14/8192/8192"
  )
  expect_equal(
    longitude_latitude_to_explorer_tile(-90, 66.51326044311186)$tile_id,
    "14/4096/4096"
  )
  expect_equal(
    longitude_latitude_to_explorer_tile(180, 0)$tile_id,
    "14/0/8192"
  )
  expect_equal(
    longitude_latitude_to_explorer_tile(179.999999, 0)$tile_id,
    "14/16383/8192"
  )
  expect_equal(
    longitude_latitude_to_explorer_tile(0.02197265625, 0)$tile_id,
    "14/8193/8192"
  )
  expect_equal(
    longitude_latitude_to_explorer_tile(0, -0.021972655711418845)$tile_id,
    "14/8192/8193"
  )
  expect_error(longitude_latitude_to_explorer_tile(181, 0), "longitude")
  expect_error(
    longitude_latitude_to_explorer_tile(0, -WEB_MERCATOR_LATITUDE_LIMIT),
    "half-open"
  )
  expect_error(longitude_latitude_to_explorer_tile(0, Inf), "finite")
  expect_error(longitude_latitude_to_explorer_tile(NA_real_, 0), "non-missing")
})

test_that("tile identifiers, bounds and projected centres are deterministic", {
  expect_true(validate_explorer_tile_id("14/8192/8192"))
  expect_equal(
    parse_explorer_tile_id("14/8192/8192")[c("zoom", "tile_x", "tile_y")],
    data.frame(zoom = 14L, tile_x = 8192L, tile_y = 8192L)
  )
  expect_error(validate_explorer_tile_id("14/08192/8192"), "canonical")
  expect_error(validate_explorer_tile_id("13/4096/4096"), "unsupported")
  expect_error(validate_explorer_tile_id("14/16384/0"), "unsupported")
  expect_no_warning(expect_error(
    validate_explorer_tile_id("999999999999999999999/0/0"), "unsupported"
  ))
  expect_no_warning(expect_error(
    validate_explorer_tile_id("14/999999999999999999999/0"), "unsupported"
  ))
  expect_no_warning(expect_error(
    validate_explorer_tile_id("14/00/0"), "canonical"
  ))
  bounds <- explorer_tile_bounds("14/8192/8192")
  expect_equal(
    unname(as.numeric(bounds[1, ])),
    c(0, -0.021972655711418845, 0.02197265625, 0),
    tolerance = 1e-12
  )
  centre <- explorer_tile_centre("14/8192/8192")
  expect_equal(
    unname(as.numeric(centre[1, ])),
    c(0.010986328125, -0.010986328057677354),
    tolerance = 1e-12
  )
})

test_that("only accepted full-resolution observations establish tile evidence", {
  observations <- make_geographic_observations(
    longitude = c(0.01, 0.011, 0.012, NA, 181),
    latitude = c(-0.01, -0.011, -0.012, NA, 0),
    qualification_status = c(
      "ACCEPTED", "UNCERTAIN", "REJECTED", "ACCEPTED", "ACCEPTED"
    ),
    full_resolution_eligible = c(TRUE, TRUE, TRUE, TRUE, TRUE),
    observed_at_utc = c("2000-01-01T00:00:00Z", rep(NA_character_, 4))
  )
  result <- calculate_activity_tile_evidence(observations)
  expect_equal(nrow(result$activity_tile_evidence), 1L)
  expect_equal(result$activity_tile_evidence$tile_id, "14/8192/8192")
  expect_equal(result$activity_tile_evidence$qualifying_observation_count, 1L)
  expect_equal(
    result$observation_outcomes$evidence_outcome,
    c(
      "QUALIFYING", "NON_QUALIFYING_STATUS", "NON_QUALIFYING_STATUS",
      "MISSING_COORDINATE", "MALFORMED_COORDINATE"
    )
  )
  expect_equal(
    result$observation_outcomes$coordinate_status,
    c("VALID", "VALID", "VALID", "MISSING", "MALFORMED")
  )
  expect_equal(
    result$observation_outcomes$qualification_status,
    c("ACCEPTED", "UNCERTAIN", "REJECTED", "ACCEPTED", "ACCEPTED")
  )
  expect_equal(
    result$observation_outcomes$tile_evidence_eligible,
    c(TRUE, FALSE, FALSE, FALSE, FALSE)
  )

  reduced <- make_geographic_observations(
    longitude = 0.01, latitude = -0.01, full_resolution_eligible = FALSE
  )
  reduced_result <- calculate_activity_tile_evidence(reduced)
  expect_equal(nrow(reduced_result$activity_tile_evidence), 0L)
  expect_equal(
    reduced_result$observation_outcomes$evidence_outcome,
    "NON_FULL_RESOLUTION"
  )
})

test_that("coordinate validity remains independent across qualification and resolution", {
  combinations <- expand.grid(
    coordinate = c("VALID", "MISSING", "MALFORMED"),
    qualification = c("ACCEPTED", "UNCERTAIN", "REJECTED"),
    full_resolution = c(TRUE, FALSE),
    stringsAsFactors = FALSE
  )
  coordinate_values <- list(
    VALID = c(0.01, -0.01),
    MISSING = c(NA_real_, NA_real_),
    MALFORMED = c(181, 0)
  )
  rows <- lapply(seq_len(nrow(combinations)), function(index) {
    combination <- combinations[index, ]
    coordinate <- coordinate_values[[combination$coordinate]]
    make_geographic_observations(
      sample_index = index - 1L,
      longitude = coordinate[[1L]], latitude = coordinate[[2L]],
      qualification_status = combination$qualification,
      full_resolution_eligible = combination$full_resolution
    )
  })
  result <- calculate_activity_tile_evidence(do.call(rbind, rows))
  outcomes <- result$observation_outcomes
  expect_equal(outcomes$coordinate_status, combinations$coordinate)
  expect_equal(outcomes$qualification_status, combinations$qualification)
  expect_equal(outcomes$full_resolution_eligible, combinations$full_resolution)
  expect_equal(
    outcomes$tile_evidence_eligible,
    combinations$coordinate == "VALID" &
      combinations$qualification == "ACCEPTED" &
      combinations$full_resolution
  )
})

test_that("stationary and repeated accepted samples deduplicate by activity tile", {
  observations <- make_geographic_observations(
    longitude = c(0.01, 0.01, 0.011),
    latitude = c(-0.01, -0.01, -0.011),
    observed_at_utc = c(
      "2000-01-01T00:00:00Z", "2000-01-01T00:00:00Z",
      "2000-01-01T00:00:02Z"
    )
  )
  evidence <- calculate_activity_tile_evidence(observations)$activity_tile_evidence
  expect_equal(nrow(evidence), 1L)
  expect_equal(evidence$qualifying_observation_count, 3L)
  expect_equal(evidence$qualifying_sample_references, "0,1,2")
  expect_true(evidence$chronology_complete)
})

test_that("segment-only and corner-only crossings do not establish tile visits", {
  segment_only <- make_geographic_observations(
    longitude = c(-0.01, 0.03), latitude = c(-0.01, -0.01),
    observed_at_utc = c("2000-01-02T00:00:00Z", "2000-01-02T00:00:01Z")
  )
  evidence <- calculate_activity_tile_evidence(segment_only)$activity_tile_evidence
  expect_setequal(evidence$tile_id, c("14/8191/8192", "14/8193/8192"))
  expect_false("14/8192/8192" %in% evidence$tile_id)

  corner_only <- make_geographic_observations(
    longitude = c(-0.001, 0.002), latitude = c(-0.002, 0.001)
  )
  corner_evidence <- calculate_activity_tile_evidence(corner_only)$activity_tile_evidence
  expect_false("14/8192/8192" %in% corner_evidence$tile_id)
})

test_that("activity keys above 2^53 remain exact and doubles are rejected", {
  observations <- make_geographic_observations(
    activity_key = "9007199254740993", longitude = 0.01, latitude = -0.01
  )
  evidence <- calculate_activity_tile_evidence(observations)$activity_tile_evidence
  expect_identical(evidence$activity_key, "9007199254740993")
  expect_error(
    canonical_geographic_activity_key(9007199254740992),
    "R doubles are not accepted"
  )
})

test_that("malformed structure fails while GPS-less evidence is explicitly empty", {
  gps_less <- make_geographic_observations(
    longitude = numeric(), latitude = numeric(), activity_key = character(),
    sample_index = integer(), qualification_status = character(),
    full_resolution_eligible = logical(), observed_at_utc = character()
  )
  expect_equal(
    nrow(calculate_activity_tile_evidence(gps_less)$activity_tile_evidence), 0L
  )
  malformed <- make_geographic_observations(
    longitude = c(0.01, 0.02), latitude = c(-0.01, -0.02),
    sample_index = c(0L, 0L)
  )
  expect_error(calculate_activity_tile_evidence(malformed), "duplicated")
  mixed_policy <- make_geographic_observations(
    longitude = c(0.01, 0.02), latitude = c(-0.01, -0.02),
    policy = c("q1", "q2")
  )
  expect_error(calculate_activity_tile_evidence(mixed_policy), "cannot mix")
})

test_that("lifetime aggregation counts activities and preserves unknown chronology", {
  first <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "9007199254740993", longitude = 0.01, latitude = -0.01,
    observed_at_utc = "2000-01-02T00:00:00Z"
  ))$activity_tile_evidence
  second <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "9007199254740994", longitude = 0.01, latitude = -0.01,
    observed_at_utc = NA_character_, representation = "synthetic-stream-v2"
  ))$activity_tile_evidence
  third <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "9007199254740995", longitude = 0.01, latitude = -0.01,
    observed_at_utc = "2000-01-03T00:00:00Z", representation = "synthetic-stream-v3"
  ))$activity_tile_evidence
  lifetime <- aggregate_lifetime_tile_visitation(rbind(first, second, third))
  expect_equal(lifetime$distinct_activity_count, 3L)
  expect_equal(lifetime$first_known_activity_key, "9007199254740993")
  expect_equal(lifetime$last_known_activity_key, "9007199254740995")
  expect_false(lifetime$chronology_complete)
  expect_equal(
    lifetime$activity_keys,
    "9007199254740993,9007199254740994,9007199254740995"
  )

  all_unknown <- aggregate_lifetime_tile_visitation(second)
  expect_true(is.na(all_unknown$first_known_visit_at_utc))
  expect_true(is.na(all_unknown$last_known_visit_at_utc))
  expect_true(is.na(all_unknown$first_known_activity_key))
  expect_false(all_unknown$chronology_complete)
})

test_that("replacement and withdrawal equal reconstruction from current evidence", {
  activity_a <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "101", longitude = c(0.01, 0.03), latitude = c(-0.01, -0.01)
  ))$activity_tile_evidence
  activity_b <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "102", longitude = 0.01, latitude = -0.01,
    representation = "stream-b"
  ))$activity_tile_evidence
  initial <- rbind(activity_a, activity_b)
  replacement_a <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "101", longitude = 0.03, latitude = -0.01,
    representation = "stream-a-corrected"
  ))$activity_tile_evidence
  replaced <- replace_activity_tile_evidence(initial, replacement_a, "101")
  reconstructed <- rbind(activity_b, replacement_a)
  expect_identical(
    aggregate_lifetime_tile_visitation(replaced),
    aggregate_lifetime_tile_visitation(reconstructed)
  )
  withdrawn <- replace_activity_tile_evidence(
    replaced, empty_activity_tile_evidence(), "102", withdraw = TRUE
  )
  expect_identical(
    aggregate_lifetime_tile_visitation(withdrawn),
    aggregate_lifetime_tile_visitation(replacement_a)
  )
})

test_that("lifetime aggregation requires one coherent qualification policy", {
  q1_a <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "301", longitude = 0.01, latitude = -0.01,
    policy = "q1", representation = "q1-a"
  ))$activity_tile_evidence
  q1_b <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "302", longitude = 0.03, latitude = -0.01,
    policy = "q1", representation = "q1-b"
  ))$activity_tile_evidence
  q2_a <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "301", longitude = 0.01, latitude = -0.01,
    policy = "q2", representation = "q2-a"
  ))$activity_tile_evidence
  q2_b <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "302", longitude = 0.03, latitude = -0.01,
    policy = "q2", representation = "q2-b"
  ))$activity_tile_evidence
  q2_c <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "303", longitude = 0.01, latitude = -0.01,
    policy = "q2", representation = "q2-c"
  ))$activity_tile_evidence

  homogeneous <- aggregate_lifetime_tile_visitation(rbind(q1_a, q1_b))
  expect_true(all(homogeneous$qualification_policy_version == "q1"))
  expect_error(
    aggregate_lifetime_tile_visitation(rbind(q1_a, q2_c)),
    "one coherent qualification policy"
  )
  expect_error(
    aggregate_lifetime_tile_visitation(rbind(q1_a, q2_b)),
    "one coherent qualification policy"
  )
  partial_transition <- replace_activity_tile_evidence(
    rbind(q1_a, q1_b), q2_a, "301"
  )
  expect_error(
    aggregate_lifetime_tile_visitation(partial_transition),
    "one coherent qualification policy"
  )
  complete_transition <- replace_activity_tile_evidence(
    partial_transition, q2_b, "302"
  )
  expect_identical(
    aggregate_lifetime_tile_visitation(complete_transition),
    aggregate_lifetime_tile_visitation(rbind(q2_a, q2_b))
  )
  expect_identical(
    aggregate_lifetime_tile_visitation(empty_activity_tile_evidence()),
    empty_lifetime_tile_visitation()
  )
})

test_that("activity tile aggregation rejects contradictory supplied evidence", {
  valid <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "401", longitude = 0.01, latitude = -0.01,
    observed_at_utc = "2000-01-01T00:00:00Z"
  ))$activity_tile_evidence
  mismatch <- valid
  mismatch$tile_x <- mismatch$tile_x + 1L
  expect_error(aggregate_lifetime_tile_visitation(mismatch), "agree with tile_id")
  bad_count <- valid
  bad_count$qualifying_observation_count <- 0L
  expect_error(aggregate_lifetime_tile_visitation(bad_count), "positive integer")
  bad_references <- valid
  bad_references$qualifying_sample_references <- "0,0"
  bad_references$qualifying_observation_count <- 2L
  expect_error(aggregate_lifetime_tile_visitation(bad_references), "unique")
  reversed_references <- valid
  reversed_references$qualifying_sample_references <- "1,0"
  reversed_references$qualifying_observation_count <- 2L
  expect_error(aggregate_lifetime_tile_visitation(reversed_references), "increasing")
  bad_time <- valid
  bad_time$first_known_observed_at_utc <-
    bad_time$last_known_observed_at_utc + 1
  expect_error(aggregate_lifetime_tile_visitation(bad_time), "out of order")
  bad_complete <- valid
  bad_complete$first_known_observed_at_utc <- as.POSIXct(NA, tz = "UTC")
  bad_complete$last_known_observed_at_utc <- as.POSIXct(NA, tz = "UTC")
  expect_error(aggregate_lifetime_tile_visitation(bad_complete), "Complete chronology")
  bad_flag <- valid
  bad_flag$chronology_complete <- NA
  expect_error(aggregate_lifetime_tile_visitation(bad_flag), "non-missing logical")
  bad_lineage <- valid
  bad_lineage$source_lineage <- ""
  expect_error(aggregate_lifetime_tile_visitation(bad_lineage), "source_lineage")
})

test_that("replacement and withdrawal arguments fail closed", {
  evidence <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "501", longitude = 0.01, latitude = -0.01
  ))$activity_tile_evidence
  expect_error(
    replace_activity_tile_evidence(evidence, evidence, "501", withdraw = TRUE),
    "cannot include replacement"
  )
  expect_error(
    replace_activity_tile_evidence(evidence, evidence, "501", withdraw = NA),
    "exactly one"
  )
  expect_error(
    replace_activity_tile_evidence(evidence, evidence, "501", withdraw = c(FALSE, TRUE)),
    "exactly one"
  )
})

test_that("timestamp correction changes chronology through whole-activity replacement", {
  original <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "201", longitude = 0.01, latitude = -0.01,
    observed_at_utc = "2000-01-03T00:00:00Z"
  ))$activity_tile_evidence
  other <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "202", longitude = 0.01, latitude = -0.01,
    observed_at_utc = "2000-01-02T00:00:00Z", representation = "other-stream"
  ))$activity_tile_evidence
  corrected <- calculate_activity_tile_evidence(make_geographic_observations(
    activity_key = "201", longitude = 0.01, latitude = -0.01,
    observed_at_utc = "2000-01-01T00:00:00Z",
    representation = "corrected-stream"
  ))$activity_tile_evidence
  before <- aggregate_lifetime_tile_visitation(rbind(original, other))
  after_evidence <- replace_activity_tile_evidence(
    rbind(original, other), corrected, "201"
  )
  after <- aggregate_lifetime_tile_visitation(after_evidence)
  expect_equal(before$first_known_activity_key, "202")
  expect_equal(after$first_known_activity_key, "201")
  expect_equal(after$last_known_activity_key, "202")
})

test_that("results are independent of observation and activity row order", {
  observations <- make_geographic_observations(
    longitude = c(0.03, 0.01, 0.011), latitude = c(-0.01, -0.01, -0.011),
    sample_index = c(2L, 0L, 1L)
  )
  forward <- calculate_activity_tile_evidence(observations)$activity_tile_evidence
  reverse <- calculate_activity_tile_evidence(
    observations[rev(seq_len(nrow(observations))), ]
  )$activity_tile_evidence
  expect_identical(forward, reverse)
})

test_that("pinned Explorer Slice 2 geometry and evidence fixtures conform", {
  fixture_root <- explorer_fixture_root()
  skip_if_not(file.exists(file.path(fixture_root, "tile_geometry.json")))
  fixture_root <- assert_pinned_explorer_fixtures()

  geometry <- jsonlite::read_json(
    file.path(fixture_root, "tile_geometry.json"), simplifyVector = FALSE
  )
  for (case in geometry$cases) {
    if (!is.null(case$expected$tile)) {
      actual <- longitude_latitude_to_explorer_tile(
        case$input$coordinate[[1L]], case$input$coordinate[[2L]]
      )
      expect_equal(
        c(actual$zoom[[1L]], actual$tile_x[[1L]], actual$tile_y[[1L]]),
        as.integer(unlist(case$expected$tile)), info = case$id
      )
    } else if (!is.null(case$expected$error) && !is.null(case$input$coordinate)) {
      expect_error(
        longitude_latitude_to_explorer_tile(
          case$input$coordinate[[1L]], case$input$coordinate[[2L]]
        ), info = case$id
      )
    }
  }

  evidence_fixture <- jsonlite::read_json(
    file.path(fixture_root, "tile_evidence.json"), simplifyVector = FALSE
  )
  fixture_keys <- c(
    "syn-a" = "9007199254740993", "syn-b" = "9007199254740994"
  )
  for (case in evidence_fixture$cases) {
    samples <- case$input$samples
    rows <- lapply(samples, function(sample) {
      coordinate <- sample$coordinate
      if (is.null(coordinate)) coordinate <- list(NA_real_, NA_real_)
      make_geographic_observations(
        activity_key = unname(fixture_keys[[sample$activity_id]]),
        sample_index = as.integer(sample$sample_index),
        longitude = as.numeric(coordinate[[1L]]),
        latitude = as.numeric(coordinate[[2L]]),
        qualification_status = toupper(sample$qualification),
        full_resolution_eligible = identical(sample$resolution, "full"),
        observed_at_utc = sample$timestamp,
        representation = paste0("fixture-", sample$activity_id),
        policy = sample$policy_version
      )
    })
    observations <- do.call(rbind, rows)
    actual <- calculate_activity_tile_evidence(observations)$activity_tile_evidence
    target <- paste(unlist(case$input$target_tile), collapse = "/")
    target_rows <- actual[actual$tile_id == target, , drop = FALSE]
    expect_identical(nrow(target_rows) > 0L,
                     case$expected$positive_visit_evidence, info = case$id)
    expect_equal(length(unique(target_rows$activity_key)),
                 case$expected$distinct_activity_count, info = case$id)
  }
})

test_that("pinned Explorer history fixture conforms for G3A visitation fields", {
  fixture_root <- explorer_fixture_root()
  history_path <- file.path(fixture_root, "history.json")
  skip_if_not(file.exists(history_path))
  fixture_root <- assert_pinned_explorer_fixtures()
  history_path <- file.path(fixture_root, "history.json")
  history <- jsonlite::read_json(history_path, simplifyVector = FALSE)
  ordered <- history$cases[[which(vapply(
    history$cases, function(case) identical(case$id, "ordered-growth"), logical(1)
  ))]]
  anchor <- as.integer(unlist(ordered$input$anchor_tile))
  activity_ids <- vapply(
    ordered$input$activities, function(activity) activity$activity_id, character(1)
  )
  fixture_keys <- setNames(
    as.character(bit64::as.integer64("9007199254740993") +
                   bit64::as.integer64(seq_along(activity_ids) - 1L)),
    activity_ids
  )
  activity_evidence <- function(activity, key) {
    rows <- lapply(activity$visit_evidence, function(event) {
      offset <- as.integer(unlist(event$tile_offset))
      tile_id <- explorer_tile_id(anchor[[2L]] + offset[[1L]],
                                  anchor[[3L]] + offset[[2L]], anchor[[1L]])
      tile <- parse_explorer_tile_id(tile_id)
      data.frame(
        activity_key = key, tile_id = tile_id, zoom = tile$zoom,
        tile_x = tile$tile_x, tile_y = tile$tile_y,
        qualifying_observation_count = 1L,
        qualifying_sample_references = as.character(event$sample_index),
        first_known_observed_at_utc = as.POSIXct(
          event$timestamp, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
        ),
        last_known_observed_at_utc = as.POSIXct(
          event$timestamp, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"
        ),
        chronology_complete = TRUE,
        stream_representation_id = paste0("fixture-", activity$activity_id),
        qualification_policy_version = event$policy_version,
        source_lineage = "explorer-slice-2",
        representation_lineage = "preassigned-tile-event",
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, rows)
  }
  accumulated <- empty_activity_tile_evidence()
  actual_counts <- integer()
  for (index in seq_along(ordered$input$activities)) {
    activity <- ordered$input$activities[[index]]
    accumulated <- rbind(
      accumulated, activity_evidence(activity, fixture_keys[[activity$activity_id]])
    )
    actual_counts <- c(
      actual_counts, nrow(aggregate_lifetime_tile_visitation(accumulated))
    )
  }
  expected_counts <- vapply(
    ordered$expected$checkpoints, function(checkpoint) checkpoint$visited_count,
    integer(1)
  )
  expect_equal(actual_counts, expected_counts)

  origin <- aggregate_lifetime_tile_visitation(accumulated)
  origin <- origin[origin$tile_id == "14/8192/8192", , drop = FALSE]
  expect_equal(origin$distinct_activity_count, 2L)
  expect_equal(origin$first_known_activity_key,
               fixture_keys[[ordered$expected$first_visit_origin]])
  expect_equal(
    origin$last_known_activity_key,
    fixture_keys[[ordered$expected$subsequent_visit_origin[[1L]]]]
  )
})
