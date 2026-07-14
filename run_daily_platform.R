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
  connection <- get_connection("mysql")

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
  connection <- get_connection("mysql")

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

      record_phase(
        phase_name = phase_name,
        phase_status = "FAILED",
        started_at = started_at,
        completed_at = completed_at,
        error_message = conditionMessage(e)
      )

      message(glue::glue(
        "Failed automation phase: {phase_name}: {conditionMessage(e)}"
      ))

      stop(e)
    }
  )
}

automation_error <- NULL
publication_gate_results <- data.frame()
gold_publication_results <- data.frame()
gold_transform_summary <- NULL

get_latest_gold_activity_best_efforts_summary <- function() {
  connection <- get_connection("mysql")

  tryCatch(
    {
      latest_run <- DBI::dbGetQuery(
        conn = connection,
        statement = "
          SELECT
            transform_run_id,
            run_mode,
            run_status,
            activities_planned,
            activities_completed,
            rows_inserted,
            rows_updated,
            rows_deleted,
            duration_seconds,
            error_message
          FROM cycling_platform_admin.transform_run
          WHERE layer_name = 'gold'
            AND entity_name = 'activity_best_efforts'
          ORDER BY transform_run_id DESC
          LIMIT 1
        "
      )

      if (nrow(latest_run) != 1) {
        return(NULL)
      }

      failed_batches <- DBI::dbGetQuery(
        conn = connection,
        statement = "
          SELECT COUNT(*) AS failed_batch_count
          FROM cycling_platform_admin.transform_run_batch
          WHERE transform_run_id = ?
            AND batch_status = 'FAILED'
        ",
        params = list(latest_run$transform_run_id[[1]])
      )

      skipped_activities <- max(
        0L,
        as.integer(latest_run$activities_planned[[1]]) -
          as.integer(latest_run$activities_completed[[1]])
      )

      list(
        lines = c(
          glue::glue(
            "activity_best_efforts: {latest_run$run_status[[1]]} · ",
            "{latest_run$run_mode[[1]]} · ",
            "{latest_run$activities_completed[[1]]}/",
            "{latest_run$activities_planned[[1]]} activities · ",
            "+{latest_run$rows_inserted[[1]]} / -{latest_run$rows_deleted[[1]]} rows"
          ),
          glue::glue(
            "activity_best_efforts: skipped {skipped_activities} · ",
            "failed batches {failed_batches$failed_batch_count[[1]]} · ",
            "{format_platform_duration(latest_run$duration_seconds[[1]])}"
          )
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

        raw_status <- system2(
          command = file.path(
            R.home("bin"),
            "Rscript"
          ),
          args = c(
            "platform.R",
            raw_execution_mode,
            "--no-notification"
          ),
          stdout = "",
          stderr = ""
        )

        if (!identical(raw_status, 0L)) {
          stop(
            "Raw ingestion failed with exit status ",
            raw_status,
            ".",
            call. = FALSE
          )
        }

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
        connection <- get_connection("mysql")

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

    run_phase(
      "silver_publication_checks",
      {
        connection <- get_connection("mysql")

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
        connection <- get_connection("mysql")

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
          get_latest_gold_activity_best_efforts_summary(),
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
        connection <- get_connection("mysql")

        tryCatch(
          {
            gold_publication_results <<-
              gold_activity_best_efforts_publication_checks(
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
      gold_transform_summary = gold_transform_summary,
      error_message = if (is.null(automation_error)) {
        NULL
      } else {
        conditionMessage(automation_error)
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
  stop(automation_error)
}

message("Platform automation complete.")
