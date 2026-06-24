# Silver Layer Design

## Purpose

The silver layer provides conformed, analytics-ready entities for dashboards,
MCP tools, and future gold models.

Consumers should use silver or gold data only. Raw tables remain the source of
truth for ingestion, auditability, and reprocessing.

## Design Principles

* Preserve raw payloads in the raw layer; do not duplicate full source JSON in
  silver.
* Use stable business keys from Strava.
* Standardise naming, units, and timestamp handling.
* Keep silver close to source semantics, but remove raw ingestion concerns.
* Make dashboard migration easy by exposing activities and streams in familiar
  analytical shapes.
* Ensure transformations are reproducible from raw data.

## Implementation Direction

Silver transformations should be SQL-first and orchestrated by R.

Proposed structure:

```text
sql/silver/
  200_create_activities.sql
  210_transform_activities.sql
  220_create_activity_streams.sql
  230_transform_activity_streams.sql

R/transforms/
  run_silver_transformations.R
```

`bootstrap_platform.R` should run only create scripts for derived layers. Silver
transformation scripts are intentionally excluded from bootstrap and should be
run explicitly with `Rscript run_silver.R`.

Use R for orchestration, run metadata, data quality checks, and any later
analytics that are awkward in SQL.

## Refresh Strategy

Silver tables should be rebuildable from raw data.

Initial strategy:

* truncate and reload silver tables after raw ingestion
* keep transformations deterministic
* avoid incremental silver logic until raw entity patterns are stable
* keep rebuilds out of bootstrap so schema setup cannot get stuck on large
  derived table loads

Future strategy:

* incremental transforms by `updated_at` or affected `activity_id`
* transformation run metadata
* data quality gates before gold models refresh

## Determinism and Source Truth

A silver transformation is deterministic when the same raw inputs and the same
transformation code produce the same conformed output. Processing metadata such
as `transformed_at` may vary between runs, but conformed business values should
not depend on run order, local state, or previous silver contents.

Raw JSON payloads remain the source of truth. Promoted raw columns can be used
in silver when they are direct extracts or stable normalisations of the same
payload fields, because they are cached access paths rather than independent
truth. If a promoted raw column disagrees with the corresponding payload value,
the payload value should win and the mismatch should be reported as a data
quality issue.

## `silver.activities`

### Grain

One row per Strava activity.

### Business Key

`activity_id`

### Sources

* `raw.activities`
* `raw.activity_details`, where available
* future `raw.gear`
* future `raw.athlete`

### Purpose

Provide a conformed activity dimension/fact hybrid suitable for dashboards and
downstream modelling.

### Candidate Columns

Identifiers:

* `activity_id`
* `athlete_id`
* `source_id`
* `gear_id`

Descriptive fields:

* `activity_name`
* `sport_type`
* `activity_type`, if useful as a conformed grouping
* `timezone_name`

Timestamps:

* `start_datetime_utc`
* `start_datetime_local`
* `start_date_local`
* `start_time_local`
* `retrieved_at`

Measures:

* `distance_metres`
* `distance_kilometres`
* `distance_miles`
* `moving_time_seconds`
* `elapsed_time_seconds`
* `elevation_gain_metres`
* `average_speed_metres_per_second`
* `average_speed_kilometres_per_hour`
* `average_speed_miles_per_hour`
* `average_cadence_rpm`
* `average_heartrate_bpm`
* `average_power_watts`
* `weighted_average_power_watts`
* `energy_kilojoules`

Flags:

* `is_device_watts`
* `is_manual`, derived from raw/details payload where available
* `is_trainer`, derived from raw/details payload where available
* `has_streams`
* `has_details`

Lineage:

* `raw_activity_retrieved_at`
* `raw_detail_retrieved_at`
* `transformed_at`

### Notes

Silver should prefer promoted raw columns where they already exist. Use JSON
extraction from `raw_payload` or `details_payload` for fields that are not yet
promoted but are analytically useful.

Where silver uses promoted columns, matching data quality checks should compare
those columns back to their source payload fields for direct extracts. This
keeps the implementation efficient without weakening the raw-payload
source-of-truth principle.

Metric/SI fields should remain canonical. Imperial fields such as
`distance_miles` and `average_speed_miles_per_hour` are convenience columns for
dashboards and should be derived consistently in silver.

## `silver.activity_streams`

### Grain

One row per activity stream sample.

Recommended business key:

```text
activity_id + sample_index
```

### Sources

* `raw.activity_streams`
* `raw.activities`

### Purpose

Provide dashboard-friendly time series data without requiring consumers to parse
raw JSON stream arrays.

### Shape

Use a wide sample table, not one row per stream type.

Each row represents a sample index within an activity, with stream values as
columns:

* `activity_id`
* `sample_index`
* `time_seconds`
* `distance_metres`
* `latitude`
* `longitude`
* `altitude_metres`
* `velocity_smooth_metres_per_second`
* `heartrate_bpm`
* `cadence_rpm`
* `watts`
* `temperature_celsius`
* `is_moving`
* `grade_smooth_percent`
* `transformed_at`

### Stream Alignment

Strava streams are returned as separate arrays by stream type. Silver should
align them by array position within each activity.

Assumptions to validate:

* stream arrays for an activity generally share the same `original_size`
* missing stream types should produce `NULL` columns
* `sample_index` should be one-based or zero-based consistently; prefer
  one-based in SQL-facing tables unless dashboard code needs zero-based indexes

### Alternative Shape Considered

A long/narrow table is possible:

```text
activity_id, sample_index, stream_type, stream_value
```

This is flexible but less convenient for dashboards and common ride analytics.
The preferred silver shape is wide because existing dashboards are likely to
benefit from direct columns for heart rate, power, cadence, distance, and
location.

### Lineage

Include enough lineage to trace back to raw stream records:

* `activity_id`
* stream source availability flags if useful
* `transformed_at`

Raw stream payloads remain in `raw.activity_streams`.

## Data Quality Expectations

Initial silver checks:

* every `silver.activities.activity_id` maps to one raw activity
* `silver.activity_streams.activity_id` maps to one silver activity
* stream sample indexes are unique per activity
* stream sample counts do not exceed raw stream `original_size`
* required activity measures are non-negative where applicable
* timestamp fields are populated for activities

## Dashboard Migration

The first useful silver milestone is:

* `silver.activities`
* `silver.activity_streams`

Once those exist, existing dashboards can be repointed away from legacy
preparation code. Gold models can wait until the dashboard migration surface is
stable.
