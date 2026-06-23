#' Send Notification
#'
#' Send a best-effort ntfy heartbeat for a platform run.
#'
#' @param run_id Integer ETL run identifier.
#' @param config Platform configuration.
#'
#' @return Invisibly returns TRUE when a notification was sent, otherwise FALSE.
send_notification <- function(
  run_id,
  config
) {
  notifications <- config$notifications

  if (is.null(notifications$enabled) || !isTRUE(notifications$enabled)) {
    return(invisible(FALSE))
  }

  if (!identical(notifications$provider, "ntfy")) {
    message(
      "Notification provider is not supported: ",
      notifications$provider
    )

    return(invisible(FALSE))
  }

  topic <- notifications$topic

  if (is.null(topic) || !nzchar(topic)) {
    message("Notification topic is not configured.")

    return(invisible(FALSE))
  }

  base_url <- notifications$base_url

  if (is.null(base_url) || !nzchar(base_url)) {
    base_url <- "https://ntfy.sh"
  }

  notification_result <- tryCatch(
    {
      connection <- get_connection(
        database_name = "cycling_platform_raw"
      )

      on.exit(
        {
          if (DBI::dbIsValid(connection)) {
            DBI::dbDisconnect(connection)
          }
        },
        add = TRUE
      )

      run <- DBI::dbGetQuery(
        conn = connection,
        statement = "
          SELECT
            run_id,
            run_mode,
            run_status,
            started_at,
            completed_at,
            duration_seconds,
            error_message
          FROM cycling_platform_admin.etl_run
          WHERE run_id = ?
        ",
        params = list(run_id)
      )

      if (nrow(run) != 1) {
        stop(
          "Could not find ETL run ",
          run_id,
          call. = FALSE
        )
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
        params = list(run_id)
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
            ) AS details_remaining
          FROM cycling_platform_raw.activities
        "
      )

      format_duration <- function(seconds) {
        if (is.na(seconds)) {
          return("unknown duration")
        }

        minutes <- seconds %/% 60
        remaining_seconds <- seconds %% 60

        paste0(
          minutes,
          "m ",
          remaining_seconds,
          "s"
        )
      }

      format_entity <- function(entity_name, rows_inserted, rows_updated) {
        paste0(
          entity_name,
          ": +",
          rows_inserted,
          " / ~",
          rows_updated
        )
      }

      entity_lines <- character()

      if (nrow(entity_summary) > 0) {
        entity_lines <- purrr::pmap_chr(
          entity_summary[
            c(
              "entity_name",
              "rows_inserted",
              "rows_updated"
            )
          ],
          format_entity
        )
      }

      no_raw_changes <- nrow(entity_summary) > 0 &&
        all(entity_summary$rows_inserted == 0) &&
        all(entity_summary$rows_updated == 0)

      pending_line <- glue::glue(
        "Pending: streams {pending_summary$streams_remaining[[1]]} · ",
        "details {pending_summary$details_remaining[[1]]}"
      )

      body_lines <- c(
        glue::glue(
          "Run {run$run_id[[1]]} · {run$run_mode[[1]]} · ",
          "{format_duration(run$duration_seconds[[1]])}"
        ),
        ""
      )

      if (no_raw_changes) {
        body_lines <- c(
          body_lines,
          "No new raw data."
        )
      } else {
        body_lines <- c(
          body_lines,
          entity_lines
        )
      }

      body_lines <- c(
        body_lines,
        "",
        pending_line
      )

      if (identical(run$run_status[[1]], "FAILED")) {
        failed_entities <- entity_summary[
          entity_summary$entity_status == "FAILED",
          ,
          drop = FALSE
        ]

        failed_entity_line <- "Failed entity: unknown"

        if (nrow(failed_entities) > 0) {
          failed_entity_line <- paste0(
            "Failed entity: ",
            failed_entities$entity_name[[nrow(failed_entities)]]
          )
        }

        error_message <- run$error_message[[1]]

        if (is.na(error_message) || !nzchar(error_message)) {
          error_message <- "No error message recorded."
        }

        error_message <- substr(
          error_message,
          1,
          500
        )

        body_lines <- c(
          body_lines,
          "",
          failed_entity_line,
          paste0(
            "Error: ",
            error_message
          )
        )
      }

      title <- glue::glue(
        "cycling-platform {run$run_status[[1]]}"
      )

      priority <- if (identical(run$run_status[[1]], "FAILED")) {
        "high"
      } else {
        "default"
      }

      tags <- if (identical(run$run_status[[1]], "FAILED")) {
        "warning"
      } else {
        "white_check_mark"
      }

      httr2::request(
        paste0(
          sub(
            "/$",
            "",
            base_url
          ),
          "/",
          topic
        )
      ) |>
        httr2::req_headers(
          Title = title,
          Priority = priority,
          Tags = tags
        ) |>
        httr2::req_body_raw(
          body = charToRaw(
            paste(
              body_lines,
              collapse = "\n"
            )
          ),
          type = "text/plain"
        ) |>
        httr2::req_perform()

      TRUE
    },
    error = function(e) {
      message(
        "Notification failed: ",
        conditionMessage(e)
      )

      FALSE
    }
  )

  invisible(notification_result)
}
