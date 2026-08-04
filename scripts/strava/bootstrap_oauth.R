#!/usr/bin/env Rscript

source(
  file.path(
    "R",
    "admin",
    "update_renviron.R"
  )
)

source(
  file.path(
    "R",
    "api",
    "bootstrap_strava_oauth.R"
  )
)

tryCatch(
  {
    bootstrap_strava_oauth()
  },
  error = function(error) {
    message(
      "Strava OAuth bootstrap failed: ",
      conditionMessage(error)
    )
    quit(
      status = 1L,
      save = "no"
    )
  }
)
