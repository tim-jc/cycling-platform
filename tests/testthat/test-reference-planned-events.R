find_planned_events_project_root <- function() {
  candidates <- c(".", "../..")
  candidate <- candidates[file.exists(file.path(candidates, "bootstrap.R"))][1]
  normalizePath(candidate, mustWork = TRUE)
}

planned_events_project_root <- find_planned_events_project_root()
source(file.path(
  planned_events_project_root,
  "R",
  "reference",
  "planned_events.R"
))
source(file.path(
  planned_events_project_root,
  "R",
  "contracts",
  "data_contract_utils.R"
))

valid_planned_event <- function(
  event_key = "event-one",
  stages = list(),
  ...
) {
  overrides <- list(...)
  value <- list(
    event_key = event_key,
    event_name = "Event one",
    start_date = "2027-05-10",
    end_date = NULL,
    event_type = "cycling trip",
    coaching_intent = "prepare_for",
    overall_objective = "Complete comfortably.",
    location = NULL,
    context = NULL,
    notes = NULL,
    is_cancelled = FALSE,
    stages = stages
  )
  value[names(overrides)] <- overrides
  value
}

valid_planned_stage <- function(stage_key = "stage-one", ...) {
  overrides <- list(...)
  value <- list(
    stage_key = stage_key,
    stage_date = "2027-05-10",
    stage_name = "Stage one",
    planned_distance_metres = 85000,
    planned_elevation_gain_metres = 1200,
    terrain_surface_context = "Paved climbing.",
    stage_objective = "Ride steadily."
  )
  value[names(overrides)] <- overrides
  value
}

empty_event_rows <- function() {
  data.frame(
    planned_event_id = integer(),
    event_key = character(),
    event_name = character(),
    start_date = character(),
    end_date = character(),
    event_type = character(),
    coaching_intent = character(),
    overall_objective = character(),
    location = character(),
    context = character(),
    notes = character(),
    is_cancelled = integer(),
    created_at = character(),
    updated_at = character(),
    stringsAsFactors = FALSE
  )
}

empty_stage_rows <- function() {
  data.frame(
    planned_event_stage_id = integer(),
    planned_event_id = integer(),
    stage_key = character(),
    stage_date = character(),
    stage_name = character(),
    planned_distance_metres = numeric(),
    planned_elevation_gain_metres = numeric(),
    terrain_surface_context = character(),
    stage_objective = character(),
    created_at = character(),
    updated_at = character(),
    stringsAsFactors = FALSE
  )
}

