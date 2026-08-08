################################################################################
# EXPLORATION
#
# SUBJECT
# Google Health Daily Resting Heart Rate
#
# PURPOSE
# Understand the RAW data sufficiently to design a canonical Silver object.
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

silver_activities <- dbGetQuery(
  con,
  "
  SELECT
    activity_id,
    start_date_local,
    energy_kilojoules
  FROM cycling_platform_silver.activities
  "
)

raw_rhr <- dbGetQuery(
  con,
  "
  SELECT
    *
  FROM cycling_platform_raw.google_health_daily_resting_heart_rate
  "
)

################################################################################
# EXPLORE
# Dataset overview
################################################################################

glimpse(raw_rhr)

summary(raw_rhr)

################################################################################
# EXPLORE
# Grain
################################################################################

raw_rhr |>
  count(
    google_health_user_id,
    activity_date,
    source_ecosystem
  ) |>
  arrange(desc(n))

################################################################################
# EXPLORE
# Coverage
################################################################################

raw_rhr |>
  group_by(source_ecosystem) |>
  summarise(
    first_date = min(activity_date),
    last_date = max(activity_date),
    observations = n(),
    distinct_days = n_distinct(activity_date),
    .groups = "drop"
  )

################################################################################
# EXPLORE
# Distribution over time
################################################################################

raw_rhr |>
  ggplot(
    aes(activity_date)
  ) +
  geom_bar() +
  facet_wrap(
    ~source_ecosystem,
    nrow = 2
  )

################################################################################
# FINDINGS
#
# - Apple and Fitbit overlap for only a small number of dates.
# - Fitbit provides the most complete longitudinal series.
# - Three Fitbit measurements are present on 2026-07-25, all other days one only
#   Google Health app shows one measurement for that day (42bpm). Timestamps
#   suggest it was created / updated later than the other values.
# - Concurrent measurements differ between ecosystems.
################################################################################

################################################################################
# OPEN QUESTIONS
#
# - What exactly does activity_date represent?
# - Are Apple and Fitbit measuring identical RHR metrics?
# - Why do multiple RHR values appear in a single day of a "daily" dataset?
################################################################################

################################################################################
# EXPLORE
# Relationship with training load
################################################################################

raw_fitbit_rhr <-
  raw_rhr |>
  filter(source_ecosystem == "fitbit") |>
  transmute(
    start_date_local = activity_date,
    metric = "rhr_bpm",
    value = resting_heart_rate_bpm
  )

activity_work <-
  silver_activities |>
  filter(
    start_date_local >
      min(raw_fitbit_rhr$start_date_local) -
        lubridate::days(7)
  ) |>
  group_by(start_date_local) |>
  summarise(
    value = sum(
      energy_kilojoules,
      na.rm = TRUE
    ),
    .groups = "drop"
  ) |>
  tidyr::complete(
    start_date_local = seq(
      min(start_date_local),
      max(start_date_local),
      by = "1 day"
    ),
    fill = list(value = 0)
  ) |>
  mutate(
    metric = "total_work_done_kj"
  )

bind_rows(
  activity_work,
  raw_fitbit_rhr
) |>
  ggplot(
    aes(
      x = start_date_local,
      y = value
    )
  ) +
  geom_line() +
  geom_point() +
  facet_wrap(
    ~metric,
    scales = "free_y",
    ncol = 1
  )

################################################################################
# FINDINGS
#
# - Visual inspection suggests RHR responds to accumulated training load.
# - Relationship requires quantitative investigation.
################################################################################

################################################################################
# CANDIDATE SILVER DESIGN
#
# Proposed object:
#
# silver.health_daily_resting_heart_rate
#
# Candidate grain:
#
# UNKNOWN - need to understand multiple daily results first.
#
# Source policy:
#
# PROVISIONAL
#
# Prefer Fitbit because it provides the most consistent longitudinal series.
#
# Preserve all Apple observations in Raw.
#
# Review this decision once activity_date semantics and metric definitions are
# fully understood.
################################################################################

################################################################################
# NEXT QUESTIONS
#
# □ Confirm activity_date semantics.
# □ Confirm HRV metric definition.
# □ Confirm measurement units.
# □ Quantify missingness.
# □ Determine whether source selection belongs in Silver or Gold.
################################################################################
