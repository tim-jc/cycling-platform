planned_event_fields <- function() {
  c(
    "event_name", "start_date", "end_date", "event_type",
    "coaching_intent", "overall_objective", "location", "context", "notes",
    "is_cancelled"
  )
}

planned_event_stage_fields <- function() {
  c(
    "stage_date", "stage_name", "planned_distance_metres",
    "planned_elevation_gain_metres", "terrain_surface_context",
    "stage_objective"
  )
}

planned_events_fail <- function(path, field, message) {
  stop(path, ": ", field, " ", message, call. = FALSE)
}

normalise_optional_planned_text <- function(
  value,
  path,
  field,
  maximum_characters = NULL
) {
  if (is.null(value)) return(NULL)
  if (!is.character(value) || length(value) != 1L || is.na(value)) {
    planned_events_fail(path, field, "must be text or null.")
  }
  value <- trimws(value)
  if (
    nzchar(value) &&
      !is.null(maximum_characters) &&
      nchar(value, type = "chars") > maximum_characters
  ) {
    planned_events_fail(
      path,
      field,
      paste0("must not exceed ", maximum_characters, " characters.")
    )
  }
  if (nzchar(value)) value else NULL
}

normalise_required_planned_text <- function(
  value,
  path,
  field,
  maximum_characters = NULL
) {
  value <- normalise_optional_planned_text(
    value,
    path,
    field,
    maximum_characters
  )
  if (is.null(value)) planned_events_fail(path, field, "must be non-blank text.")
  value
}

normalise_planned_date <- function(value, path, field, required = FALSE) {
  if (is.null(value)) {
    if (required) planned_events_fail(path, field, "is required.")
    return(NULL)
  }
  if (inherits(value, "Date")) value <- format(value, "%Y-%m-%d")
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", value)) {
    planned_events_fail(path, field, "must be an exact YYYY-MM-DD date or null.")
  }
  parsed <- as.Date(value, format = "%Y-%m-%d")
  if (is.na(parsed) || format(parsed, "%Y-%m-%d") != value) {
    planned_events_fail(path, field, "is not a valid calendar date.")
  }
  value
}

normalise_planned_boolean <- function(value, path, field) {
  if (!is.logical(value) || length(value) != 1L || is.na(value)) {
    planned_events_fail(path, field, "must be explicitly true or false.")
  }
  value
}

normalise_planned_metres <- function(value, path, field) {
  if (is.null(value)) return(NULL)
  if (!is.numeric(value) || length(value) != 1L || is.na(value) ||
      !is.finite(value) || value < 0 || value != floor(value) ||
      value > 9999999999) {
    planned_events_fail(
      path,
      field,
      "must be a non-negative whole number of metres up to 9999999999, or null."
    )
  }
  as.numeric(value)
}