make_planned_events_database <- function(fail_on = NULL) {
  state <- new.env(parent = emptyenv())
  state$events <- empty_event_rows()
  state$stages <- empty_stage_rows()
  state$clock <- 0L
  state$transactions <- 0L
  state$rollbacks <- 0L

  timestamp <- function() {
    state$clock <- state$clock + 1L
    sprintf("2026-08-11 10:00:%02d", state$clock)
  }

  get_query <- function(connection, statement, params = list()) {
    if (grepl("JOIN cycling_platform_reference.planned_event_stages", statement, fixed = TRUE)) {
      keys <- unlist(params, use.names = FALSE)
      events <- state$events[state$events$event_key %in% keys, , drop = FALSE]
      stages <- merge(
        events[c("planned_event_id", "event_key")],
        state$stages,
        by = "planned_event_id"
      )
      return(stages[c(
        "event_key", "stage_key", "stage_date", "stage_name",
        "planned_distance_metres", "planned_elevation_gain_metres",
        "terrain_surface_context", "stage_objective"
      )])
    }
    if (grepl("FROM cycling_platform_reference.planned_event_stages", statement, fixed = TRUE)) {
      return(state$stages[
        state$stages$planned_event_id == as.integer(params[[1]]),
        ,
        drop = FALSE
      ])
    }
    if (grepl("WHERE event_key = ?", statement, fixed = TRUE)) {
      return(state$events[
        state$events$event_key == params[[1]],
        setdiff(names(state$events), "event_key"),
        drop = FALSE
      ])
    }
    if (grepl("WHERE event_key IN", statement, fixed = TRUE)) {
      return(state$events[
        state$events$event_key %in% unlist(params, use.names = FALSE),
        setdiff(names(state$events), c(
          "planned_event_id", "created_at", "updated_at"
        )),
        drop = FALSE
      ])
    }
    stop("Unexpected query: ", statement)
  }

  execute <- function(connection, statement, params = list()) {
    if (!is.null(fail_on) && grepl(fail_on, statement, fixed = TRUE)) {
      stop("Injected database write failure.")
    }
    if (grepl("INSERT INTO cycling_platform_reference.planned_events", statement, fixed = TRUE)) {
      now <- timestamp()
      state$events <- rbind(state$events, data.frame(
        planned_event_id = nrow(state$events) + 1L,
        event_key = params[[1]],
        event_name = params[[2]],
        start_date = params[[3]],
        end_date = if (is.null(params[[4]])) NA_character_ else params[[4]],
        event_type = params[[5]],
        coaching_intent = params[[6]],
        overall_objective = if (is.null(params[[7]])) NA_character_ else params[[7]],
        location = if (is.null(params[[8]])) NA_character_ else params[[8]],
        context = if (is.null(params[[9]])) NA_character_ else params[[9]],
        notes = if (is.null(params[[10]])) NA_character_ else params[[10]],
        is_cancelled = params[[11]],
        created_at = now,
        updated_at = now,
        stringsAsFactors = FALSE
      ))
    } else if (grepl("UPDATE cycling_platform_reference.planned_events SET", statement, fixed = TRUE)) {
      index <- match(params[[11]], state$events$event_key)
      for (field_index in seq_along(planned_event_fields())) {
        value <- params[[field_index]]
        if (is.null(value)) value <- NA
        state$events[index, planned_event_fields()[[field_index]]] <- value
      }
      state$events$updated_at[[index]] <- timestamp()
    } else if (grepl("INSERT INTO cycling_platform_reference.planned_event_stages", statement, fixed = TRUE)) {
      now <- timestamp()
      state$stages <- rbind(state$stages, data.frame(
        planned_event_stage_id = nrow(state$stages) + 1L,
        planned_event_id = params[[1]],
        stage_key = params[[2]],
        stage_date = if (is.null(params[[3]])) NA_character_ else params[[3]],
        stage_name = if (is.null(params[[4]])) NA_character_ else params[[4]],
        planned_distance_metres = if (is.null(params[[5]])) NA_real_ else params[[5]],
        planned_elevation_gain_metres = if (is.null(params[[6]])) NA_real_ else params[[6]],
        terrain_surface_context = if (is.null(params[[7]])) NA_character_ else params[[7]],
        stage_objective = if (is.null(params[[8]])) NA_character_ else params[[8]],
        created_at = now,
        updated_at = now,
        stringsAsFactors = FALSE
      ))
    } else if (grepl("UPDATE cycling_platform_reference.planned_event_stages SET", statement, fixed = TRUE)) {
      index <- which(
        state$stages$planned_event_id == as.integer(params[[7]]) &
          state$stages$stage_key == params[[8]]
      )
      for (field_index in seq_along(planned_event_stage_fields())) {
        value <- params[[field_index]]
        if (is.null(value)) value <- NA
        state$stages[index, planned_event_stage_fields()[[field_index]]] <- value
      }
      state$stages$updated_at[[index]] <- timestamp()
    } else if (grepl("DELETE FROM cycling_platform_reference.planned_event_stages", statement, fixed = TRUE)) {
      remove <- state$stages$planned_event_id == as.integer(params[[1]]) &
        state$stages$stage_key %in% unlist(params[-1], use.names = FALSE)
      state$stages <- state$stages[!remove, , drop = FALSE]
    } else {
      stop("Unexpected write: ", statement)
    }
    1L
  }

  with_transaction <- function(connection, code) {
    state$transactions <- state$transactions + 1L
    before_events <- state$events
    before_stages <- state$stages
    tryCatch(
      force(code),
      error = function(error) {
        state$events <- before_events
        state$stages <- before_stages
        state$rollbacks <- state$rollbacks + 1L
        stop(error)
      }
    )
  }

  list(
    state = state,
    get_query = get_query,
    execute = execute,
    with_transaction = with_transaction
  )
}

publish_to_fake <- function(database, events) {
  publish_planned_events(
    connection = NULL,
    events = events,
    get_query = database$get_query,
    execute = database$execute,
    with_transaction = database$with_transaction
  )
}

