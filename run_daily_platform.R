# run_daily_platform.R
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

raw_execution_mode <- "scheduled"

if (length(args) > 0) {
  raw_execution_mode <- tolower(args[[1]])
}

if (!raw_execution_mode %in% c("scheduled", "manual", "streams_only")) {
  stop(
    "Unknown automation raw mode. Use 'scheduled', 'manual', or 'streams_only'. ",
    "Backfill is intentionally excluded from unattended automation.",
    call. = FALSE
  )
}

phase_results <- data.frame(
  phase_name = character(),
  phase_status = character(),
  started_at = as.POSIXct(character()),
  completed_at = as.POSIXct(character()),
  duration_seconds = numeric(),
  error_message = character()
)

raw_ingestion_summary <- NULL

get_latest_etl_run_id <- function() {
  connection <- get_connection("cycling_platform_admin")

  tryCatch(
    {
      latest_run <- DBI::dbGetQuery(
        conn = connection,
        statement = "
          SELECT COALESCE(MAX(run_id), 0) AS run_id
          FROM cycling_platform_admin.etl_run
        "
      )

      latest_run$run_id[[1]]
    },
    finally = {
      if (DBI::dbIsValid(connection)) {
        DBI::dbDisconnect(connection)
      }
    }
  )
}

get_raw_ingestion_summary <- function(previous_run_id) {
  connection <- get_connection("cycling_platform_admin")

  tryCatch(
    {
      if (is.na(previous_run_id)) {
        run <- DBI::dbGetQuery(
          conn = connection,
          statement = "
            SELECT
              run_id,
              run_mode,
              run_status,
              duration_seconds
            FROM cycling_platform_admin.etl_run
            ORDER BY run_id DESC
            LIMIT 1
          "
        )
      } else {
        run <- DBI::dbGetQuery(
          conn = connection,
          statement = "
            SELECT
              run_id,
              run_mode,
              run_status,
              duration_seconds
            FROM cycling_platform_admin.etl_run
            WHERE run_id > ?
            ORDER BY run_id DESC
            LIMIT 1
          ",
          params = list(previous_run_id)
        )
      }

      if (nrow(run) != 1) {
        return(NULL)
      }

      entity_summary <- DBI::dbGetQuery(
        conn = connection,
        statement = "
          SELECT
            entity_name,
            entity_status,
            rows_inserted,
            rows_updated
          FROM cycling_platform_admin.etl_run_entity
          WHERE run_id = ?
          ORDER BY run_entity_id
        ",
        params = list(run$run_id[[1]])
      )

      pending_summary <- DBI::dbGetQuery(
        conn = connection,
        statement = "
          SELECT
            COALESCE(
              SUM(stream_status IN ('PENDING', 'FAILED')),
              0
            ) AS streams_remaining,
            COALESCE(
              SUM(details_status IN ('PENDING', 'FAILED')),
              0
            ) AS details_remaining,
            COALESCE(
              SUM(laps_status IN ('PENDING', 'FAILED')),
              0
            ) AS laps_remaining
          FROM cycling_platform_raw.activities
        "
      )

      entity_lines <- character()

      if (nrow(entity_summary) > 0) {
        entity_lines <- purrr::pmap_chr(
          entity_summary[
            c(
              "entity_name",
              "entity_status",
              "rows_inserted",
              "rows_updated"
            )
          ],
          \(entity_name, entity_status, rows_inserted, rows_updated) {
            paste0(
              entity_name,
              ": ",
              entity_status,
              " · +",
              rows_inserted,
              " / ~",
              rows_updated
            )
          }
        )
      }

      list(
        run_line = glue::glue(
          "Run: raw #{run$run_id[[1]]} · {run$run_mode[[1]]} · ",
          "{format_platform_duration(run$duration_seconds[[1]])}"
        ),
        entity_lines = entity_lines,
        pending_line = glue::glue(
          "Pending: streams {pending_summary$streams_remaining[[1]]} · ",
          "details {pending_summary$details_remaining[[1]]} · ",
          "laps {pending_summary$laps_remaining[[1]]}"
        )
      )
    },
    finally = {
      if (DBI::dbIsValid(connection)) {
        DBI::dbDisconnect(connection)
      }
    }
  )
}

