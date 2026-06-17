update_renviron <- function(
  key,
  value,
  renviron_path = ".Renviron"
) {
  lines <- readLines(
    renviron_path,
    warn = FALSE
  )

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

  invisible(NULL)
}
