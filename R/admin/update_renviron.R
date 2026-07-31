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
  if (
    length(key) != 1L ||
      is.na(key) ||
      !grepl("^[A-Z][A-Z0-9_]*$", key)
  ) {
    stop("Invalid runtime credential key.", call. = FALSE)
  }

  if (length(value) != 1L || is.na(value) || !nzchar(value)) {
    stop(
      "Refusing to persist a missing or blank runtime credential value.",
      call. = FALSE
    )
  }

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

  renviron_directory <- dirname(renviron_path)

  if (!dir.exists(renviron_directory)) {
    stop(
      "Runtime credential directory does not exist: ",
      renviron_directory,
      call. = FALSE
    )
  }

  existing_mode <- if (file.exists(renviron_path)) {
    file.info(renviron_path)$mode[[1]]
  } else {
    "600"
  }
  temporary_path <- tempfile(
    pattern = ".runtime-renviron-",
    tmpdir = renviron_directory
  )

  on.exit(
    {
      if (file.exists(temporary_path)) {
        unlink(temporary_path)
      }
    },
    add = TRUE
  )

  writeLines(lines, temporary_path)
  Sys.chmod(temporary_path, mode = existing_mode)

  if (!file.rename(temporary_path, renviron_path)) {
    stop(
      "Failed to atomically replace the persistent runtime credential file.",
      call. = FALSE
    )
  }

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