testthat::test_that("Reference DDL defines the approved exact schema", {
  event_path <- file.path(
    planned_events_project_root, "sql/reference/010_create_planned_events.sql"
  )
  stage_path <- file.path(
    planned_events_project_root,
    "sql/reference/020_create_planned_event_stages.sql"
  )
  event_sql <- paste(readLines(event_path, warn = FALSE), collapse = "\n")
  stage_sql <- paste(readLines(stage_path, warn = FALSE), collapse = "\n")
  event_ddl <- parse_contract_ddl(event_path)
  stage_ddl <- parse_contract_ddl(stage_path)

  testthat::expect_identical(event_ddl$primary_key, "planned_event_id")
  testthat::expect_identical(stage_ddl$primary_key, "planned_event_stage_id")
  testthat::expect_match(event_sql, "UNIQUE KEY uq_reference_planned_events_key")
  testthat::expect_match(
    stage_sql,
    "UNIQUE KEY uq_reference_planned_event_stages_key"
  )
  testthat::expect_match(stage_sql, "DECIMAL(10,0)", fixed = TRUE)
  testthat::expect_equal(length(gregexpr("DECIMAL(10,0)", stage_sql, fixed = TRUE)[[1]]), 2L)
  testthat::expect_match(stage_sql, "ON DELETE RESTRICT", fixed = TRUE)
  testthat::expect_match(stage_sql, "ON UPDATE RESTRICT", fixed = TRUE)
  testthat::expect_match(event_sql, "coaching_intent IN ('prepare_for', 'plan_around')", fixed = TRUE)
  testthat::expect_match(event_sql, "end_date IS NULL OR end_date >= start_date", fixed = TRUE)
  testthat::expect_match(event_sql, "is_cancelled IN (0, 1)", fixed = TRUE)
  testthat::expect_false(grepl("stage_order|planned_duration|activity_id|route_id", stage_sql))
  testthat::expect_false(grepl("notes", stage_sql, fixed = TRUE))
  for (sql in c(event_sql, stage_sql)) {
    testthat::expect_match(sql, "ENGINE=InnoDB", fixed = TRUE)
    testthat::expect_match(sql, "DEFAULT CHARACTER SET utf8mb4", fixed = TRUE)
    testthat::expect_match(sql, "DEFAULT COLLATE utf8mb4_general_ci", fixed = TRUE)
  }
})

testthat::test_that("bootstrap discovers Reference objects in dependency order", {
  source(file.path(
    planned_events_project_root,
    "R/database/bootstrap_platform_schema.R"
  ))
  paths <- list_platform_bootstrap_sql_files(planned_events_project_root)
  reference <- paths[grepl("/sql/reference/", paths, fixed = TRUE)]
  testthat::expect_identical(
    basename(reference),
    c(
      "010_create_planned_events.sql",
      "020_create_planned_event_stages.sql"
    )
  )

  executed <- character()
  bootstrap_platform_schema(
    connection = NULL,
    project_root = planned_events_project_root,
    execute_sql = function(path, connection) {
      executed <<- c(executed, basename(path))
    },
    migrate = function(...) character(),
    database_access_findings = function(connection) data.frame()
  )
  testthat::expect_true(all(basename(reference) %in% executed))
})

testthat::test_that("valid events, stages and missing values normalise", {
  event <- normalise_planned_event(valid_planned_event(
    stages = list(valid_planned_stage(
      stage_name = " ",
      planned_distance_metres = NULL
    )),
    location = "  ",
    notes = " retained "
  ))
  testthat::expect_null(event$end_date)
  testthat::expect_null(event$location)
  testthat::expect_identical(event$notes, "retained")
  testthat::expect_null(event$stages[[1]]$stage_name)
  testthat::expect_null(event$stages[[1]]$planned_distance_metres)
  testthat::expect_false(event$is_cancelled)
})

