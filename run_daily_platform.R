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

if (!raw_execution_mode %in% c("scheduled", "manual", "hygiene", "activity_backfill", "streams_only")) {
  stop(
    "Unknown automation raw mode. Use 'scheduled', 'manual', 'hygiene', 'activity_backfill', or 'streams_only'. ",
    "General backfill is intentionally excluded from unattended automation.",
    call. = FALSE
  )
}

automation_lock_connection <- get_connection("cycling_platform_admin")
acquire_platform_run_lock(automation_lock_connection, raw_execution_mode)
Sys.setenv(CYCLING_PLATFORM_PARENT_LOCK = "1")

phase_results <- data.frame(
  phase_name = character(),
  phase_status = character(),
  started_at = as.POSIXct(character()),
  completed_at = as.POSIXct(character()),
  duration_seconds = numeric(),
  error_message = character()
)

raw_ingestion_summary <- NULL
gold_change_context <- unavailable_gold_change_context(
  "Daily Silver phase has not produced change context."
)

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

      reconciliation <- DBI::dbGetQuery(
        connection,
        "SELECT reconciliation_status, child_status,
                SUM(details_repair_required) AS details_repair_required,
                SUM(streams_repair_required) AS streams_repair_required,
                SUM(laps_repair_required) AS laps_repair_required,
                COUNT(*) AS activity_count
           FROM cycling_platform_admin.activity_reconciliation
          WHERE run_id = ?
          GROUP BY reconciliation_status, child_status",
        params = list(run$run_id[[1]])
      )
      affected <- DBI::dbGetQuery(
        connection,
        "SELECT DISTINCT activity_id
           FROM cycling_platform_admin.activity_reconciliation
          WHERE run_id = ?
            AND (reconciliation_status IN ('NEW','CHANGED')
                 OR child_status IN ('INCOMPLETE','FAILED'))",
        params = list(run$run_id[[1]])
      )
      reconciliation <- normalise_activity_reconciliation_counts(reconciliation)
      reconciliation_lines <- if (nrow(reconciliation)) {
        totals <- stats::setNames(rep(0L, 4L), c("NEW", "CHANGED", "UNCHANGED", "MISSING"))
        grouped <- stats::aggregate(activity_count ~ reconciliation_status, reconciliation, sum)
        totals[grouped$reconciliation_status] <- grouped$activity_count
        c(
          glue::glue("Reconciliation: examined {sum(reconciliation$activity_count[reconciliation$reconciliation_status != 'MISSING'])} · new/recovered {totals[['NEW']]} · changed {totals[['CHANGED']]} · unchanged {totals[['UNCHANGED']]} · missing from source {totals[['MISSING']]}"),
          glue::glue("Selective repairs requested: details {sum(reconciliation$details_repair_required)} · streams {sum(reconciliation$streams_repair_required)} · laps {sum(reconciliation$laps_repair_required)}")
        )
      } else character()

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
        reconciliation_lines = reconciliation_lines,
        affected_activity_ids = affected$activity_id,
        run_id = run$run_id[[1]],
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
backup_health_summary <- NULL

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
              (
                SELECT COUNT(*)
                FROM cycling_platform_admin.transform_run_batch failed_batch
                WHERE failed_batch.transform_run_id = tr.transform_run_id
                  AND failed_batch.batch_status = 'FAILED'
              ) AS failed_batches,
              error_message,
              ROW_NUMBER() OVER (
                PARTITION BY entity_name
                ORDER BY transform_run_id DESC
              ) AS entity_recency_rank
            FROM cycling_platform_admin.transform_run tr
            WHERE layer_name = 'silver'
              AND entity_name IN ('activities', 'gear', 'activity_streams', 'activity_laps')
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
            failed_batches,
            error_message
          FROM ranked
          WHERE entity_recency_rank = 1
          ORDER BY FIELD(entity_name, 'activities', 'gear', 'activity_streams', 'activity_laps')
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
              "duration_seconds",
              "failed_batches"
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
            duration_seconds,
            failed_batches) {
            activity_part <- if (identical(entity_name, "gear")) {
              glue::glue(" · {rows_inserted} gear records")
            } else {
              glue::glue(
                " · {activities_completed}/{activities_planned} activities"
              )
            }

            batch_part <- if (total_batches > 0) {
              glue::glue(
                " · batches {completed_batches}/{total_batches}"
              )
            } else {
              ""
            }

            throughput_part <- if (
              identical(entity_name, "activity_streams") &&
                !is.na(duration_seconds) && duration_seconds > 0
            ) {
              glue::glue(
                " · {round(rows_inserted / duration_seconds, 1)} rows/s",
                " · failed {failed_batches}"
              )
            } else {
              ""
            }

            glue::glue(
              "{entity_name}: {run_status} · {toupper(run_mode)}",
              "{activity_part}",
              " · +{rows_inserted} / ~{rows_updated} / -{rows_deleted} rows",
              "{batch_part}",
              "{throughput_part}",
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

get_latest_gold_transform_summary <- function(
  transform_timings = NULL,
  orchestration_timing = NULL
) {
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

            format_gold_transform_summary_line(
              entity_name = entity_name,
              run_status = run_status,
              run_mode = run_mode,
              activities_completed = activities_completed,
              activities_planned = activities_planned,
              rows_inserted = rows_inserted,
              rows_deleted = rows_deleted,
              failed_batch_count = failed_batch_count[[1]],
              timing = transform_timings[[entity_name]],
              recorded_duration_seconds = duration_seconds
            )
          }
        ),
        orchestration_lines = if (is.null(orchestration_timing)) {
          character()
        } else {
          paste0(
            "Gold orchestration: connection setup/teardown ",
            format_platform_duration(
              orchestration_timing$connection_seconds
            ),
            " · summary/finalisation ",
            format_platform_duration(
              orchestration_timing$summary_finalisation_seconds
            )
          )
        }
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
          script = "run_raw_ingestion.R",
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
            gold_change_context <<- run_silver_transformations(
              connection = connection,
              config = config,
              stream_rebuild_mode = "repair",
              activity_ids = if (!is.null(raw_ingestion_summary)) raw_ingestion_summary$affected_activity_ids else NULL,
              raw_run_id = if (!is.null(raw_ingestion_summary)) raw_ingestion_summary$run_id else NA_integer_
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
        gold_connection_started_at <- gold_timing_now()
        connection <- get_connection("cycling_platform_admin")
        gold_connection_seconds <- gold_elapsed_seconds(
          gold_connection_started_at
        )
        gold_disconnect_seconds <- 0

        tryCatch(
          {
            gold_transform_timings <- run_gold_transformations(
              connection = connection,
              config = config,
              gold_change_context = gold_change_context,
              mode = "daily"
            )
          },
          finally = {
            if (DBI::dbIsValid(connection)) {
              gold_disconnect_started_at <- gold_timing_now()
              DBI::dbDisconnect(connection)
              gold_disconnect_seconds <- gold_elapsed_seconds(
                gold_disconnect_started_at
              )
            }
          }
        )

        gold_summary_started_at <- gold_timing_now()
        gold_transform_summary <<- tryCatch(
          get_latest_gold_transform_summary(
            transform_timings = gold_transform_timings,
            orchestration_timing = list(
              connection_seconds = gold_connection_seconds +
                gold_disconnect_seconds,
              summary_finalisation_seconds = 0
            )
          ),
          error = function(e) {
            message(
              "Unable to build Gold transform notification summary: ",
              conditionMessage(e)
            )

            NULL
          }
        )

        gold_summary_finalisation_seconds <- gold_elapsed_seconds(
          gold_summary_started_at
        )

        if (!is.null(gold_transform_summary)) {
          gold_transform_summary$orchestration_lines <- paste0(
            "Gold orchestration: connection setup/teardown ",
            format_platform_duration(
              gold_connection_seconds + gold_disconnect_seconds
            ),
            " · summary/finalisation ",
            format_platform_duration(gold_summary_finalisation_seconds)
          )
        }
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

    if (raw_execution_mode == "activity_backfill") {
      now <- Sys.time()
      record_phase("achievement_notifications", "SKIPPED", now, now, "Historical achievement notifications suppressed by default.")
      achievement_notification_summary <<- list(lines = "suppressed for annual historical backfill ✓")
    } else run_phase(
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
                format_activity_achievement_queue_summary(queue_result),
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

if (isTRUE(
  is.null(silver_transform_summary) &&
    any(
      phase_results$phase_name == "silver_transforms" &
        phase_results$phase_status == "FAILED"
    )
)) {
  silver_transform_summary <- tryCatch(
    get_latest_silver_transform_summary(),
    error = function(e) NULL
  )
}

backup_health_summary <- tryCatch(
  {
    connection <- get_connection("cycling_platform_admin")

    tryCatch(
      backup_health_notification_summary(
        connection = connection,
        config = config
      ),
      finally = {
        if (DBI::dbIsValid(connection)) {
          DBI::dbDisconnect(connection)
        }
      }
    )
  },
  error = function(e) {
    list(
      lines = paste0(
        "Backup observability: unavailable ⚠ — ",
        substr(conditionMessage(e), 1, 160)
      )
    )
  }
)

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
      backup_health_summary = backup_health_summary,
      pipeline = switch(raw_execution_mode, hygiene = "activity-hygiene", activity_backfill = "annual-backfill", "daily-platform"),
      component = switch(raw_execution_mode, hygiene = "monthly activity hygiene", activity_backfill = "annual historical backfill", "automation"),
      window_label = switch(raw_execution_mode, hygiene = paste0("previous ", config$ingestion$activity_hygiene_days, " days"), activity_backfill = paste0("configured history (", config$ingestion$activity_backfill_days, " days)"), paste0("previous ", config$ingestion$activity_refresh_days, " days")),
      error_message = if (is.null(automation_error)) {
        NULL
      } else {
        condition_message_safe(automation_error)
      }
    )

    if (identical(run_status, "FAILED") && isTRUE(notification_sent)) {
      message("CYCLING_PLATFORM_FAILURE_NOTIFICATION_SENT")
    }

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

release_platform_run_lock(automation_lock_connection, raw_execution_mode)
DBI::dbDisconnect(automation_lock_connection)
Sys.unsetenv("CYCLING_PLATFORM_PARENT_LOCK")

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
