# run_platform_validation.R
source("bootstrap.R")

config <- load_config()

args <- commandArgs(
  trailingOnly = TRUE
)

include_gold <- !("--silver-only" %in% args)
validation_scope <- "deep"

if ("--publication" %in% args) {
  validation_scope <- "publication"
  include_gold <- FALSE
}

per_check_timeout_seconds <- if (identical(validation_scope, "publication")) {
  config$validation$publication_gate_per_check_timeout_seconds
} else {
  config$validation$deep_per_check_timeout_seconds
}

overall_timeout_seconds <- if (identical(validation_scope, "publication")) {
  config$validation$publication_gate_overall_timeout_seconds
} else {
  config$validation$deep_overall_timeout_seconds
}

connection <- get_connection("cycling_platform_admin")

validation_error <- NULL
validation_results <- NULL

tryCatch(
  {
    validation_results <- run_platform_validation(
      connection = connection,
      config = config,
      include_gold = include_gold,
      validation_scope = validation_scope,
      run_mode = "standalone",
      per_check_timeout_seconds = per_check_timeout_seconds,
      overall_timeout_seconds = overall_timeout_seconds,
      notify = TRUE
    )

    print_platform_completeness_validation(
      validation_results
    )
  },
  error = function(e) {
    validation_error <<- e
  },
  finally = {
    connection_is_valid <- tryCatch(
      DBI::dbIsValid(connection),
      error = function(e) {
        FALSE
      }
    )

    if (isTRUE(connection_is_valid)) {
      DBI::dbDisconnect(connection)
    }
  }
)

if (!is.null(validation_error)) {
  stop(validation_error)
}

validation_outcome <- attr(
  validation_results,
  "validation_outcome"
)

if (is.null(validation_outcome) || !nzchar(validation_outcome)) {
  validation_outcome <- "PASSED"
}

message(
  "Platform validation outcome: ",
  validation_outcome
)
