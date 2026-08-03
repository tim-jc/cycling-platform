# Exploration helpers for functionality not already available in the platform.

sample_json_payload <- function(
  data,
  payload_column,
  seed = NULL
) {
  if (!is.null(seed)) {
    set.seed(seed)
  }

  payload_json <-
    data |>
    dplyr::slice_sample(n = 1) |>
    dplyr::pull({{ payload_column }})

  parse_json_payload(payload_json)
}


parse_json_payload <- function(payload_json) {
  parsed <-
    jsonlite::fromJSON(
      payload_json,
      simplifyVector = FALSE,
      bigint_as_char = TRUE
    )

  flattened <-
    purrr::list_flatten(
      parsed,
      name_spec = "{outer}.{inner}"
    ) |>
    purrr::map(
      \(value) {
        if (length(value) == 1L && !is.list(value)) {
          value
        } else {
          list(value)
        }
      }
    )

  list(
    json = payload_json,
    parsed = parsed,
    row = tibble::as_tibble(flattened)
  )
}

# Parse one payload without stopping a dataset-wide exploration.
parse_json_payload_safe <- function(payload_json) {
  if (
    is.null(payload_json) ||
      length(payload_json) != 1L ||
      is.na(payload_json) ||
      !nzchar(trimws(payload_json))
  ) {
    return(list(ok = FALSE, parsed = NULL, error = "missing payload"))
  }

  tryCatch(
    list(
      ok = TRUE,
      parsed = jsonlite::fromJSON(
        payload_json,
        simplifyVector = FALSE,
        bigint_as_char = TRUE
      ),
      error = NULL
    ),
    error = function(error) {
      list(
        ok = FALSE,
        parsed = NULL,
        error = conditionMessage(error)
      )
    }
  )
}

# Extract a value from a parsed payload using a character path.
safe_nested_extract <- function(payload, path, default = NULL) {
  if (is.character(path) && length(path) == 1L) {
    path <- strsplit(path, ".", fixed = TRUE)[[1]]
  }

  value <- payload

  for (component in path) {
    if (!is.list(value) || is.null(names(value)) || !component %in% names(value)) {
      return(default)
    }

    value <- value[[component]]
  }

  if (is.null(value)) default else value
}

json_value_type <- function(value) {
  if (is.null(value)) return("null")
  if (is.list(value) && is.null(names(value))) return("array")
  if (is.list(value)) return("object")
  if (is.logical(value)) return("logical")
  if (is.integer(value)) return("integer")
  if (is.numeric(value)) return("number")
  if (is.character(value)) return("character")
  class(value)[[1]]
}

# Recursively flatten named JSON objects while retaining arrays as one field.
recursive_payload_fields <- function(payload, prefix = NULL) {
  if (!is.list(payload) || is.null(names(payload))) {
    return(tibble::tibble(
      field_name = prefix %||% "<root>",
      value = list(payload),
      observed_type = json_value_type(payload),
      is_null = is.null(payload)
    ))
  }

  purrr::map_dfr(
    names(payload),
    function(name) {
      value <- payload[name]
      field_name <- if (is.null(prefix)) name else paste(prefix, name, sep = ".")

      # `payload[name]` retains the field name even when its value is JSON null.
      field_value <- value[[1]]

      if (is.list(field_value) && !is.null(names(field_value))) {
        recursive_payload_fields(field_value, field_name)
      } else {
        tibble::tibble(
          field_name = field_name,
          value = list(field_value),
          observed_type = json_value_type(field_value),
          is_null = is.null(field_value)
        )
      }
    }
  )
}

# Summarise recursive field presence, observed types and explicit nulls.
payload_field_coverage <- function(payloads) {
  total_payloads <- length(payloads)
  parsed <- purrr::map(payloads, parse_json_payload_safe)

  fields <- purrr::imap_dfr(
    parsed,
    function(result, payload_number) {
      if (!isTRUE(result$ok)) return(tibble::tibble())

      recursive_payload_fields(result$parsed) |>
        dplyr::mutate(payload_number = payload_number)
    }
  )

  if (nrow(fields) == 0L) {
    return(tibble::tibble(
      field_name = character(),
      coverage_percent = numeric(),
      observed_type = character(),
      null_frequency = numeric()
    ))
  }

  fields |>
    dplyr::group_by(field_name) |>
    dplyr::summarise(
      payloads_present = dplyr::n_distinct(payload_number),
      coverage_percent = 100 * payloads_present / total_payloads,
      observed_type = paste(sort(unique(observed_type)), collapse = ", "),
      null_count = sum(is_null),
      null_frequency = null_count / dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::arrange(dplyr::desc(coverage_percent), field_name)
}
