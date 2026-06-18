source_files <- list.files(
  path = "R",
  pattern = "\\.[Rr]$",
  recursive = TRUE,
  full.names = TRUE
) |>
  sort()

purrr::walk(
  source_files,
  ~ {
    message("Sourcing: ", .x)
    source(.x)
  }
)
