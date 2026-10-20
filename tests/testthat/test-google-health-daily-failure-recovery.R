validation_file <- file.path(
  "R", "validation", "validate_platform_completeness.R"
)
if (!file.exists(validation_file)) {
  validation_file <- file.path("..", "..", validation_file)
}
source(validation_file)

summary_file <- file.path(
  "R", "validation", "summarize_platform_validation.R"
)
if (!file.exists(summary_file)) {
  summary_file <- file.path("..", "..", summary_file)
}
source(summary_file)

recovery_time <- function(day) {
  as.POSIXct(paste(day, "06:00:00"), tz = "UTC")
}

entity_fixture <- function(
  run_entity_id,
  entity_name = "google_health_daily_resting_heart_rate",
  entity_status = "FAILED",
  started_at = recovery_time("2026-10-19"),
  completed_at = started_at + 60,
  source_id = 2L
) {
  tibble::tibble(
    run_entity_id = run_entity_id,
    source_id = source_id,
    entity_name = entity_name,
    entity_status = entity_status,
    started_at = started_at,
    completed_at = completed_at
  )
}

request_fixture <- function(
  run_entity_id,
  start_date = "2026-10-05",
  end_date = as.character(as.Date(start_date) + 1L),
  request_status = "SUCCESS"
) {
  tibble::tibble(
    run_entity_id = run_entity_id,
    request_status = request_status,
    requested_start_date = as.Date(start_date),
    requested_end_date = as.Date(end_date)
  )
}

failure_history <- function(entities, requests) {
  daily_entities <- c(
    "google_health_daily_resting_heart_rate",
    "google_health_daily_heart_rate_variability",
    "google_health_daily_respiratory_rate"
  )

  failures <- entities |>
    dplyr::filter(
      .data$entity_name %in% daily_entities,
      .data$entity_status == "FAILED"
    )

  purrr::map_dfr(seq_len(nrow(failures)), function(index) {
    failed <- failures[index, , drop = FALSE]
    failed_requests <- requests |>
      dplyr::filter(.data$run_entity_id == failed$run_entity_id[[1]]) |>
      dplyr::filter(.data$requested_end_date > .data$requested_start_date) |>
      dplyr::distinct(.data$requested_start_date, .data$requested_end_date)
    if (nrow(failed_requests) == 0L) {
      return(tibble::tibble(
        run_entity_id = failed$run_entity_id[[1]],
        recovery_status = "UNKNOWN",
        failed_request_window_count = 0L,
        covered_request_window_count = 0L,
        recovery_completed_at = as.POSIXct(NA)
      ))
    }

    boundary <- failed$completed_at[[1]]
    if (is.na(boundary)) boundary <- failed$started_at[[1]]

    recovered_entities <- entities |>
      dplyr::filter(
        .data$entity_name == failed$entity_name[[1]],
        .data$entity_status == "SUCCESS",
        .data$started_at > boundary,
        (.data$source_id == failed$source_id[[1]]) |
          (is.na(.data$source_id) & is.na(failed$source_id[[1]]))
      )
    recovered_requests <- requests |>
      dplyr::filter(.data$run_entity_id %in% recovered_entities$run_entity_id) |>
      dplyr::filter(.data$request_status == "SUCCESS") |>
      dplyr::left_join(
        recovered_entities |>
          dplyr::select("run_entity_id", "completed_at"),
        by = "run_entity_id"
      )

    window_recovery <- purrr::map_dfr(
      seq_len(nrow(failed_requests)),
      function(request_index) {
        request <- failed_requests[request_index, , drop = FALSE]
        days <- seq(
          request$requested_start_date[[1]],
          request$requested_end_date[[1]] - 1L,
          by = "day"
        )
        day_recovery <- vapply(days, function(day) {
          day <- as.Date(day, origin = "1970-01-01")
          candidates <- recovered_requests |>
            dplyr::filter(
              .data$requested_start_date <= day,
              .data$requested_end_date > day
            )
          if (nrow(candidates) == 0L) return(as.numeric(NA))
          min(as.numeric(candidates$completed_at))
        }, numeric(1))
        tibble::tibble(
          covered = all(!is.na(day_recovery)),
          recovery_completed_at = if (all(!is.na(day_recovery))) {
            as.POSIXct(max(day_recovery), origin = "1970-01-01", tz = "UTC")
          } else {
            as.POSIXct(NA)
          }
        )
      }
    )

    is_recovered <- all(window_recovery$covered)
    tibble::tibble(
      run_entity_id = failed$run_entity_id[[1]],
      recovery_status = if (is_recovered) "RECOVERED" else "UNRESOLVED",
      failed_request_window_count = nrow(failed_requests),
      covered_request_window_count = sum(window_recovery$covered),
      recovery_completed_at = if (is_recovered) {
        max(window_recovery$recovery_completed_at)
      } else {
        as.POSIXct(NA)
      }
    )
  })
}

