# run_google_health_auth_check.R
source("bootstrap.R")

auth_error <- NULL
access_token <- NULL

tryCatch(
  {
    access_token <- get_google_health_access_token(
      verbose = TRUE
    )
  },
  error = function(e) {
    auth_error <<- e
  }
)

if (!is.null(auth_error)) {
  stop(auth_error)
}

message(
  "Google Health access token refresh succeeded. Access token prefix: ",
  substr(access_token, 1, 12),
  "..."
)
