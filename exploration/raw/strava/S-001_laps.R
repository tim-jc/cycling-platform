# STRAVA LAPS: RETAINED RAW -> SILVER EXPLORATION
# Read-only evidence for deciding whether/how to create silver.activity_laps.

source("bootstrap.R")
source(file.path("exploration", "helpers.R"))

# Edit these to inspect a particular lap. The deterministic sample still prints
# when this activity/lap is absent.
example_activity_id <- "19378607568"
example_lap_index <- 5L

heading <- function(text) cat("\n", text, "\n", strrep("-", nchar(text)), "\n", sep = "")

payload_value <- function(result, path, numeric = FALSE) {
  if (!result$ok) return(if (numeric) NA_real_ else NA_character_)
  value <- safe_nested_extract(result$parsed, path)
  if (is.null(value) || length(value) != 1L) return(if (numeric) NA_real_ else NA_character_)
  if (numeric) suppressWarnings(as.numeric(value)) else as.character(value)
}

main <- function() {
  connection <- get_connection("cycling_platform_admin")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)

  raw_laps <- DBI::dbGetQuery(connection, "
    SELECT activity_id, lap_index, lap_payload
    FROM cycling_platform_raw.activity_laps
    ORDER BY activity_id, lap_index")
  activities <- DBI::dbGetQuery(connection, "
    SELECT activity_id, distance_metres, elapsed_time_seconds,
           moving_time_seconds, elevation_gain_metres
    FROM cycling_platform_silver.activities")
  streams <- DBI::dbGetQuery(connection, "
    SELECT activity_id, COUNT(*) AS stream_rows,
           MIN(sample_index) AS minimum_sample_index,
           MAX(sample_index) AS maximum_sample_index
    FROM cycling_platform_silver.activity_streams
    GROUP BY activity_id")

  if (!nrow(raw_laps)) {
    message("No Raw lap rows are available.")
    return(invisible(NULL))
  }

  parsed <- purrr::map(raw_laps$lap_payload, parse_json_payload_safe)
  text_field <- function(path) purrr::map_chr(parsed, payload_value, path = path)
  number_field <- function(path) purrr::map_dbl(parsed, payload_value, path = path, numeric = TRUE)
  laps <- tibble::tibble(
    activity_id = as.character(raw_laps$activity_id),
    lap_index = raw_laps$lap_index,
    payload_ok = purrr::map_lgl(parsed, "ok"),
    lap_id = text_field("id"),
    payload_activity_id = text_field("activity.id"),
    payload_lap_index = number_field("lap_index"),
    start_index = number_field("start_index"),
    end_index = number_field("end_index"),
    distance = number_field("distance"),
    elapsed_time = number_field("elapsed_time"),
    moving_time = number_field("moving_time"),
    elevation_gain = number_field("total_elevation_gain")
  )

  heading("1. Dataset overview")
  laps_per_activity <- dplyr::count(laps, activity_id, name = "laps")
  print(tibble::tibble(
    lap_rows = nrow(laps),
    distinct_activities = dplyr::n_distinct(laps$activity_id),
    malformed_payloads = sum(!laps$payload_ok),
    minimum_laps = min(laps_per_activity$laps),
    median_laps = stats::median(laps_per_activity$laps),
    maximum_laps = max(laps_per_activity$laps)
  ))
  print(dplyr::count(laps_per_activity, laps, name = "activities"))

  heading("2. Representative payloads")
  valid_rows <- which(laps$payload_ok)
  if (length(valid_rows)) {
    set.seed(44)
    sample_row <- sample(valid_rows, 1L)
    sample_payload <- parse_json_payload(raw_laps$lap_payload[[sample_row]])
    str(sample_payload$parsed, max.level = 3)
    print(sample_payload$row, width = Inf)

    specific_row <- which(laps$activity_id == example_activity_id &
      laps$lap_index == example_lap_index & laps$payload_ok)
    if (length(specific_row) == 1L) {
      specific <- parse_json_payload(raw_laps$lap_payload[[specific_row]])
      str(specific$parsed, max.level = 3)
      print(recursive_payload_fields(specific$parsed), n = Inf)
    } else {
      message("Editable example not found: ", example_activity_id, " / ", example_lap_index)
    }
  }

  heading("3. Identity and grain")
  identity <- laps |>
    dplyr::summarise(
      missing_lap_id = sum(is.na(lap_id) | !nzchar(lap_id)),
      distinct_lap_ids = dplyr::n_distinct(lap_id, na.rm = TRUE),
      duplicate_lap_ids = sum(duplicated(lap_id) & !is.na(lap_id)),
      duplicate_activity_laps = sum(duplicated(paste(activity_id, lap_index))),
      activity_id_mismatches = sum(!is.na(payload_activity_id) & payload_activity_id != activity_id),
      lap_index_mismatches = sum(!is.na(payload_lap_index) & payload_lap_index != lap_index)
    )
  print(identity)
  print(laps |> dplyr::filter(!is.na(lap_id)) |> dplyr::add_count(lap_id) |>
    dplyr::filter(n > 1) |> utils::head(10))
  print(laps |> dplyr::filter(
    (!is.na(payload_activity_id) & payload_activity_id != activity_id) |
      (!is.na(payload_lap_index) & payload_lap_index != lap_index)
  ) |> utils::head(10))

  heading("4. Lap-index sequencing")
  sequences <- laps |>
    dplyr::group_by(activity_id) |>
    dplyr::arrange(lap_index, .by_group = TRUE) |>
    dplyr::summarise(
      laps = dplyr::n(), distinct_indices = dplyr::n_distinct(lap_index),
      minimum_index = min(lap_index), maximum_index = max(lap_index),
      contiguous = identical(lap_index, seq.int(minimum_index, maximum_index)),
      .groups = "drop"
    )
  print(dplyr::count(sequences, minimum_index, contiguous, name = "activities"))
  print(sequences |> dplyr::filter(!contiguous | laps != distinct_indices) |> utils::head(20))

  heading("5. Stream-boundary semantics")
  indexed_laps <- laps |>
    dplyr::filter(!is.na(start_index), !is.na(end_index)) |>
    dplyr::group_by(activity_id) |>
    dplyr::arrange(lap_index, .by_group = TRUE) |>
    dplyr::mutate(boundary_delta = dplyr::lead(start_index) - end_index) |>
    dplyr::ungroup()
  boundaries <- indexed_laps |>
    dplyr::group_by(activity_id) |>
    dplyr::summarise(
      first_start = min(start_index), final_end = max(end_index),
      inclusive_rows = sum(end_index - start_index + 1),
      exclusive_rows = sum(end_index - start_index), .groups = "drop"
    ) |>
    dplyr::left_join(streams |> dplyr::mutate(activity_id = as.character(activity_id)),
                     by = "activity_id") |>
    dplyr::mutate(
      inclusive_end_match = final_end + 1 == maximum_sample_index,
      exclusive_end_match = final_end == maximum_sample_index,
      inclusive_difference = inclusive_rows - stream_rows,
      exclusive_difference = exclusive_rows - stream_rows
    )
  print(indexed_laps |> dplyr::filter(!is.na(boundary_delta)) |>
    dplyr::count(boundary_delta, sort = TRUE))
  print(boundaries |> dplyr::summarise(
    activities_compared = sum(!is.na(stream_rows)),
    silver_starts_at_one = sum(minimum_sample_index == 1, na.rm = TRUE),
    inclusive_end_matches = sum(inclusive_end_match, na.rm = TRUE),
    exclusive_end_matches = sum(exclusive_end_match, na.rm = TRUE),
    inclusive_row_matches = sum(inclusive_difference == 0, na.rm = TRUE),
    exclusive_row_matches = sum(exclusive_difference == 0, na.rm = TRUE)
  ))
  print(boundaries |> dplyr::arrange(dplyr::desc(abs(inclusive_difference))) |>
    utils::head(10))

  heading("6. Parent-activity reconciliation")
  totals <- laps |>
    dplyr::group_by(activity_id) |>
    dplyr::summarise(
      lap_distance = sum(distance, na.rm = TRUE),
      lap_elapsed = sum(elapsed_time, na.rm = TRUE),
      lap_moving = sum(moving_time, na.rm = TRUE),
      lap_elevation = sum(elevation_gain, na.rm = TRUE), .groups = "drop"
    ) |>
    dplyr::left_join(activities |> dplyr::mutate(activity_id = as.character(activity_id)),
                     by = "activity_id")
  differences <- dplyr::bind_rows(
    dplyr::transmute(totals, activity_id, metric = "distance", difference = lap_distance - distance_metres),
    dplyr::transmute(totals, activity_id, metric = "elapsed_time", difference = lap_elapsed - elapsed_time_seconds),
    dplyr::transmute(totals, activity_id, metric = "moving_time", difference = lap_moving - moving_time_seconds),
    dplyr::transmute(totals, activity_id, metric = "elevation_gain", difference = lap_elevation - elevation_gain_metres)
  )
  print(differences |> dplyr::group_by(metric) |> dplyr::summarise(
    median_difference = stats::median(difference, na.rm = TRUE),
    median_absolute_difference = stats::median(abs(difference), na.rm = TRUE),
    maximum_absolute_difference = max(abs(difference), na.rm = TRUE), .groups = "drop"
  ))
  print(differences |> dplyr::group_by(metric) |>
    dplyr::slice_max(abs(difference), n = 5, with_ties = FALSE) |> dplyr::ungroup())

  heading("7. Payload field coverage")
  useful_fields <- c(
    "id", "activity.id", "lap_index", "name", "start_date", "start_date_local",
    "elapsed_time", "moving_time", "distance", "start_index", "end_index",
    "average_speed", "average_cadence", "average_watts", "average_heartrate",
    "max_heartrate", "total_elevation_gain", "device_watts"
  )
  coverage <- payload_field_coverage(raw_laps$lap_payload) |>
    dplyr::filter(field_name %in% useful_fields)
  print(coverage, n = Inf)
}

if (sys.nframe() == 0L) main()

# FINDINGS
# - Raw row identity is currently activity_id x promoted lap_index.
# - Promoted lap_index is response order assigned by get_activity_laps().
# - Record dataset-specific findings here after reviewing the output.

# PROVISIONAL DECISIONS
# - Treat payload id as candidate lap_id only if completeness, uniqueness and
#   source identity checks pass.
# - Keep lap_index as an ordering key, not an assumed source identity.

# OPEN QUESTIONS
# - Is lap_id stable and globally unique across repeated observations?
# - Are start_index/end_index zero-based, and is end_index inclusive?
# - Are adjacent boundary overlaps intentional?
# - What explains the largest parent-summary differences?
# - Which conditional sensor summaries have a governed downstream use?

# CANDIDATE SILVER DESIGN (NOT FINAL)
# Grain: one current Strava lap per confirmed lap_id.
# Key: lap_id; consider UNIQUE(activity_id, lap_index).
# Fields: lap_id, activity_id, lap_index, lap_name, start_datetime_utc,
# start_datetime_local, elapsed_time_seconds, moving_time_seconds,
# distance_metres, start_sample_index, end_sample_index,
# average_speed_metres_per_second, average_cadence_rpm, average_power_watts,
# average_heartrate_bpm, maximum_heartrate_bpm, elevation_gain_metres,
# is_device_watts. Index semantics remain unresolved; sensor fields are nullable.

# CONFIDENCE
# High: current Raw key and promoted lap_index implementation.
# Dataset-dependent: coverage, uniqueness and identifier agreement.
# Provisional: lap_id as Silver key and reconciliation meaning.
# Unresolved: historical identity stability and stream-boundary semantics.
