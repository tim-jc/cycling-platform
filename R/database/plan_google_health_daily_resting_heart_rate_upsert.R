google_health_rhr_payload_hash <- function(payload) {
  vapply(
    payload,
    function(value) {
      as.character(openssl::sha256(charToRaw(as.character(value))))
    },
    character(1)
  )
}

plan_google_health_daily_resting_heart_rate_upsert <- function(
  daily_resting_heart_rate,
  existing_rows
) {
  key_column <- "daily_resting_heart_rate_key"
  payload_column <- "daily_resting_heart_rate_payload"

  if (nrow(daily_resting_heart_rate) == 0L) {
    return(list(
      to_insert = daily_resting_heart_rate,
      to_update = daily_resting_heart_rate,
      unchanged = daily_resting_heart_rate,
      duplicate_count = 0L
    ))
  }

  keys <- as.character(daily_resting_heart_rate[[key_column]])
  if (anyNA(keys) || any(!nzchar(keys))) {
    stop("Google Health daily RHR keys must be non-empty.", call. = FALSE)
  }

  incoming <- dplyr::mutate(
    daily_resting_heart_rate,
    .payload_hash = google_health_rhr_payload_hash(.data[[payload_column]])
  )

  conflicting_keys <- incoming |>
    dplyr::group_by(.data[[key_column]]) |>
    dplyr::summarise(
      distinct_payloads = dplyr::n_distinct(.payload_hash),
      .groups = "drop"
    ) |>
    dplyr::filter(distinct_payloads > 1L)

  if (nrow(conflicting_keys) > 0L) {
    stop(
      paste0(
        "Conflicting Google Health daily RHR payloads share the same source ",
        "identity: ",
        paste(conflicting_keys[[key_column]], collapse = ", "),
        "."
      ),
      call. = FALSE
    )
  }

  duplicate_count <- sum(duplicated(keys))
  incoming <- dplyr::distinct(
    incoming,
    .data[[key_column]],
    .keep_all = TRUE
  )

  existing <- existing_rows |>
    dplyr::transmute(
      daily_resting_heart_rate_key = as.character(
        .data$daily_resting_heart_rate_key
      ),
      .existing_payload_hash = as.character(.data$payload_hash)
    )

  classified <- dplyr::left_join(
    incoming,
    existing,
    by = key_column
  )

  drop_planning_columns <- function(data) {
    dplyr::select(data, -dplyr::any_of(c(
      ".payload_hash",
      ".existing_payload_hash"
    )))
  }

  list(
    to_insert = classified |>
      dplyr::filter(is.na(.existing_payload_hash)) |>
      drop_planning_columns(),
    to_update = classified |>
      dplyr::filter(
        !is.na(.existing_payload_hash),
        .payload_hash != .existing_payload_hash
      ) |>
      drop_planning_columns(),
    unchanged = classified |>
      dplyr::filter(
        !is.na(.existing_payload_hash),
        .payload_hash == .existing_payload_hash
      ) |>
      drop_planning_columns(),
    duplicate_count = as.integer(duplicate_count)
  )
}