reject_unknown_planned_fields <- function(value, allowed, path) {
  unknown <- setdiff(names(value), allowed)
  if (length(unknown)) {
    stop(
      path,
      ": unsupported field(s): ",
      paste(unknown, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
}

normalise_planned_event_stage <- function(stage, path, index) {
  stage_path <- paste0(path, ": stages[", index, "]")
  if (!is.list(stage) || is.null(names(stage))) {
    stop(stage_path, " must be a YAML mapping.", call. = FALSE)
  }
  reject_unknown_planned_fields(
    stage,
    c("stage_key", planned_event_stage_fields()),
    stage_path
  )

  list(
    stage_key = normalise_required_planned_text(
      stage$stage_key, stage_path, "stage_key", 100L
    ),
    stage_date = normalise_planned_date(
      stage$stage_date, stage_path, "stage_date"
    ),
    stage_name = normalise_optional_planned_text(
      stage$stage_name, stage_path, "stage_name", 200L
    ),
    planned_distance_metres = normalise_planned_metres(
      stage$planned_distance_metres,
      stage_path,
      "planned_distance_metres"
    ),
    planned_elevation_gain_metres = normalise_planned_metres(
      stage$planned_elevation_gain_metres,
      stage_path,
      "planned_elevation_gain_metres"
    ),
    terrain_surface_context = normalise_optional_planned_text(
      stage$terrain_surface_context, stage_path, "terrain_surface_context"
    ),
    stage_objective = normalise_optional_planned_text(
      stage$stage_objective, stage_path, "stage_objective"
    )
  )
}

normalise_planned_event <- function(value, path = "planned event") {
  if (!is.list(value) || is.null(names(value))) {
    stop(path, " must contain one YAML mapping.", call. = FALSE)
  }
  reject_unknown_planned_fields(
    value,
    c("event_key", planned_event_fields(), "stages"),
    path
  )

  stages <- value$stages
  if (is.null(stages)) stages <- list()
  if (!is.list(stages) || (!is.null(names(stages)) && length(stages))) {
    planned_events_fail(path, "stages", "must be a YAML list or null.")
  }
  stages <- lapply(
    seq_along(stages),
    function(index) normalise_planned_event_stage(stages[[index]], path, index)
  )
  stage_keys <- vapply(stages, function(stage) stage$stage_key, character(1))
  duplicates <- unique(stage_keys[duplicated(stage_keys)])
  if (length(duplicates)) {
    planned_events_fail(
      path,
      "stages",
      paste0(
        "contains duplicate stage_key value(s): ",
        paste(duplicates, collapse = ", "),
        "."
      )
    )
  }

  start_date <- normalise_planned_date(
    value$start_date, path, "start_date", required = TRUE
  )
  end_date <- normalise_planned_date(value$end_date, path, "end_date")
  if (!is.null(end_date) && end_date < start_date) {
    planned_events_fail(path, "end_date", "must not precede start_date.")
  }
  coaching_intent <- normalise_required_planned_text(
    value$coaching_intent, path, "coaching_intent", 20L
  )
  if (!coaching_intent %in% c("prepare_for", "plan_around")) {
    planned_events_fail(
      path,
      "coaching_intent",
      "must be prepare_for or plan_around."
    )
  }

  list(
    event_key = normalise_required_planned_text(
      value$event_key, path, "event_key", 100L
    ),
    event_name = normalise_required_planned_text(
      value$event_name, path, "event_name", 200L
    ),
    start_date = start_date,
    end_date = end_date,
    event_type = normalise_required_planned_text(
      value$event_type, path, "event_type", 150L
    ),
    coaching_intent = coaching_intent,
    overall_objective = normalise_optional_planned_text(
      value$overall_objective, path, "overall_objective"
    ),
    location = normalise_optional_planned_text(
      value$location, path, "location", 255L
    ),
    context = normalise_optional_planned_text(value$context, path, "context"),
    notes = normalise_optional_planned_text(value$notes, path, "notes"),
    is_cancelled = normalise_planned_boolean(
      value$is_cancelled, path, "is_cancelled"
    ),
    stages = stages,
    source_path = path
  )
}

read_planned_event_file <- function(path) {
  event <- tryCatch(
    yaml::read_yaml(path),
    error = function(error) {
      stop(path, ": invalid YAML: ", conditionMessage(error), call. = FALSE)
    }
  )
  event <- normalise_planned_event(event, path)
  expected_key <- tools::file_path_sans_ext(basename(path))
  if (!identical(event$event_key, expected_key)) {
    planned_events_fail(
      path,
      "event_key",
      paste0("must match the filename '", expected_key, "'.")
    )
  }
  event
}

read_planned_events_dataset <- function(
  directory = file.path("data", "reference", "planned_events")
) {
  if (!dir.exists(directory)) {
    stop("Planned-events directory does not exist: ", directory, call. = FALSE)
  }
  paths <- sort(list.files(directory, pattern = "[.]ya?ml$", full.names = TRUE))
  events <- lapply(paths, read_planned_event_file)
  event_keys <- vapply(events, function(event) event$event_key, character(1))
  duplicates <- unique(event_keys[duplicated(event_keys)])
  if (length(duplicates)) {
    stop(
      "Planned-events dataset contains duplicate event_key value(s): ",
      paste(duplicates, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  events
}

planned_value_for_compare <- function(value, field) {
  if (length(value) == 0L || is.null(value) || is.na(value)) return(NA_character_)
  if (field == "is_cancelled") return(if (isTRUE(as.logical(value))) "1" else "0")
  if (field %in% c("planned_distance_metres", "planned_elevation_gain_metres")) {
    return(format(as.numeric(value), scientific = FALSE, trim = TRUE))
  }
  if (inherits(value, "Date") || inherits(value, "POSIXt")) {
    return(format(value, "%Y-%m-%d"))
  }
  as.character(value)
}

planned_row_matches <- function(authored, database_row, fields) {
  all(vapply(fields, function(field) {
    identical(
      planned_value_for_compare(authored[[field]], field),
      planned_value_for_compare(database_row[[field]], field)
    )
  }, logical(1)))
}

planned_database_param <- function(value, field) {
  if (!is.null(value)) return(value)
  if (field %in% c(
    "planned_distance_metres",
    "planned_elevation_gain_metres"
  )) {
    return(NA_real_)
  }
  if (field == "is_cancelled") return(NA_integer_)
  NA_character_
}

planned_database_params <- function(value, fields) {
  unname(lapply(
    fields,
    function(field) planned_database_param(value[[field]], field)
  ))
}

planned_event_params <- function(event) {
  c(
    planned_database_params(
      event,
      c("event_key", planned_event_fields()[1:9])
    ),
    list(as.integer(event$is_cancelled))
  )
}

planned_stage_params <- function(stage, planned_event_id) {
  c(
    list(planned_event_id, stage$stage_key),
    planned_database_params(stage, planned_event_stage_fields())
  )
}

publish_planned_events <- function(
  connection,
  events = read_planned_events_dataset(),
  get_query = DBI::dbGetQuery,
  execute = DBI::dbExecute,
  with_transaction = DBI::dbWithTransaction,
  validate_after = validate_planned_events_publication
) {
  stats <- list(
    inserted_events = 0L, updated_events = 0L, unchanged_events = 0L,
    inserted_stages = 0L, updated_stages = 0L, unchanged_stages = 0L,
    removed_stages = 0L
  )

  with_transaction(connection, {
    for (event in events) {
      existing_event <- get_query(
        connection,
        paste(
          "SELECT planned_event_id, event_name, start_date, end_date,",
          "event_type, coaching_intent, overall_objective, location, context,",
          "notes, is_cancelled, created_at, updated_at",
          "FROM cycling_platform_reference.planned_events",
          "WHERE event_key = ?"
        ),
        params = list(event$event_key)
      )

      if (!nrow(existing_event)) {
        execute(
          connection,
          paste(
            "INSERT INTO cycling_platform_reference.planned_events (",
            "event_key, event_name, start_date, end_date, event_type,",
            "coaching_intent, overall_objective, location, context, notes,",
            "is_cancelled) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
          ),
          params = planned_event_params(event)
        )
        existing_event <- get_query(
          connection,
          paste(
            "SELECT planned_event_id, event_name, start_date, end_date,",
            "event_type, coaching_intent, overall_objective, location, context,",
            "notes, is_cancelled, created_at, updated_at",
            "FROM cycling_platform_reference.planned_events",
            "WHERE event_key = ?"
          ),
          params = list(event$event_key)
        )
        stats$inserted_events <- stats$inserted_events + 1L
      } else if (planned_row_matches(
        event,
        existing_event[1, ],
        planned_event_fields()
      )) {
        stats$unchanged_events <- stats$unchanged_events + 1L
      } else {
        execute(
          connection,
          paste(
            "UPDATE cycling_platform_reference.planned_events SET",
            "event_name = ?, start_date = ?, end_date = ?, event_type = ?,",
            "coaching_intent = ?, overall_objective = ?, location = ?,",
            "context = ?, notes = ?, is_cancelled = ? WHERE event_key = ?"
          ),
          params = c(
            planned_database_params(
              event,
              planned_event_fields()[1:9]
            ),
            list(as.integer(event$is_cancelled), event$event_key)
          )
        )
        stats$updated_events <- stats$updated_events + 1L
      }

      planned_event_id <- existing_event$planned_event_id[[1]]
      existing_stages <- get_query(
        connection,
        paste(
          "SELECT planned_event_stage_id, stage_key, stage_date, stage_name,",
          "planned_distance_metres, planned_elevation_gain_metres,",
          "terrain_surface_context, stage_objective, created_at, updated_at",
          "FROM cycling_platform_reference.planned_event_stages",
          "WHERE planned_event_id = ?"
        ),
        params = list(planned_event_id)
      )

      for (stage in event$stages) {
        match_index <- match(stage$stage_key, existing_stages$stage_key)
        if (is.na(match_index)) {
          execute(
            connection,
            paste(
              "INSERT INTO cycling_platform_reference.planned_event_stages (",
              "planned_event_id, stage_key, stage_date, stage_name,",
              "planned_distance_metres, planned_elevation_gain_metres,",
              "terrain_surface_context, stage_objective)",
              "VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            ),
            params = planned_stage_params(stage, planned_event_id)
          )
          stats$inserted_stages <- stats$inserted_stages + 1L
        } else if (planned_row_matches(
          stage,
          existing_stages[match_index, ],
          planned_event_stage_fields()
        )) {
          stats$unchanged_stages <- stats$unchanged_stages + 1L
        } else {
          execute(
            connection,
            paste(
              "UPDATE cycling_platform_reference.planned_event_stages SET",
              "stage_date = ?, stage_name = ?, planned_distance_metres = ?,",
              "planned_elevation_gain_metres = ?, terrain_surface_context = ?,",
              "stage_objective = ?",
              "WHERE planned_event_id = ? AND stage_key = ?"
            ),
            params = c(
              planned_database_params(
                stage,
                planned_event_stage_fields()
              ),
              list(planned_event_id, stage$stage_key)
            )
          )
          stats$updated_stages <- stats$updated_stages + 1L
        }
      }

      declared_stage_keys <- vapply(
        event$stages,
        function(stage) stage$stage_key,
        character(1)
      )
      removed <- setdiff(existing_stages$stage_key, declared_stage_keys)
      if (length(removed)) {
        execute(
          connection,
          paste0(
            "DELETE FROM cycling_platform_reference.planned_event_stages ",
            "WHERE planned_event_id = ? AND stage_key IN (",
            paste(rep("?", length(removed)), collapse = ", "),
            ")"
          ),
          params = c(list(planned_event_id), as.list(removed))
        )
        stats$removed_stages <- stats$removed_stages + length(removed)
      }
    }
  })

  validation <- validate_after(connection, events, get_query = get_query)
  if (!isTRUE(validation$passed)) {
    stop(
      "Planned-events publication committed but post-publication validation failed: ",
      paste(validation$findings$message, collapse = "; "),
      call. = FALSE
    )
  }

  stats$event_files <- length(events)
  stats$validation <- validation
  stats
}

reconcile_planned_events_rows <- function(events, database_events, database_stages) {
  findings <- list()
  add <- function(code, key, message) {
    findings[[length(findings) + 1L]] <<- data.frame(
      code = code,
      object_key = key,
      message = message,
      stringsAsFactors = FALSE
    )
  }

  for (event in events) {
    rows <- database_events[
      database_events$event_key == event$event_key,
      ,
      drop = FALSE
    ]
    if (nrow(rows) != 1L) {
      add("event_count", event$event_key, "Expected exactly one database event row.")
      next
    }
    if (!planned_row_matches(event, rows[1, ], planned_event_fields())) {
      add("event_mismatch", event$event_key, "Database event values differ from YAML.")
    }
    authored_stages <- vapply(
      event$stages,
      function(stage) stage$stage_key,
      character(1)
    )
    published <- database_stages[
      database_stages$event_key == event$event_key,
      ,
      drop = FALSE
    ]
    for (stage in event$stages) {
      stage_rows <- published[
        published$stage_key == stage$stage_key,
        ,
        drop = FALSE
      ]
      key <- paste(event$event_key, stage$stage_key, sep = "/")
      if (nrow(stage_rows) != 1L) {
        add("stage_count", key, "Expected exactly one database stage row.")
      } else if (!planned_row_matches(
        stage,
        stage_rows[1, ],
        planned_event_stage_fields()
      )) {
        add("stage_mismatch", key, "Database stage values differ from YAML.")
      }
    }
    undeclared <- setdiff(published$stage_key, authored_stages)
    for (stage_key in undeclared) {
      add(
        "undeclared_stage",
        paste(event$event_key, stage_key, sep = "/"),
        "Database stage is not declared by the successfully published event file."
      )
    }
  }

  if (!length(findings)) {
    return(data.frame(
      code = character(),
      object_key = character(),
      message = character()
    ))
  }
  do.call(rbind, findings)
}

validate_planned_events_publication <- function(
  connection,
  events = read_planned_events_dataset(),
  get_query = DBI::dbGetQuery
) {
  if (!length(events)) {
    empty <- data.frame(
      code = character(),
      object_key = character(),
      message = character()
    )
    return(list(passed = TRUE, findings = empty))
  }
  event_keys <- vapply(events, function(event) event$event_key, character(1))
  placeholders <- paste(rep("?", length(event_keys)), collapse = ", ")
  database_events <- get_query(
    connection,
    paste0(
      "SELECT event_key, event_name, start_date, end_date, event_type, ",
      "coaching_intent, overall_objective, location, context, notes, is_cancelled ",
      "FROM cycling_platform_reference.planned_events WHERE event_key IN (",
      placeholders,
      ")"
    ),
    params = as.list(event_keys)
  )
  database_stages <- get_query(
    connection,
    paste0(
      "SELECT events.event_key, stages.stage_key, stages.stage_date, ",
      "stages.stage_name, stages.planned_distance_metres, ",
      "stages.planned_elevation_gain_metres, stages.terrain_surface_context, ",
      "stages.stage_objective ",
      "FROM cycling_platform_reference.planned_events events ",
      "JOIN cycling_platform_reference.planned_event_stages stages ",
      "ON stages.planned_event_id = events.planned_event_id ",
      "WHERE events.event_key IN (",
      placeholders,
      ")"
    ),
    params = as.list(event_keys)
  )
  findings <- reconcile_planned_events_rows(
    events,
    database_events,
    database_stages
  )
  list(passed = nrow(findings) == 0L, findings = findings)
}

get_upcoming_planned_events <- function(
  connection,
  as_of_date = Sys.Date(),
  get_query = DBI::dbGetQuery
) {
  get_query(
    connection,
    paste(
      "SELECT planned_event_id, event_key, event_name, start_date, end_date,",
      "COALESCE(end_date, start_date) AS effective_end_date, event_type,",
      "coaching_intent, overall_objective, location, context, notes",
      "FROM cycling_platform_reference.planned_events",
      "WHERE is_cancelled = 0",
      "AND COALESCE(end_date, start_date) >= ?",
      "ORDER BY start_date, planned_event_id"
    ),
    params = list(as.character(as_of_date))
  )
}

get_planned_event_stages <- function(
  connection,
  planned_event_id,
  get_query = DBI::dbGetQuery
) {
  get_query(
    connection,
    paste(
      "SELECT planned_event_stage_id, planned_event_id, stage_key, stage_date,",
      "stage_name, planned_distance_metres, planned_elevation_gain_metres,",
      "terrain_surface_context, stage_objective",
      "FROM cycling_platform_reference.planned_event_stages",
      "WHERE planned_event_id = ?"
    ),
    params = list(planned_event_id)
  )
}

run_planned_events_publication <- function(
  events = read_planned_events_dataset(),
  connection = NULL,
  connect = get_connection,
  disconnect = DBI::dbDisconnect,
  publisher = publish_planned_events
) {
  owns_connection <- is.null(connection)
  if (owns_connection) {
    connection <- connect("cycling_platform_reference")
    on.exit(disconnect(connection), add = TRUE)
  }

  publisher(connection, events)
}
