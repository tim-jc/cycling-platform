find_credential_project_root <- function() {
  candidates <- c(".", "../..")
  candidate <- candidates[
    file.exists(file.path(candidates, "bootstrap.R"))
  ][1]

  normalizePath(candidate, mustWork = TRUE)
}

source(file.path(
  find_credential_project_root(),
  "R",
  "database",
  "get_connection.R"
))
source(file.path(
  find_credential_project_root(),
  "R",
  "api",
  "get_access_token.R"
))

testthat::test_that("MariaDB configuration reports all missing credentials", {
  environment <- c(
    MARIADB_HOST = "db-host",
    MARIADB_PORT = "3306",
    MARIADB_USER = "",
    MARIADB_PASSWORD = ""
  )

  testthat::expect_error(
    load_mariadb_connection_config(environment),
    "MARIADB_USER, MARIADB_PASSWORD",
    fixed = TRUE
  )
})

testthat::test_that("MariaDB configuration validates port without secrets", {
  password <- "do-not-print-this-password"
  environment <- c(
    MARIADB_HOST = "db-host",
    MARIADB_PORT = "not-a-port",
    MARIADB_USER = "platform-user",
    MARIADB_PASSWORD = password
  )

  error <- tryCatch(
    load_mariadb_connection_config(environment),
    error = identity
  )

  testthat::expect_s3_class(error, "error")
  testthat::expect_match(conditionMessage(error), "MARIADB_PORT")
  testthat::expect_false(grepl(password, conditionMessage(error), fixed = TRUE))
})

testthat::test_that("MariaDB configuration returns typed safe fields", {
  config <- load_mariadb_connection_config(c(
    MARIADB_HOST = " db-host ",
    MARIADB_PORT = "3307",
    MARIADB_USER = " platform-user ",
    MARIADB_PASSWORD = "password"
  ))

  testthat::expect_identical(config$host, "db-host")
  testthat::expect_identical(config$port, 3307L)
  testthat::expect_identical(config$user, "platform-user")
})

testthat::test_that("Strava configuration reports missing credentials clearly", {
  testthat::expect_error(
    load_strava_refresh_config(c(
      STRAVA_CLIENT_ID = "client-id",
      STRAVA_CLIENT_SECRET = "",
      STRAVA_REFRESH_TOKEN = ""
    )),
    "STRAVA_CLIENT_SECRET, STRAVA_REFRESH_TOKEN",
    fixed = TRUE
  )
})

testthat::test_that("credential validation never includes supplied secrets", {
  secret <- "do-not-print-client-secret"
  refresh_token <- "do-not-print-refresh-token"

  error <- tryCatch(
    load_strava_refresh_config(c(
      STRAVA_CLIENT_ID = "",
      STRAVA_CLIENT_SECRET = secret,
      STRAVA_REFRESH_TOKEN = refresh_token
    )),
    error = identity
  )

  testthat::expect_s3_class(error, "error")
  testthat::expect_false(grepl(secret, conditionMessage(error), fixed = TRUE))
  testthat::expect_false(
    grepl(refresh_token, conditionMessage(error), fixed = TRUE)
  )
})
