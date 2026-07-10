# run_daily_platform.R
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

raw_execution_mode <- "manual"

if (length(args) > 0) {
  raw_execution_mode <- tolower(args[[1]])
}

if (!raw_execution_mode %in% c("manual", "streams_only")) {
  stop(
    "Unknown automation raw mode. Use 'manual' or 'streams_only'. ",
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

tryCatch(
  {
    run_phase(
      "raw_ingestion",
      {
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
      "publication_gate",
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
  message("Platform automation publication-gate checks:")
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

if (!is.null(automation_error)) {
  stop(automation_error)
}

message("Platform automation complete.")