unresolved_ids <- function(entities, requests) {
  history <- failure_history(entities, requests)
  history$run_entity_id[history$recovery_status != "RECOVERED"]
}

testthat::test_that("failed daily entity without later success remains unresolved", {
  entities <- entity_fixture(1)
  requests <- request_fixture(1)

  testthat::expect_equal(unresolved_ids(entities, requests), 1)
})

testthat::test_that("historical age does not suppress unresolved coverage", {
  entities <- entity_fixture(
    1,
    started_at = recovery_time("2025-01-01")
  )
  requests <- request_fixture(1, "2024-12-15")

  testthat::expect_equal(unresolved_ids(entities, requests), 1)
})

testthat::test_that("later successful full coverage resolves a failure", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(
      2,
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- dplyr::bind_rows(
    request_fixture(1),
    request_fixture(2)
  )

  testthat::expect_length(unresolved_ids(entities, requests), 0L)
})

testthat::test_that("success for another entity does not resolve the failure", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(
      2,
      entity_name = "google_health_daily_heart_rate_variability",
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- dplyr::bind_rows(request_fixture(1), request_fixture(2))

  testthat::expect_equal(unresolved_ids(entities, requests), 1)
})

testthat::test_that("non-overlapping later coverage does not resolve a failure", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(
      2,
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- dplyr::bind_rows(
    request_fixture(1),
    request_fixture(2, "2026-10-06")
  )

  testthat::expect_equal(unresolved_ids(entities, requests), 1)
})

testthat::test_that("partial coverage of failed work remains unresolved", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(
      2,
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- dplyr::bind_rows(
    request_fixture(1, "2026-10-05"),
    request_fixture(1, "2026-10-06"),
    request_fixture(2, "2026-10-05")
  )

  testthat::expect_equal(unresolved_ids(entities, requests), 1)
})

testthat::test_that("a later failed execution is not recovery", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(2, started_at = recovery_time("2026-10-20"))
  )
  requests <- dplyr::bind_rows(request_fixture(1), request_fixture(2))

  testthat::expect_equal(sort(unresolved_ids(entities, requests)), c(1, 2))
})

testthat::test_that("one success can cover multiple failures", {
  entities <- dplyr::bind_rows(
    entity_fixture(1, started_at = recovery_time("2026-10-18")),
    entity_fixture(2, started_at = recovery_time("2026-10-19")),
    entity_fixture(
      3,
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- dplyr::bind_rows(
    request_fixture(1, "2026-10-05"),
    request_fixture(2, "2026-10-06"),
    request_fixture(3, "2026-10-05", "2026-10-07")
  )

  testthat::expect_length(unresolved_ids(entities, requests), 0L)
})

testthat::test_that("multiple failures retain only partially recovered debt", {
  entities <- dplyr::bind_rows(
    entity_fixture(1, started_at = recovery_time("2026-10-18")),
    entity_fixture(2, started_at = recovery_time("2026-10-19")),
    entity_fixture(
      3,
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- dplyr::bind_rows(
    request_fixture(1, "2026-10-05"),
    request_fixture(2, "2026-10-06"),
    request_fixture(3, "2026-10-05")
  )

  testthat::expect_equal(unresolved_ids(entities, requests), 2)
})

testthat::test_that("missing request coverage metadata remains unresolved", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(
      2,
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- request_fixture(2)

  testthat::expect_equal(unresolved_ids(entities, requests), 1)
  testthat::expect_identical(
    failure_history(entities, requests)$recovery_status,
    "UNKNOWN"
  )
})

testthat::test_that("adjacent successful windows collectively recover a failed interval", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(2, entity_status = "SUCCESS", started_at = recovery_time("2026-10-20")),
    entity_fixture(3, entity_status = "SUCCESS", started_at = recovery_time("2026-10-21"))
  )
  requests <- dplyr::bind_rows(
    request_fixture(1, "2026-10-05", "2026-10-08"),
    request_fixture(2, "2026-10-05", "2026-10-06"),
    request_fixture(3, "2026-10-06", "2026-10-08")
  )

  history <- failure_history(entities, requests)
  testthat::expect_identical(history$recovery_status, "RECOVERED")
  testthat::expect_equal(history$recovery_completed_at, recovery_time("2026-10-21") + 60)
})

testthat::test_that("a gap between successful windows remains unresolved", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(2, entity_status = "SUCCESS", started_at = recovery_time("2026-10-20")),
    entity_fixture(3, entity_status = "SUCCESS", started_at = recovery_time("2026-10-21"))
  )
  requests <- dplyr::bind_rows(
    request_fixture(1, "2026-10-05", "2026-10-08"),
    request_fixture(2, "2026-10-05", "2026-10-06"),
    request_fixture(3, "2026-10-07", "2026-10-08")
  )

  history <- failure_history(entities, requests)
  testthat::expect_identical(history$recovery_status, "UNRESOLVED")
  testthat::expect_true(is.na(history$recovery_completed_at))
})

