################################################################################
# EXPLORATION
#
# SUBJECT
# Strava laps
#
# PURPOSE
# Understand the RAW data sufficiently to design a canonical Silver object.
#
# QUESTIONS
# 1. What is the observed grain?
# 2. Is the grain stable?
# 3. What is the JSON payload's structure
# 4. Is the metric useful for downstream analytics?
#
# OUTPUT
# - Findings
# - Open questions
# - Candidate Silver design
################################################################################

library(DBI)
library(dplyr)
library(tidyr)
library(ggplot2)

rm(list = ls())

source("bootstrap.R")
source("exploration/helpers.R")

################################################################################
# DATA EXTRACTION
################################################################################

con <- get_connection()

on.exit(DBI::dbDisconnect(con), add = TRUE)

raw_laps <- dbGetQuery(
  con,
  "
  SELECT
    activity_id,
    lap_index,
    lap_payload
  FROM cycling_platform_raw.activity_laps
  "
)

################################################################################
# EXPLORE
# Sample JSON payload
################################################################################

example_payload <- sample_json_payload(raw_laps, lap_payload, seed = 44)

example_payload$row

################################################################################
# FINDINGS
#
# - Nested objects within payload for athlete and activity. A lap is a property
#   of a single activity, which is the property of a single athlete, so should
#   only have one record in each nest. This behaviour observed. Need to confirm
#   before making behavioural assumptions however
# - Payload contains start and end indices and provides helfpul summary statistics
#   (e.g. average power, HR) which will be valuable in silver
################################################################################

################################################################################
# EXPLORE
# Specific activity JSON payload
################################################################################

activity_payload <- raw_laps |>
  filter(activity_id == 19378607568, lap_index == 5) |>
  pull(lap_payload)

parsed_lap <- parse_json_payload(activity_payload)$row


################################################################################
# EXPLORE
# Grain
################################################################################

raw_laps |>
  count(
    activity_id,
    lap_index
  ) |>
  arrange(desc(n)) |>
  head(n = 10)

################################################################################
# CANDIDATE SILVER DESIGN
#
# Proposed object:
#
# silver.activity_laps
#
# Candidate grain:
#
# One observation per activity_id x lap_index
#
# Proposed promoted fields:
# (validated that metrics refer to lap, not activity via manual review against
#  Strava website)
#
# activity$id           activity_id
# lap_index             lap_index
# name                  lap_name
# start_date            lap_start_datetime_utc
# start_date_local      lap_start_datetime_local
# elapsed_time          lap_elapsed_time
# moving_time           lap_moving_time
# start_index           lap_start_index
# end_index             lap_end_index
# distance              lap_distance_metres
# average_speed         lap_average_speed_metres_per_second
# average_cadence       lap_average_cadence_rpm
# average_watts         lap_average_watts
# total_elevation_gain  lap_elevation_gain_metres
################################################################################

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