testthat::test_that("invalid event and stage values are rejected", {
  testthat::expect_error(
    normalise_planned_event(valid_planned_event(start_date = "2027-02-30")),
    "valid calendar date"
  )
  testthat::expect_error(
    normalise_planned_event(valid_planned_event(end_date = "2027-05-09")),
    "must not precede"
  )
  testthat::expect_error(
    normalise_planned_event(valid_planned_event(coaching_intent = "important")),
    "prepare_for or plan_around"
  )
  testthat::expect_error(
    normalise_planned_event(valid_planned_event(is_cancelled = 0L)),
    "true or false"
  )
  testthat::expect_error(
    normalise_planned_event(valid_planned_event(event_name = " ")),
    "non-blank"
  )
  testthat::expect_error(
    normalise_planned_event(valid_planned_event(
      event_name = paste(rep("x", 201L), collapse = "")
    )),
    "200 characters"
  )
  testthat::expect_error(
    normalise_planned_event(valid_planned_event(
      stages = list(valid_planned_stage(planned_distance_metres = -1))
    )),
    "non-negative"
  )
  testthat::expect_error(
    normalise_planned_event(valid_planned_event(
      stages = list(valid_planned_stage(), valid_planned_stage())
    )),
    "duplicate stage_key"
  )
})

testthat::test_that("dataset validates every file before any transaction", {
  directory <- tempfile("planned-events-")
  dir.create(directory)
  yaml::write_yaml(valid_planned_event("first"), file.path(directory, "first.yml"))
  yaml::write_yaml(
    valid_planned_event("second", coaching_intent = "invalid"),
    file.path(directory, "second.yml")
  )
  database <- make_planned_events_database()
  testthat::expect_error(read_planned_events_dataset(directory), "coaching_intent")
  testthat::expect_equal(database$state$transactions, 0L)
})

testthat::test_that("filename and event keys must agree", {
  path <- tempfile(fileext = ".yml")
  yaml::write_yaml(valid_planned_event("different-key"), path)
  testthat::expect_error(read_planned_event_file(path), "must match the filename")
})

testthat::test_that("publication is idempotent and preserves identities and timestamps", {
  database <- make_planned_events_database()
  events <- list(normalise_planned_event(valid_planned_event(
    stages = list(valid_planned_stage())
  )))
  first <- publish_to_fake(database, events)
  event_before <- database$state$events
  stage_before <- database$state$stages
  second <- publish_to_fake(database, events)

  testthat::expect_equal(first$inserted_events, 1L)
  testthat::expect_equal(first$inserted_stages, 1L)
  testthat::expect_equal(second$unchanged_events, 1L)
  testthat::expect_equal(second$unchanged_stages, 1L)
  testthat::expect_equal(second$updated_events, 0L)
  testthat::expect_equal(second$updated_stages, 0L)
  testthat::expect_identical(database$state$events, event_before)
  testthat::expect_identical(database$state$stages, stage_before)
})

testthat::test_that("changed values update stable rows", {
  database <- make_planned_events_database()
  original <- list(normalise_planned_event(valid_planned_event(
    stages = list(valid_planned_stage())
  )))
  publish_to_fake(database, original)
  event_id <- database$state$events$planned_event_id
  stage_id <- database$state$stages$planned_event_stage_id

  changed <- list(normalise_planned_event(valid_planned_event(
    event_name = "Renamed event",
    start_date = "2027-05-11",
    stages = list(valid_planned_stage(stage_objective = "Changed objective."))
  )))
  result <- publish_to_fake(database, changed)
  testthat::expect_equal(result$updated_events, 1L)
  testthat::expect_equal(result$updated_stages, 1L)
  testthat::expect_equal(database$state$events$planned_event_id, event_id)
  testthat::expect_equal(database$state$stages$planned_event_stage_id, stage_id)
})

testthat::test_that("stage omission reconciles but event-file omission does not", {
  database <- make_planned_events_database()
  two_events <- list(
    normalise_planned_event(valid_planned_event(
      "first",
      stages = list(valid_planned_stage("keep"), valid_planned_stage("remove"))
    )),
    normalise_planned_event(valid_planned_event(
      "second",
      is_cancelled = TRUE
    ))
  )
  publish_to_fake(database, two_events)
  result <- publish_to_fake(database, list(normalise_planned_event(
    valid_planned_event("first", stages = list(valid_planned_stage("keep")))
  )))
  testthat::expect_equal(result$removed_stages, 1L)
  testthat::expect_identical(database$state$stages$stage_key, "keep")
  testthat::expect_true("second" %in% database$state$events$event_key)
  testthat::expect_equal(
    database$state$events$is_cancelled[
      database$state$events$event_key == "second"
    ],
    1L
  )
})

