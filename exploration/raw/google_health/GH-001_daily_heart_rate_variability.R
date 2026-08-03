################################################################################
# EXPLORATION
#
# SUBJECT
# Google Health Daily Heart Rate Variability
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

raw_hrv <- dbGetQuery(
  con,
  "
  SELECT
    google_health_user_id,
    activity_date,
    source_ecosystem,
    average_hrv_milliseconds
  FROM cycling_platform_raw.google_health_daily_heart_rate_variability
  "
)

################################################################################
# EXPLORE
# Dataset overview
################################################################################

glimpse(raw_hrv)

summary(raw_hrv)

################################################################################
# EXPLORE
# Grain
################################################################################

raw_hrv |>
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

raw_hrv |>
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

raw_hrv |>
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
# - Concurrent measurements differ between ecosystems.
################################################################################

################################################################################
# OPEN QUESTIONS
#
# - What exactly does activity_date represent?
# - Are Apple and Fitbit measuring identical HRV metrics?
# - Is one HRV observation per day guaranteed by the API or merely observed?
################################################################################

################################################################################
# EXPLORE
# Relationship with training load
################################################################################

raw_fitbit_hrv <-
  raw_hrv |>
  filter(source_ecosystem == "fitbit") |>
  transmute(
    start_date_local = activity_date,
    metric = "hrv_ms",
    value = average_hrv_milliseconds
  )

activity_work <-
  silver_activities |>
  filter(
    start_date_local >
      min(raw_fitbit_hrv$start_date_local) -
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
  raw_fitbit_hrv
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
# - Visual inspection suggests HRV responds to accumulated training load.
# - Relationship requires quantitative investigation.
################################################################################

################################################################################
# CANDIDATE SILVER DESIGN
#
# Proposed object:
#
# silver.health_daily_heart_rate_variability
#
# Candidate grain:
#
# One observation per person per day.
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
