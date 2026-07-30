strava_oauth_source <- function(path) {
  candidate <- file.path("R", path)
  if (!file.exists(candidate)) {
    candidate <- file.path("..", "..", "R", path)
  }
  source(candidate)
}

strava_oauth_source(
  file.path(
    "admin",
    "update_renviron.R"
  )
)
strava_oauth_source(
  file.path(
    "api",
    "bootstrap_strava_oauth.R"
  )
)

with_strava_oauth_environment <- function(code) {
  keys <- c(
    "STRAVA_CLIENT_ID",
    "STRAVA_CLIENT_SECRET",
    "STRAVA_REDIRECT_URI",
    "STRAVA_REFRESH_TOKEN",
    "CYCLING_PLATFORM_RENVIRON_PATH",
    "R_ENVIRON_USER"
  )
  old_values <- Sys.getenv(
    keys,
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
    STRAVA_CLIENT_ID = "12345",
    STRAVA_CLIENT_SECRET = "client-secret",
    STRAVA_REDIRECT_URI = "http://localhost"
  )

  force(code)
}

testthat::test_that("authorization URL requests every required scope", {
  url <- build_strava_authorization_url(
    client_id = "12345",
    redirect_uri = "http://localhost",
    state = "known-state"
  )
  query <- httr2::url_parse(url)$query

  testthat::expect_equal(query$client_id, "12345")
  testthat::expect_equal(query$response_type, "code")
  testthat::expect_equal(query$approval_prompt, "force")
  testthat::expect_equal(query$redirect_uri, "http://localhost")
  testthat::expect_equal(query$state, "known-state")
  testthat::expect_setequal(
    parse_strava_scopes(query$scope),
    strava_required_scopes()
  )
})

testthat::test_that("authorization redirect validates state and scopes", {
  redirect <- paste0(
    "http://localhost/?code=one-time-code",
    "&scope=read%2Cactivity%3Aread_all%2Cprofile%3Aread_all",
    "&state=known-state"
  )

  parsed <- parse_strava_authorization_redirect(
    redirect,
    expected_state = "known-state"
  )

  testthat::expect_equal(parsed$code, "one-time-code")
  testthat::expect_setequal(
    parsed$scopes,
    strava_required_scopes()
  )

  testthat::expect_error(
    parse_strava_authorization_redirect(
      sub("known-state", "wrong-state", redirect),
      expected_state = "known-state"
    ),
    "state validation failed"
  )

  testthat::expect_error(
    parse_strava_authorization_redirect(
      sub(
        "%2Cprofile%3Aread_all",
        "",
        redirect
      ),
      expected_state = "known-state"
    ),
    "Missing: profile:read_all"
  )

  testthat::expect_error(
    parse_strava_authorization_redirect(
      sub("http://localhost", "https://example.com", redirect, fixed = TRUE),
      expected_state = "known-state",
      expected_redirect_uri = "http://localhost"
    ),
    "does not match the configured"
  )

  denied <- paste0(
    "http://localhost/?error=access_denied",
    "&state=known-state"
  )
  testthat::expect_error(
    parse_strava_authorization_redirect(
      denied,
      expected_state = "known-state"
    ),
    "authorization failed: access_denied"
  )

  testthat::expect_error(
    parse_strava_authorization_redirect(
      sub("known-state", "wrong-state", denied, fixed = TRUE),
      expected_state = "known-state"
    ),
    "state validation failed"
  )
})

testthat::test_that("authorization code exchange uses the OAuth code grant", {
  request <- build_strava_authorization_code_request(
    code = "one-time-code",
    client_id = "12345",
    client_secret = "client-secret"
  )

  testthat::expect_equal(
    unclass(request$body$data$grant_type),
    "authorization_code"
  )
  testthat::expect_equal(unclass(request$body$data$code), "one-time-code")
  testthat::expect_equal(request$body$type, "form")
})

testthat::test_that("token response validation requires tokens and scopes", {
  valid_response <- list(
    access_token = "access-token",
    refresh_token = "refresh-token",
    scope = "read activity:read_all profile:read_all"
  )

  testthat::expect_setequal(
    validate_strava_token_response(valid_response),
    strava_required_scopes()
  )

  testthat::expect_error(
    validate_strava_token_response(
      utils::modifyList(
        valid_response,
        list(scope = "read activity:read_all")
      )
    ),
    "Missing: profile:read_all"
  )

  testthat::expect_error(
    validate_strava_token_response(
      valid_response[c("access_token", "scope")]
    ),
    "refresh_token"
  )

  invalid_response <- valid_response
  invalid_response$refresh_token <- NA_character_
  testthat::expect_error(
    validate_strava_token_response(invalid_response),
    "refresh_token"
  )
})