testthat::test_that("duplicate failed windows retain one recovery obligation", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(2, entity_status = "SUCCESS", started_at = recovery_time("2026-10-20"))
  )
  requests <- dplyr::bind_rows(
    request_fixture(1), request_fixture(1), request_fixture(2)
  )

  history <- failure_history(entities, requests)
  testthat::expect_equal(history$failed_request_window_count, 1L)
  testthat::expect_equal(history$covered_request_window_count, 1L)
})

testthat::test_that("success from another source cannot establish recovery", {
  entities <- dplyr::bind_rows(
    entity_fixture(1, source_id = 2L),
    entity_fixture(
      2,
      source_id = 3L,
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- dplyr::bind_rows(request_fixture(1), request_fixture(2))

  testthat::expect_equal(unresolved_ids(entities, requests), 1)
})

testthat::test_that("classification leaves historical execution rows unchanged", {
  entities <- dplyr::bind_rows(
    entity_fixture(1),
    entity_fixture(
      2,
      entity_status = "SUCCESS",
      started_at = recovery_time("2026-10-20")
    )
  )
  requests <- dplyr::bind_rows(request_fixture(1), request_fixture(2))
  original <- entities

  unresolved_ids(entities, requests)

  testthat::expect_identical(entities, original)
  testthat::expect_identical(entities$entity_status, c("FAILED", "SUCCESS"))
})

testthat::test_that("all governed daily entities use identical recovery semantics", {
  daily_entities <- c(
    "google_health_daily_resting_heart_rate",
    "google_health_daily_heart_rate_variability",
    "google_health_daily_respiratory_rate"
  )
  entities <- purrr::map2_dfr(
    seq_along(daily_entities),
    daily_entities,
    function(index, entity_name) {
      dplyr::bind_rows(
        entity_fixture(index, entity_name = entity_name),
        entity_fixture(
          index + 10,
          entity_name = entity_name,
          entity_status = "SUCCESS",
          started_at = recovery_time("2026-10-20")
        )
      )
    }
  )
  requests <- dplyr::bind_rows(
    request_fixture(1), request_fixture(11),
    request_fixture(2), request_fixture(12),
    request_fixture(3), request_fixture(13)
  )

  testthat::expect_length(unresolved_ids(entities, requests), 0L)
})

testthat::test_that("validation consumes the authoritative recovery contract", {
  sql <- google_health_daily_unresolved_failures_query()

  testthat::expect_match(
    sql,
    "v_google_health_daily_ingestion_failure_history",
    fixed = TRUE
  )
  testthat::expect_match(sql, "recovery_status IN ('UNRESOLVED', 'UNKNOWN')", fixed = TRUE)
  testthat::expect_false(grepl("INTERVAL 14 DAY", sql, fixed = TRUE))
  testthat::expect_false(grepl("etl_request_log", sql, fixed = TRUE))
})

testthat::test_that("an unresolved issue retains warning governance", {
  results <- tibble::tibble(
    check_name = "raw_google_health_daily_entities_recent_failures",
    check_scope = "deep",
    severity = "WARNING",
    passed = FALSE,
    issue_count = 1L
  )

  summary <- summarize_platform_validation_results(results)
  testthat::expect_identical(summary$validation_outcome, "PASSED_WITH_WARNINGS")
})
