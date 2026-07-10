testthat::test_that("update_renviron writes token and updates process env", {
  update_renviron_file <- file.path(
    "R",
    "admin",
    "update_renviron.R"
  )

  if (!file.exists(update_renviron_file)) {
    update_renviron_file <- file.path(
      "..",
      "..",
      "R",
      "admin",
      "update_renviron.R"
    )
  }

  source(update_renviron_file)

  old_value <- Sys.getenv(
    "GOOGLE_HEALTH_REFRESH_TOKEN",
    unset = NA_character_
  )

  on.exit(
    {
      if (is.na(old_value)) {
        Sys.unsetenv("GOOGLE_HEALTH_REFRESH_TOKEN")
      } else {
        Sys.setenv(GOOGLE_HEALTH_REFRESH_TOKEN = old_value)
      }
    },
    add = TRUE
  )

  renviron_file <- tempfile()

  writeLines(
    "GOOGLE_HEALTH_REFRESH_TOKEN=old",
    renviron_file
  )

  update_renviron(
    key = "GOOGLE_HEALTH_REFRESH_TOKEN",
    value = "new",
    renviron_path = renviron_file
  )

  testthat::expect_true(
    any(
      readLines(renviron_file) == "GOOGLE_HEALTH_REFRESH_TOKEN=new"
    )
  )

  testthat::expect_equal(
    Sys.getenv("GOOGLE_HEALTH_REFRESH_TOKEN"),
    "new"
  )
})

testthat::test_that("Google Health token diagnostics do not expose full token", {
  update_renviron_file <- file.path(
    "R",
    "admin",
    "update_renviron.R"
  )

  google_auth_file <- file.path(
    "R",
    "api",
    "get_google_health_access_token.R"
  )

  if (!file.exists(update_renviron_file)) {
    update_renviron_file <- file.path(
      "..",
      "..",
      "R",
      "admin",
      "update_renviron.R"
    )
  }

  if (!file.exists(google_auth_file)) {
    google_auth_file <- file.path(
      "..",
      "..",
      "R",
      "api",
      "get_google_health_access_token.R"
    )
  }

  source(update_renviron_file)
  source(google_auth_file)

  old_values <- Sys.getenv(
    c(
      "GOOGLE_HEALTH_CLIENT_ID",
      "GOOGLE_HEALTH_CLIENT_SECRET",
      "GOOGLE_HEALTH_REFRESH_TOKEN"
    ),
    unset = NA_character_
  )

  on.exit(
    {
      for (key in names(old_values)) {
        if (is.na(old_values[[key]])) {
          Sys.unsetenv(key)
        } else {
          do.call(
            Sys.setenv,
            as.list(
              stats::setNames(
                old_values[[key]],
                key
              )
            )
          )
        }
      }
    },
    add = TRUE
  )

  Sys.setenv(
    GOOGLE_HEALTH_CLIENT_ID = "client",
    GOOGLE_HEALTH_CLIENT_SECRET = "secret",
    GOOGLE_HEALTH_REFRESH_TOKEN = "1//refresh-token-value"
  )

  diagnostics <- google_health_token_diagnostics(
    renviron_path = tempfile()
  )

  testthat::expect_true(
    diagnostics$refresh_token_present[[1]]
  )

  testthat::expect_equal(
    diagnostics$refresh_token_prefix[[1]],
    "1//r"
  )

  testthat::expect_false(
    "1//refresh-token-value" %in% unlist(diagnostics)
  )
})