testthat::test_that("bootstrap persists only a validated refresh token", {
  with_strava_oauth_environment({
    renviron_path <- tempfile()
    writeLines(
      c(
        "STRAVA_REFRESH_TOKEN=old-token",
        "GOOGLE_HEALTH_REFRESH_TOKEN=google-token"
      ),
      renviron_path
    )

    callback <- paste0(
      "http://localhost/?code=one-time-code",
      "&scope=read%2Cactivity%3Aread_all%2Cprofile%3Aread_all",
      "&state=known-state"
    )

    messages <- testthat::capture_messages(
      result <- bootstrap_strava_oauth(
        redirect_input_fn = function() callback,
        exchange_fn = function(code, client_id, client_secret) {
          testthat::expect_equal(code, "one-time-code")
          testthat::expect_equal(client_id, "12345")
          testthat::expect_equal(client_secret, "client-secret")
          list(
            access_token = "new-access-token",
            refresh_token = "new-refresh-token",
            scope = "read activity:read_all profile:read_all"
          )
        },
        state_fn = function() "known-state",
        renviron_path = renviron_path
      )
    )

    persisted <- readLines(
      renviron_path,
      warn = FALSE
    )

    testthat::expect_true(
      "STRAVA_REFRESH_TOKEN=new-refresh-token" %in% persisted
    )
    testthat::expect_true(
      "GOOGLE_HEALTH_REFRESH_TOKEN=google-token" %in% persisted
    )
    testthat::expect_setequal(
      result$scopes,
      strava_required_scopes()
    )

    visible_output <- paste(messages, collapse = "\n")
    testthat::expect_false(
      grepl("new-refresh-token|new-access-token|client-secret|one-time-code",
            visible_output)
    )
  })
})

testthat::test_that("bootstrap does not persist insufficient scopes", {
  with_strava_oauth_environment({
    renviron_path <- tempfile()
    writeLines(
      "STRAVA_REFRESH_TOKEN=old-token",
      renviron_path
    )

    callback <- paste0(
      "http://localhost/?code=one-time-code",
      "&scope=read%2Cactivity%3Aread_all%2Cprofile%3Aread_all",
      "&state=known-state"
    )

    testthat::expect_error(
      testthat::capture_messages(
        bootstrap_strava_oauth(
          redirect_input_fn = function() callback,
          exchange_fn = function(code, client_id, client_secret) {
            list(
              access_token = "new-access-token",
              refresh_token = "new-refresh-token",
              scope = "read activity:read_all"
            )
          },
          state_fn = function() "known-state",
          renviron_path = renviron_path
        )
      ),
      "Missing: profile:read_all"
    )

    testthat::expect_equal(
      readLines(renviron_path, warn = FALSE),
      "STRAVA_REFRESH_TOKEN=old-token"
    )
  })
})

testthat::test_that("bootstrap does not persist an incomplete token response", {
  with_strava_oauth_environment({
    renviron_path <- tempfile()
    writeLines(
      c(
        "STRAVA_REFRESH_TOKEN=old-token",
        "GOOGLE_HEALTH_REFRESH_TOKEN=google-token"
      ),
      renviron_path
    )

    callback <- paste0(
      "http://localhost/?code=one-time-code",
      "&scope=read%2Cactivity%3Aread_all%2Cprofile%3Aread_all",
      "&state=known-state"
    )

    testthat::expect_error(
      testthat::capture_messages(
        bootstrap_strava_oauth(
          redirect_input_fn = function() callback,
          exchange_fn = function(code, client_id, client_secret) {
            list(
              access_token = "new-access-token",
              scope = "read activity:read_all profile:read_all"
            )
          },
          state_fn = function() "known-state",
          renviron_path = renviron_path
        )
      ),
      "refresh_token"
    )

    testthat::expect_equal(
      readLines(renviron_path, warn = FALSE),
      c(
        "STRAVA_REFRESH_TOKEN=old-token",
        "GOOGLE_HEALTH_REFRESH_TOKEN=google-token"
      )
    )
  })
})

testthat::test_that("OAuth state is a cryptographically generated 256-bit hex value", {
  state_one <- generate_strava_oauth_state()
  state_two <- generate_strava_oauth_state()

  testthat::expect_match(state_one, "^[0-9a-f]{64}$")
  testthat::expect_match(state_two, "^[0-9a-f]{64}$")
  testthat::expect_false(identical(state_one, state_two))
})

testthat::test_that("stdin redirect prompt reads and trims one complete line", {
  input <- textConnection(
    "  http://localhost/?code=example&state=known-state  \n",
    open = "r"
  )
  output <- textConnection("prompt_output", open = "w", local = TRUE)
  on.exit(close(input), add = TRUE)
  on.exit(close(output), add = TRUE)

  value <- prompt_for_strava_redirect(
    input = input,
    output = output
  )

  testthat::expect_equal(
    value,
    "http://localhost/?code=example&state=known-state"
  )
  testthat::expect_match(
    paste(prompt_output, collapse = "\n"),
    "press Enter"
  )
})

testthat::test_that("stdin redirect prompt rejects blank input", {
  input <- textConnection("   \n", open = "r")
  output <- textConnection(NULL, open = "w")
  on.exit(close(input), add = TRUE)
  on.exit(close(output), add = TRUE)

  testthat::expect_error(
    prompt_for_strava_redirect(input = input, output = output),
    "No Strava redirect URL was supplied"
  )
})

testthat::test_that("stdin redirect prompt rejects EOF", {
  input <- textConnection(character(), open = "r")
  output <- textConnection(NULL, open = "w")
  on.exit(close(input), add = TRUE)
  on.exit(close(output), add = TRUE)

  testthat::expect_error(
    prompt_for_strava_redirect(input = input, output = output),
    "No Strava redirect URL was supplied"
  )
})

testthat::test_that("authorization redirect parser rejects NULL input", {
  testthat::expect_error(
    parse_strava_authorization_redirect(
      NULL,
      expected_state = "known-state"
    ),
    "No Strava redirect URL"
  )
})
