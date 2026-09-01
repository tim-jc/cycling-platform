smoke_inventory_file <- file.path("tests", "helpers", "smoke_inventory.R")
if (!file.exists(smoke_inventory_file)) {
  smoke_inventory_file <- file.path("..", "..", smoke_inventory_file)
}
source(smoke_inventory_file)

testthat::test_that("smoke syntax inventory discovers supported R scripts", {
  root <- tempfile("smoke-inventory-")
  dir.create(file.path(root, "R", "nested"), recursive = TRUE)
  dir.create(file.path(root, "scripts", "nested"), recursive = TRUE)
  dir.create(file.path(root, "exploration"), recursive = TRUE)
  dir.create(file.path(root, "tests"), recursive = TRUE)

  expected <- file.path(
    root,
    c("run_job.R", "R/nested/helper.R", "scripts/nested/new_job.R")
  )
  excluded <- file.path(
    root,
    c("exploration/notebook.R", "tests/test-job.R")
  )
  invisible(vapply(c(expected, excluded), file.create, logical(1)))

  discovered <- discover_smoke_r_files(root)

  testthat::expect_setequal(
    basename(discovered),
    c("run_job.R", "helper.R", "new_job.R")
  )
  testthat::expect_false(any(basename(excluded) %in% basename(discovered)))
})

testthat::test_that("root executable allowlist remains an independent guard", {
  smoke_file <- file.path("tests", "smoke_check.R")
  if (!file.exists(smoke_file)) smoke_file <- file.path("..", "..", smoke_file)
  text <- paste(readLines(smoke_file, warn = FALSE), collapse = "\n")

  testthat::expect_match(text, "expected_root_r_files", fixed = TRUE)
  testthat::expect_match(
    text,
    "Unexpected root-level R entry points",
    fixed = TRUE
  )
})
