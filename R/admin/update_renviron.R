find_project_renviron <- function(start_path = getwd()) {
  configured_renviron <- Sys.getenv(
    "CYCLING_PLATFORM_RENVIRON_PATH"
  )

  if (nzchar(configured_renviron)) {
    return(
      normalizePath(
        configured_renviron,
        winslash = "/",
        mustWork = FALSE
      )
    )
  }

  renviron_user <- Sys.getenv(
    "R_ENVIRON_USER"
  )

  if (nzchar(renviron_user)) {
    return(
      normalizePath(
        renviron_user,
        winslash = "/",
        mustWork = FALSE
      )
    )
  }

  current_path <- normalizePath(
    start_path,
    winslash = "/",
    mustWork = TRUE
  )

  repeat {
    candidate <- file.path(
      current_path,
      ".Renviron"
    )

    if (file.exists(candidate)) {
      return(candidate)
    }

    parent_path <- dirname(current_path)

    if (identical(parent_path, current_path)) {
      return(
        file.path(
          normalizePath(
            start_path,
            winslash = "/",
            mustWork = TRUE
          ),
          ".Renviron"
        )
      )
    }

    current_path <- parent_path
  }
}

update_renviron <- function(
  key,
  value,
  renviron_path = find_project_renviron()
) {
  lines <- if (file.exists(renviron_path)) {
    readLines(
      renviron_path,
      warn = FALSE
    )
  } else {
    character()
  }

  pattern <- paste0("^", key, "=")

  replacement <- paste0(
    key,
    "=",
    value
  )

  if (any(grepl(pattern, lines))) {
    lines <- sub(
      pattern = paste0("^", key, "=.*$"),
      replacement = replacement,
      x = lines
    )
  } else {
    lines <- c(lines, replacement)
  }

  writeLines(
    lines,
    renviron_path
  )

  do.call(
    Sys.setenv,
    as.list(
      stats::setNames(
        value,
        key
      )
    )
  )

  invisible(NULL)
}
