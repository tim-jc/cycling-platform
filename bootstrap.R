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
