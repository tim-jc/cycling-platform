################################################################################
# EXPLORATION
#
# SUBJECT
# Google Health Exercise
#
# PURPOSE
# Understand the RAW data sufficiently to design a canonical Silver object,
# particularly for workouts imported via Apple Health
#
# QUESTIONS
# 1. What is the observed grain?
# 2. Is the grain stable?
# 3. Which source ecosystems contribute data?
# 4. Are concurrent observations expected?
# 5. Are source values comparable?
# 6. Is the metric useful for downstream analytics?
#
# OUTPUT
# - Findings
# - Open questions
# - Candidate Silver design
################################################################################

library(DBI)
library(dplyr)
library(ggplot2)

source("bootstrap.R")

################################################################################
# DATA EXTRACTION
################################################################################

con <- get_connection()

on.exit(DBI::dbDisconnect(con), add = TRUE)

raw_exercise <- dbGetQuery(
  con,
  "
  SELECT
    *
  FROM cycling_platform_raw.google_health_exercise
  "
)

################################################################################
# EXPLORE
# Dataset overview
################################################################################

# Grain is one record per exercise event

# Workout types
raw_exercise |>
  count(source_ecosystem, exercise_type)

# Need to review payload exampes for apple CORE_TRAINING, WORKOUT, YOGA

################################################################################
# EXPLORE
# WORKOUT example
################################################################################

example_workout_payload <- raw_exercise |>
  filter(source_ecosystem == "apple_health", exercise_type == "WORKOUT") |>
  slice_sample(n = 1) |>
  pull(exercise_payload)

# inspect paylod
jsonlite::fromJSON(example_workout_payload)

# CONCLUSION - very little of value to promote that isn't already available in raw.
# Only potentials:
# - $exercise$activeDuration
# - $exercise$metricsSummary$caloriesKcal
# - $exercise$metricsSummary$averageHeartRateBeatsPerMinute

################################################################################
# EXPLORE
# CORE_TRAINING example
################################################################################

example_core_training_payload <- raw_exercise |>
  filter(source_ecosystem == "apple_health", exercise_type == "WORKOUT") |>
  slice_sample(n = 1) |>
  pull(exercise_payload)

# inspect paylod
jsonlite::fromJSON(example_core_training_payload)

# CONCLUSION - very little of value to promote that isn't already available in raw.
# Only potentials:
# - $exercise$activeDuration
# - $exercise$metricsSummary$caloriesKcal
# - $exercise$metricsSummary$averageHeartRateBeatsPerMinute

################################################################################
# EXPLORE
# YOGA example
################################################################################

example_yoga_payload <- raw_exercise |>
  filter(source_ecosystem == "apple_health", exercise_type == "WORKOUT") |>
  slice_sample(n = 1) |>
  pull(exercise_payload)

# inspect paylod
jsonlite::fromJSON(example_yoga_payload)

# CONCLUSION - very little of value to promote that isn't already available in raw.
# Only potentials:
# - $exercise$activeDuration
# - $exercise$metricsSummary$caloriesKcal
# - $exercise$metricsSummary$averageHeartRateBeatsPerMinute

# Extra findings - it's possible for exercise to be paused and resumed (recorded in
# $exercise$exerciseEvents). Need to make sure any duration value in silver excluded
# any time that is paused.