record_phase <- function(
  phase_name,
  phase_status,
  started_at,
  completed_at,
  error_message = ""
) {
  phase_results <<- rbind(
    phase_results,
    data.frame(
      phase_name = phase_name,
      phase_status = phase_status,
      started_at = started_at,
      completed_at = completed_at,
      duration_seconds = as.numeric(
        difftime(
          completed_at,
          started_at,
          units = "secs"
        )
      ),
      error_message = error_message
    )
  )
}

condition_message_safe <- function(e) {
  message <- conditionMessage(e)

  if (
    is.null(message) ||
      !nzchar(trimws(message)) ||
      grepl("^\\s*\\[0\\]\\s*$", message)
  ) {
    message <- paste(
      capture.output(
        str(e)
      ),
      collapse = " "
    )
  }

  message
}

tail_file_lines <- function(path, n = 25L) {
  if (!file.exists(path) || file.info(path)$size == 0) {
    return(character())
  }

  lines <- readLines(
    path,
    warn = FALSE
  )

  utils::tail(
    lines,
    n = n
  )
}

format_child_process_failure <- function(
  label,
  status,
  stdout_file,
  stderr_file,
  tail_lines = 25L
) {
  stdout_tail <- tail_file_lines(
    path = stdout_file,
    n = tail_lines
  )

  stderr_tail <- tail_file_lines(
    path = stderr_file,
    n = tail_lines
  )

  output_parts <- c(
    if (length(stderr_tail) > 0) {
      c(
        "stderr tail:",
        stderr_tail
      )
    },
    if (length(stdout_tail) > 0) {
      c(
        "stdout tail:",
        stdout_tail
      )
    }
  )

  if (length(output_parts) == 0) {
    output_parts <- "No child-process output captured."
  }

  paste(
    c(
      glue::glue("{label} failed with exit status {status}."),
      output_parts
    ),
    collapse = "\n"
  )
}

run_child_rscript <- function(
  script,
  args = character(),
  label = script,
  tail_lines = 25L
) {
  stdout_file <- tempfile(
    pattern = "cycling-platform-child-stdout-"
  )

  stderr_file <- tempfile(
    pattern = "cycling-platform-child-stderr-"
  )

  on.exit(
    unlink(
      c(
        stdout_file,
        stderr_file
      ),
      force = TRUE
    ),
    add = TRUE
  )

  status <- system2(
    command = file.path(
      R.home("bin"),
      "Rscript"
    ),
    args = c(
      script,
      args
    ),
    stdout = stdout_file,
    stderr = stderr_file
  )

  stdout_tail <- tail_file_lines(
    path = stdout_file,
    n = tail_lines
  )

  stderr_tail <- tail_file_lines(
    path = stderr_file,
    n = tail_lines
  )

  if (length(stdout_tail) > 0) {
    message(
      paste(
        stdout_tail,
        collapse = "\n"
      )
    )
  }

  if (length(stderr_tail) > 0) {
    message(
      paste(
        stderr_tail,
        collapse = "\n"
      )
    )
  }

  if (!identical(status, 0L)) {
    stop(
      format_child_process_failure(
        label = label,
        status = status,
        stdout_file = stdout_file,
        stderr_file = stderr_file,
        tail_lines = tail_lines
      ),
      call. = FALSE
    )
  }

  invisible(status)
}

