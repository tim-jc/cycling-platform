find_append_project_root <- function() {
  candidates <- c(".", "../..")
  candidate <- candidates[
    file.exists(file.path(candidates, "bootstrap.R"))
  ][1]

  normalizePath(candidate, mustWork = TRUE)
}

source(file.path(
  find_append_project_root(),
  "R",
  "database",
  "append_existing_table.R"
))

testthat::test_that("append helper refuses implicit table creation", {
  writes <- 0L

  testthat::expect_error(
    append_existing_table(
      conn = NULL,
      name = "missing_table",
      value = data.frame(id = 1L),
      table_exists = function(...) FALSE,
      write_table = function(...) {
        writes <<- writes + 1L
      }
    ),
    "Refusing to create a missing persistent table"
  )

  testthat::expect_equal(writes, 0L)
})

testthat::test_that("append helper only permits safe write flags", {
  testthat::expect_error(
    append_existing_table(
      conn = NULL,
      name = "table",
      value = data.frame(id = 1L),
      append = FALSE,
      table_exists = function(...) TRUE,
      write_table = function(...) TRUE
    ),
    "only supports append=TRUE"
  )
  testthat::expect_error(
    append_existing_table(
      conn = NULL,
      name = "table",
      value = data.frame(id = 1L),
      overwrite = TRUE,
      table_exists = function(...) TRUE,
      write_table = function(...) TRUE
    ),
    "overwrite=FALSE"
  )
})

testthat::test_that("append helper writes an existing table", {
  received <- NULL

  result <- append_existing_table(
    conn = "connection",
    name = "existing_table",
    value = data.frame(id = 1L),
    table_exists = function(conn, name) TRUE,
    write_table = function(...) {
      received <<- list(...)
      TRUE
    }
  )

  testthat::expect_true(result)
  testthat::expect_true(received$append)
  testthat::expect_false(received$overwrite)
})
