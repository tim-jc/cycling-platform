#' Format Platform Duration
#'
#' @param seconds Duration in seconds.
#'
#' @return Character duration suitable for concise notifications.
format_platform_duration <- function(seconds) {
  if (
    is.null(seconds) ||
      length(seconds) == 0 ||
      is.na(seconds)
  ) {
    return("unknown")
  }

  seconds <- round(as.numeric(seconds))

  if (seconds < 60) {
    return(paste0(seconds, "s"))
  }

  minutes <- seconds %/% 60
  remaining_seconds <- seconds %% 60

  if (minutes < 60) {
    return(paste0(
      minutes,
      "m ",
      remaining_seconds,
      "s"
    ))
  }

  hours <- minutes %/% 60
  remaining_minutes <- minutes %% 60

  paste0(
    hours,
    "h ",
    remaining_minutes,
    "m ",
    remaining_seconds,
    "s"
  )
}

#' Format Platform Notification Title
#'
#' @param component Platform component name, such as raw or automation.
#' @param status Run status.
#'
#' @return Character notification title.
format_platform_notification_title <- function(component, status) {
  paste(
    "cycling-platform",
    component,
    status
  )
}

#' Format Platform Notification Status Line
#'
#' @param name Entity or phase name.
#' @param status Status value.
#' @param duration_seconds Optional duration in seconds.
#'
#' @return Character notification line.
format_platform_notification_status_line <- function(
  name,
  status,
  duration_seconds = NULL
) {
  line <- paste0(
    name,
    ": ",
    status
  )

  if (!is.null(duration_seconds)) {
    line <- paste0(
      line,
      " · ",
      format_platform_duration(duration_seconds)
    )
  }

  line
}