describe_automation_error <- function(e, phase_name = NULL) {
  message <- condition_message_safe(e)
  error_class <- paste(
    class(e),
    collapse = "/"
  )

  error_call <- conditionCall(e)
  error_call_text <- if (is.null(error_call)) {
    NA_character_
  } else {
    paste(
      deparse(error_call),
      collapse = " "
    )
  }

  parts <- c(
    if (!is.null(phase_name)) {
      paste0("phase=", phase_name)
    },
    paste0("class=", error_class),
    paste0("message=", message),
    if (!is.na(error_call_text) && nzchar(error_call_text)) {
      paste0("call=", error_call_text)
    }
  )

  paste(
    parts,
    collapse = "; "
  )
}

run_phase <- function(phase_name, expr) {
  started_at <- Sys.time()

  message(glue::glue(
    "Starting automation phase: {phase_name}."
  ))

  tryCatch(
    {
      force(expr)

      completed_at <- Sys.time()

      record_phase(
        phase_name = phase_name,
        phase_status = "SUCCESS",
        started_at = started_at,
        completed_at = completed_at
      )

      message(glue::glue(
        "Completed automation phase: {phase_name} in ",
        "{round(as.numeric(difftime(completed_at, started_at, units = 'secs')), 1)}s."
      ))
    },
    error = function(e) {
      completed_at <- Sys.time()
      error_message <- describe_automation_error(
        e = e,
        phase_name = phase_name
      )

      record_phase(
        phase_name = phase_name,
        phase_status = "FAILED",
        started_at = started_at,
        completed_at = completed_at,
        error_message = error_message
      )

      message(glue::glue(
        "Failed automation phase: {phase_name}: {error_message}"
      ))

      stop(
        error_message,
        call. = FALSE
      )
    }
  )
}

automation_error <- NULL
publication_gate_results <- data.frame()
gold_publication_results <- data.frame()
silver_transform_summary <- NULL
gold_transform_summary <- NULL
achievement_notification_summary <- NULL

get_latest_silver_transform_summary <- function() {
  connection <- get_connection("cycling_platform_admin")

  tryCatch(
    {
      latest_runs <- DBI::dbGetQuery(
        conn = connection,
        statement = "
          WITH ranked AS (
            SELECT
              transform_run_id,
              entity_name,
              run_mode,
              run_status,
              total_batches,
              completed_batches,
              activities_planned,
              activities_completed,
              rows_inserted,
              rows_updated,
              rows_deleted,
              duration_seconds,
              error_message,
              ROW_NUMBER() OVER (
                PARTITION BY entity_name
                ORDER BY transform_run_id DESC
              ) AS entity_recency_rank
            FROM cycling_platform_admin.transform_run
            WHERE layer_name = 'silver'
              AND entity_name IN ('activities', 'activity_streams')
          )
          SELECT
            transform_run_id,
            entity_name,
            run_mode,
            run_status,
            total_batches,
            completed_batches,
            activities_planned,
            activities_completed,
            rows_inserted,
            rows_updated,
            rows_deleted,
            duration_seconds,
            error_message
          FROM ranked
          WHERE entity_recency_rank = 1
          ORDER BY FIELD(entity_name, 'activities', 'activity_streams')
        "
      )

      if (nrow(latest_runs) == 0) {
        return(NULL)
      }

      list(
        lines = purrr::pmap_chr(
          latest_runs[
            c(
              "entity_name",
              "run_status",
              "run_mode",
              "activities_completed",
              "activities_planned",
              "rows_inserted",
              "rows_updated",
              "rows_deleted",
              "completed_batches",
              "total_batches",
              "duration_seconds"
            )
          ],
          \(entity_name,
            run_status,
            run_mode,
            activities_completed,
            activities_planned,
            rows_inserted,
            rows_updated,
            rows_deleted,
            completed_batches,
            total_batches,
            duration_seconds) {
            activity_part <- if (activities_planned > 0) {
              glue::glue(
                " · {activities_completed}/{activities_planned} activities"
              )
            } else {
              ""
            }

            batch_part <- if (total_batches > 0) {
              glue::glue(
                " · batches {completed_batches}/{total_batches}"
              )
            } else {
              ""
            }

            glue::glue(
              "{entity_name}: {run_status} · {toupper(run_mode)}",
              "{activity_part}",
              " · +{rows_inserted} / ~{rows_updated} / -{rows_deleted} rows",
              "{batch_part}",
              " · {format_platform_duration(duration_seconds)}"
            )
          }
        )
      )
    },
    finally = {
      if (DBI::dbIsValid(connection)) {
        DBI::dbDisconnect(connection)
      }
    }
  )
}

