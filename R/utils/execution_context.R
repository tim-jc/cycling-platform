#' Determine the Current Execution Host
#'
#' Prefer an explicitly propagated physical host identity when present. This is
#' needed in Docker, where the operating-system nodename and HOSTNAME normally
#' identify the container rather than its host. Native execution falls back to
#' the operating-system nodename and then HOSTNAME.
#'
#' @param system_info Result shaped like Sys.info().
#' @param hostname_environment HOSTNAME environment value.
#' @param execution_host_environment CYCLING_PLATFORM_EXECUTION_HOST value.
#'
#' @return Non-blank host label.
platform_execution_host <- function(
  system_info = Sys.info(),
  hostname_environment = Sys.getenv("HOSTNAME", unset = ""),
  execution_host_environment = Sys.getenv(
    "CYCLING_PLATFORM_EXECUTION_HOST",
    unset = ""
  )
) {
  if (
    length(execution_host_environment) == 1L &&
      !is.na(execution_host_environment) &&
      nzchar(trimws(execution_host_environment))
  ) {
    return(trimws(execution_host_environment))
  }

  nodename <- unname(system_info[["nodename"]])

  if (
    !is.null(nodename) &&
      length(nodename) == 1L &&
      !is.na(nodename) &&
      nzchar(trimws(nodename))
  ) {
    return(trimws(nodename))
  }

  if (
    length(hostname_environment) == 1L &&
      !is.na(hostname_environment) &&
      nzchar(trimws(hostname_environment))
  ) {
    return(trimws(hostname_environment))
  }

  "unknown"
}

#' Collect Platform Execution Context
#'
#' @param pipeline Stable pipeline or job name.
#' @param status Overall execution or event status.
#' @param duration_seconds Optional elapsed duration.
#' @param host Execution host.
#'
#' @return Named execution-context list.
platform_execution_context <- function(
  pipeline,
  status,
  duration_seconds = NULL,
  host = platform_execution_host()
) {
  list(
    host = as.character(host),
    pipeline = as.character(pipeline),
    status = as.character(status),
    duration_seconds = duration_seconds
  )
}

#' Format Platform Execution Context
#'
#' @param context Result from platform_execution_context().
#'
#' @return Character lines for a notification body.
format_platform_execution_context <- function(context) {
  lines <- c(
    paste0("Host: ", context$host),
    paste0("Pipeline: ", context$pipeline),
    paste0("Status: ", context$status)
  )

  if (
    !is.null(context$duration_seconds) &&
      length(context$duration_seconds) > 0L &&
      !is.na(context$duration_seconds[[1]])
  ) {
    lines <- c(
      lines,
      paste0(
        "Duration: ",
        format_platform_duration(context$duration_seconds[[1]])
      )
    )
  }

  lines
}
