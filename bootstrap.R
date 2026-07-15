load_project_renviron <- function(start_path = getwd()) {
  configured_renviron <- Sys.getenv(
    "CYCLING_PLATFORM_RENVIRON_PATH"
  )

  renviron_user <- Sys.getenv(
    "R_ENVIRON_USER"
  )

  candidates <- c(
    configured_renviron,
    renviron_user
  )

  current_path <- normalizePath(
    start_path,
    winslash = "/",
    mustWork = TRUE
  )

  repeat {
    candidates <- c(
      candidates,
      file.path(
        current_path,
        ".Renviron"
      )
    )

    parent_path <- dirname(current_path)

    if (identical(parent_path, current_path)) {
      break
    }

    current_path <- parent_path
  }

  candidates <- candidates[nzchar(candidates)]
  candidates <- unique(
    normalizePath(
      candidates,
      winslash = "/",
      mustWork = FALSE
    )
  )

  for (candidate in candidates) {
    if (file.exists(candidate)) {
      readRenviron(candidate)
      Sys.setenv(
        CYCLING_PLATFORM_RENVIRON_PATH = candidate
      )
      return(invisible(candidate))
    }
  }

  invisible(NA_character_)
}

load_project_renviron()

source_files <- list.files(
  path = "R",
  pattern = "\\.[Rr]$",
  recursive = TRUE,
  full.names = TRUE
) |>
  sort()

purrr::walk(
  source_files,
  \(file) {
    message("Sourcing: ", file)
    source(file, local = .GlobalEnv)
  }
)

# TODO:
# Convert project to an R package once the raw and silver
# layers have stabilised.