get_latest_gold_transform_summary <- function() {
  connection <- get_connection("cycling_platform_admin")

  tryCatch(
    {
      latest_runs <- DBI::dbGetQuery(
        conn = connection,
        statement = "
          WITH ranked AS (
            SELECT
              transform_run_id,
              entity_name,
              run_mode,
              run_status,
              activities_planned,
              activities_completed,
              rows_inserted,
              rows_updated,
              rows_deleted,
              duration_seconds,
              error_message,
              ROW_NUMBER() OVER (
                PARTITION BY entity_name
                ORDER BY transform_run_id DESC
              ) AS entity_recency_rank
            FROM cycling_platform_admin.transform_run
            WHERE layer_name = 'gold'
              AND entity_name IN (
                'activity_best_efforts',
                'activity_achievements'
              )
          )
          SELECT
            transform_run_id,
            entity_name,
            run_mode,
            run_status,
            activities_planned,
            activities_completed,
            rows_inserted,
            rows_updated,
            rows_deleted,
            duration_seconds,
            error_message
          FROM ranked
          WHERE entity_recency_rank = 1
          ORDER BY FIELD(
            entity_name,
            'activity_best_efforts',
            'activity_achievements'
          )
        "
      )

      if (nrow(latest_runs) == 0) {
        return(NULL)
      }

      failed_batches <- DBI::dbGetQuery(
        conn = connection,
        statement = paste0(
          "
          SELECT
            transform_run_id,
            COUNT(*) AS failed_batch_count
          FROM cycling_platform_admin.transform_run_batch
          WHERE transform_run_id IN (",
          paste(rep("?", nrow(latest_runs)), collapse = ", "),
          ")
            AND batch_status = 'FAILED'
          GROUP BY transform_run_id
          "
        ),
        params = as.list(latest_runs$transform_run_id)
      )

      list(
        lines = purrr::pmap_chr(
          latest_runs[
            c(
              "transform_run_id",
              "entity_name",
              "run_status",
              "run_mode",
              "activities_completed",
              "activities_planned",
              "rows_inserted",
              "rows_deleted",
              "duration_seconds"
            )
          ],
          \(transform_run_id,
            entity_name,
            run_status,
            run_mode,
            activities_completed,
            activities_planned,
            rows_inserted,
            rows_deleted,
            duration_seconds) {
            failed_batch_count <- failed_batches$failed_batch_count[
              failed_batches$transform_run_id == transform_run_id
            ]

            if (length(failed_batch_count) == 0) {
              failed_batch_count <- 0L
            }

            skipped_activities <- max(
              0L,
              as.integer(activities_planned) -
                as.integer(activities_completed)
            )

            glue::glue(
              "{entity_name}: {run_status} · {run_mode} · ",
              "{activities_completed}/{activities_planned} activities · ",
              "+{rows_inserted} / -{rows_deleted} rows · ",
              "skipped {skipped_activities} · ",
              "failed batches {failed_batch_count[[1]]} · ",
              "{format_platform_duration(duration_seconds)}"
            )
          }
        )
      )
    },
    finally = {
      if (DBI::dbIsValid(connection)) {
        DBI::dbDisconnect(connection)
      }
    }
  )
}

tryCatch(
  {
    run_phase(
      "raw_ingestion",
      {
        previous_etl_run_id <- tryCatch(
          get_latest_etl_run_id(),
          error = function(e) {
            message(
              "Unable to snapshot latest ETL run before raw ingestion: ",
              conditionMessage(e)
            )

            NA_integer_
          }
        )

        run_child_rscript(
          script = "platform.R",
          args = c(
            raw_execution_mode,
            "--no-notification"
          ),
          label = "Raw ingestion",
          tail_lines = 30L
        )

        raw_ingestion_summary <<- tryCatch(
          get_raw_ingestion_summary(
            previous_run_id = previous_etl_run_id
          ),
          error = function(e) {
            message(
              "Unable to build raw ingestion notification summary: ",
              conditionMessage(e)
            )

            NULL
          }
        )
      }
    )

    run_phase(
      "silver_transforms",
      {
        connection <- get_connection("cycling_platform_admin")

        tryCatch(
          {
            run_silver_transformations(
              connection = connection,
              config = config,
              stream_rebuild_mode = "repair"
            )
          },
          finally = {
            if (DBI::dbIsValid(connection)) {
              DBI::dbDisconnect(connection)
            }
          }
        )
      }
    )

    silver_transform_summary <<- tryCatch(
      get_latest_silver_transform_summary(),
      error = function(e) {
        message(
          "Unable to build Silver transform notification summary: ",
          conditionMessage(e)
        )

        NULL
      }
    )

    run_phase(
      "silver_publication_checks",
      {
        connection <- get_connection("cycling_platform_admin")

        tryCatch(
          {
            publication_gate_results <<- run_platform_validation(
              connection = connection,
              config = config,
              include_gold = FALSE,
              validation_scope = "publication",
              run_mode = "automated_publication_gate",
              per_check_timeout_seconds =
                config$validation$publication_gate_per_check_timeout_seconds,
              overall_timeout_seconds =
                config$validation$publication_gate_overall_timeout_seconds
            )

            print_platform_completeness_validation(
              publication_gate_results
            )
          },
          finally = {
            if (DBI::dbIsValid(connection)) {
              DBI::dbDisconnect(connection)
            }
          }
        )
      }
    )

    run_phase(
      "gold_transforms",
      {
        connection <- get_connection("cycling_platform_admin")

        tryCatch(
          {
            run_gold_transformations(
              connection = connection,
              config = config,
              mode = "daily"
            )
          },
          finally = {
            if (DBI::dbIsValid(connection)) {
              DBI::dbDisconnect(connection)
            }
          }
        )

        gold_transform_summary <<- tryCatch(
          get_latest_gold_transform_summary(),
          error = function(e) {
            message(
              "Unable to build Gold transform notification summary: ",
              conditionMessage(e)
            )

            NULL
          }
        )
      }
    )

    run_phase(
      "gold_publication_checks",
      {
        connection <- get_connection("cycling_platform_admin")

        tryCatch(
          {
            gold_publication_results <<-
              gold_publication_checks(
                connection = connection,
                config = config,
                check_scope = "gold_publication",
                per_check_timeout_seconds =
                  config$validation$publication_gate_per_check_timeout_seconds,
                deadline = validation_deadline(
                  overall_timeout_seconds =
                    config$validation$publication_gate_overall_timeout_seconds
                )
              )

            print_platform_completeness_validation(
              gold_publication_results
            )

            if (
              platform_validation_has_critical_failures(
                gold_publication_results
              )
            ) {
              failed_checks <- gold_publication_results[
                gold_publication_results$severity == "CRITICAL" &
                  !gold_publication_results$passed,
                ,
                drop = FALSE
              ]

              if (nrow(failed_checks) == 0) {
                stop(
                  "Gold publication checks failed, but no failed critical ",
                  "check rows were returned. Inspect the Gold publication ",
                  "validation output and admin.validation_run_check.",
                  call. = FALSE
                )
              }

              stop(
                "Gold publication checks failed: ",
                paste(
                  paste0(
                    failed_checks$check_name,
                    "=",
                    failed_checks$issue_count
                  ),
                  collapse = "; "
                ),
                call. = FALSE
              )
            }
          },
          finally = {
            if (DBI::dbIsValid(connection)) {
              DBI::dbDisconnect(connection)
            }
          }
        )
      }
    )

    run_phase(
      "achievement_notifications",
      {
        connection <- get_connection("cycling_platform_admin")

        tryCatch(
          {
            execute_sql_file(
              sql_file = file.path(
                "sql",
                "admin",
                "060_create_notification_outbox.sql"
              ),
              connection = connection
            )

            queue_result <- queue_activity_achievement_notifications(
              connection = connection,
              config = config
            )

            delivery_result <- deliver_due_notifications(
              connection = connection,
              config = config
            )

            achievement_notification_summary <<- list(
              lines = c(
                glue::glue(
                  "queued {queue_result$queued} · skipped {queue_result$skipped}"
                ),
                glue::glue(
                  "attempted {delivery_result$attempted} · ",
                  "sent {delivery_result$sent} · ",
                  "failed {delivery_result$failed} · ",
                  "retry {delivery_result$retry}"
                )
              )
            )

            if (delivery_result$failed > 0) {
              stop(
                "Achievement notification delivery failed for ",
                delivery_result$failed,
                " notification(s). Retry state recorded in ",
                "admin.notification_outbox.",
                call. = FALSE
              )
            }
          },
          finally = {
            if (DBI::dbIsValid(connection)) {
              DBI::dbDisconnect(connection)
            }
          }
        )
      }
    )

    deep_validation_started_at <- Sys.time()

    record_phase(
      phase_name = "deep_validation",
      phase_status = "NOT_RUN",
      started_at = deep_validation_started_at,
      completed_at = deep_validation_started_at,
      error_message = "Run separately with Rscript run_platform_validation.R"
    )
  },
  error = function(e) {
    automation_error <<- e
  }
)

run_status <- if (is.null(automation_error)) {
  "SUCCESS"
} else {
  "FAILED"
}

notification_started_at <- Sys.time()

tryCatch(
  {
    notification_sent <- send_platform_automation_notification(
      config = config,
      run_status = run_status,
      phase_results = phase_results,
      raw_ingestion_summary = raw_ingestion_summary,
      silver_transform_summary = silver_transform_summary,
      gold_transform_summary = gold_transform_summary,
      achievement_notification_summary = achievement_notification_summary,
      error_message = if (is.null(automation_error)) {
        NULL
      } else {
        condition_message_safe(automation_error)
      }
    )

    record_phase(
      phase_name = "notification",
      phase_status = if (isTRUE(notification_sent)) "SUCCESS" else "SKIPPED",
      started_at = notification_started_at,
      completed_at = Sys.time()
    )
  },
  error = function(e) {
    record_phase(
      phase_name = "notification",
      phase_status = "FAILED",
      started_at = notification_started_at,
      completed_at = Sys.time(),
      error_message = conditionMessage(e)
    )

    message(
      "Automation notification phase failed: ",
      conditionMessage(e)
    )
  }
)

message("Platform automation phase summary:")
print(phase_results)

if (nrow(publication_gate_results) > 0) {
  message("Platform automation Silver publication checks:")
  print(
    publication_gate_results[
      c(
        "check_name",
        "check_scope",
        "severity",
        "passed",
        "issue_count",
        "elapsed_seconds"
      )
    ]
  )
}

if (nrow(gold_publication_results) > 0) {
  message("Platform automation Gold publication checks:")
  print(
    gold_publication_results[
      c(
        "check_name",
        "check_scope",
        "severity",
        "passed",
        "issue_count",
        "elapsed_seconds"
      )
    ]
  )
}

if (!is.null(automation_error)) {
  stop(
    condition_message_safe(automation_error),
    call. = FALSE
  )
}

message("Platform automation complete.")
