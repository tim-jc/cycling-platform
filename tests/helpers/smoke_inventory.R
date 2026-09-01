smoke_r_file_exclusions <- character()

discover_smoke_r_files <- function(root = ".") {
  root_files <- list.files(
    root,
    pattern = "[.][Rr]$",
    recursive = FALSE,
    full.names = TRUE
  )
  owned_directories <- file.path(root, c("R", "scripts"))
  owned_files <- unlist(
    lapply(
      owned_directories[dir.exists(owned_directories)],
      list.files,
      pattern = "[.][Rr]$",
      recursive = TRUE,
      full.names = TRUE
    ),
    use.names = FALSE
  )
  files <- sort(unique(c(root_files, owned_files)))
  relative_files <- sub(
    paste0("^", normalizePath(root, mustWork = TRUE), "/?"),
    "",
    normalizePath(files, mustWork = TRUE)
  )

  sub("^[.]/", "", files[!relative_files %in% smoke_r_file_exclusions])
}