testthat::test_that("the same stage key is valid under different parents", {
  database <- make_planned_events_database()
  events <- list(
    normalise_planned_event(valid_planned_event(
      "first",
      stages = list(valid_planned_stage("shared"))
    )),
    normalise_planned_event(valid_planned_event(
      "second",
      stages = list(valid_planned_stage("shared"))
    ))
  )
  result <- publish_to_fake(database, events)
  testthat::expect_equal(result$inserted_stages, 2L)
  testthat::expect_equal(
    length(unique(database$state$stages$planned_event_id)),
    2L
  )
})

testthat::test_that("database failure rolls back the complete publication", {
  database <- make_planned_events_database(
    fail_on = "INSERT INTO cycling_platform_reference.planned_event_stages"
  )
  events <- list(normalise_planned_event(valid_planned_event(
    stages = list(valid_planned_stage())
  )))
  testthat::expect_error(
    publish_to_fake(database, events),
    "Injected database write failure"
  )
  testthat::expect_equal(nrow(database$state$events), 0L)
  testthat::expect_equal(nrow(database$state$stages), 0L)
  testthat::expect_equal(database$state$rollbacks, 1L)
})

testthat::test_that("publication reconciliation reports without changing rows", {
  event <- normalise_planned_event(valid_planned_event(
    stages = list(valid_planned_stage())
  ))
  database_events <- data.frame(
    event_key = "event-one",
    event_name = "Wrong name",
    start_date = "2027-05-10",
    end_date = NA_character_,
    event_type = "cycling trip",
    coaching_intent = "prepare_for",
    overall_objective = "Complete comfortably.",
    location = NA_character_,
    context = NA_character_,
    notes = NA_character_,
    is_cancelled = 0L,
    stringsAsFactors = FALSE
  )
  database_stages <- data.frame(
    event_key = c("event-one", "event-one"),
    stage_key = c("stage-one", "undeclared"),
    stage_date = c("2027-05-10", NA_character_),
    stage_name = c("Stage one", NA_character_),
    planned_distance_metres = c(85000, NA),
    planned_elevation_gain_metres = c(1200, NA),
    terrain_surface_context = c("Paved climbing.", NA_character_),
    stage_objective = c("Different.", NA_character_),
    stringsAsFactors = FALSE
  )
  before_events <- database_events
  before_stages <- database_stages
  findings <- reconcile_planned_events_rows(
    list(event),
    database_events,
    database_stages
  )
  testthat::expect_true(all(c(
    "event_mismatch", "stage_mismatch", "undeclared_stage"
  ) %in% findings$code))
  testthat::expect_identical(database_events, before_events)
  testthat::expect_identical(database_stages, before_stages)
})

testthat::test_that("parent mismatch is visible as missing declared publication", {
  event <- normalise_planned_event(valid_planned_event(
    stages = list(valid_planned_stage())
  ))
  database_events <- data.frame(
    event_key = "event-one",
    event_name = "Event one",
    start_date = "2027-05-10",
    end_date = NA_character_,
    event_type = "cycling trip",
    coaching_intent = "prepare_for",
    overall_objective = "Complete comfortably.",
    location = NA_character_,
    context = NA_character_,
    notes = NA_character_,
    is_cancelled = 0L,
    stringsAsFactors = FALSE
  )
  database_stages <- data.frame(
    event_key = "wrong-parent",
    stage_key = "stage-one",
    stage_date = "2027-05-10",
    stage_name = "Stage one",
    planned_distance_metres = 85000,
    planned_elevation_gain_metres = 1200,
    terrain_surface_context = "Paved climbing.",
    stage_objective = "Ride steadily.",
    stringsAsFactors = FALSE
  )
  findings <- reconcile_planned_events_rows(
    list(event),
    database_events,
    database_stages
  )
  testthat::expect_true("stage_count" %in% findings$code)
})

testthat::test_that("coaching query uses effective dates without flattening stages", {
  captured <- NULL
  get_upcoming_planned_events(
    NULL,
    as_of_date = as.Date("2027-01-01"),
    get_query = function(connection, statement, params) {
      captured <<- list(statement = statement, params = params)
      data.frame()
    }
  )
  testthat::expect_match(
    captured$statement,
    "COALESCE(end_date, start_date) >= ?",
    fixed = TRUE
  )
  testthat::expect_match(
    captured$statement,
    "ORDER BY start_date, planned_event_id",
    fixed = TRUE
  )
  testthat::expect_identical(captured$params, list("2027-01-01"))
})
