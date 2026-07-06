#' Send Platform Automation Notification
#'
#' Send a best-effort ntfy notification for the end-to-end automation wrapper.
#'
#' @param config Platform configuration.
#' @param run_status Overall automation status.
#' @param phase_results Data frame of phase timings and statuses.
#' @param error_message Optional error message.
#'
#' @return Invisibly returns TRUE when a notification was sent, otherwise FALSE.
send_platform_automation_notification <- function(
  config,
  run_status,
  phase_results,
  error_message = NULL
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

  format_phase <- function(phase_name, phase_status, duration_seconds) {
    paste0(
      phase_name,
      ": ",
      phase_status,
      " (",
      round(duration_seconds, 1),
      "s)"
    )
  }

  phase_lines <- purrr::pmap_chr(
    phase_results[
      c(
        "phase_name",
        "phase_status",
        "duration_seconds"
      )
    ],
    format_phase
  )

  body_lines <- c(
    paste0(
      "Status: ",
      run_status
    ),
    "",
    phase_lines
  )

  if (!is.null(error_message) && nzchar(error_message)) {
    body_lines <- c(
      body_lines,
      "",
      paste0(
        "Error: ",
        substr(
          error_message,
          1,
          500
        )
      )
    )
  }

  notification_result <- tryCatch(
    {
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
          Title = paste0(
            "cycling-platform automation ",
            run_status
          ),
          Priority = if (identical(run_status, "FAILED")) "high" else "default",
          Tags = if (identical(run_status, "FAILED")) "warning" else "white_check_mark"
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
        "Automation notification failed: ",
        conditionMessage(e)
      )

      FALSE
    }
  )

  invisible(notification_result)
}
