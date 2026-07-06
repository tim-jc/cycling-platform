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

        on.exit(
          {
            if (DBI::dbIsValid(connection)) {
              DBI::dbDisconnect(connection)
            }
          },
          add = TRUE
        )

        run_silver_transformations(
          connection = connection,
          config = config,
          stream_rebuild_mode = "repair"
        )
      }
    )

    run_phase(
      "validation",
      {
        connection <- get_connection("mysql")

        on.exit(
          {
            if (DBI::dbIsValid(connection)) {
              DBI::dbDisconnect(connection)
            }
          },
          add = TRUE
        )

        validation_results <- run_platform_validation(
          connection = connection
        )

        message("Platform validation results:")
        print(validation_results)
      }
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

if (!is.null(automation_error)) {
  stop(automation_error)
}

message("Platform automation complete.")
