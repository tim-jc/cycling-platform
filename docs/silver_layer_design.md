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
* Make consumer migration easy by exposing activities and streams in familiar
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

R/transforms/
  run_silver_transformations.R
  rebuild_silver_activity_streams.R
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
* rebuild stream samples in activity batches rather than one whole-table SQL
  statement

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

Silver activity rebuilds write run and single-batch progress to
`cycling_platform_admin.transform_run` and
`cycling_platform_admin.transform_run_batch`. The log records expected raw
activity rows, inserted silver rows, timing, and failures.

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

Location columns depend on raw `latlng` payload precision. Historical raw
stream payloads loaded before the `digits = NA` serialization fix have rounded
coordinates and should be fully reloaded before silver stream latitude and
longitude are used for map or route analysis.

### Rebuild Behaviour

`silver.activity_streams` is rebuilt by `rebuild_silver_activity_streams()` in
activity batches. This avoids one long-running opaque `INSERT ... SELECT`,
limits transaction size, and produces progress messages during large stream
expansions.

The batch size is controlled by
`transforms.silver_stream_activity_batch_size` and
`transforms.silver_stream_batch_max_expected_rows` in `config/platform.yml`.

Batches are planned using both activity count and expected stream row count.
Expected row count comes from `MAX(original_size)` in
`raw.activity_streams`. This keeps short activities grouped efficiently while
long rides are isolated into smaller database statements.

The expected-row cap should be conservative on the Raspberry Pi-hosted MariaDB
because large JSON expansion statements can cause the server connection to drop.
If a single activity still exceeds the practical limit, the next refinement is
sample-range batching within an activity.

Run modes:

```sh
Rscript run_silver.R
Rscript run_silver.R repair
```

The default mode truncates and fully rebuilds `silver.activity_streams`.
`repair` mode compares raw stream `original_size` values with existing silver
row counts, then deletes and rebuilds only missing or incomplete activities.
This is the preferred recovery path after an interrupted silver stream rebuild.

For the historical Mac-to-Pi recovery path, a temporary local R backfill helper
can parse raw stream JSON in R and rebuild `silver.activity_streams` one
activity at a time. It is useful when MariaDB-side JSON expansion is too slow or
causes connection drops, but it should remain a recovery tool rather than the
long-term orchestration pattern.

Silver stream rebuilds write run and batch progress to
`cycling_platform_admin.transform_run` and
`cycling_platform_admin.transform_run_batch`. These logs record planned and
completed batches, activity counts, expected rows, inserted/deleted rows,
duration, and failures.

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

Those two tables are sufficient for the Coastal project. Coastal is fully
migrated to `cycling-platform`, complete, and no longer depends on the legacy
scraper database.

Broader legacy scraper replacement moves into `cycling-analytics` and should
not recreate old scraper tables one-for-one. Legacy objects should be treated
as requirements and examples. Analytical work should adapt to the platform
model, with reusable gold objects built where the old scraper exposed derived
concepts such as peaks and power summaries.

Gold design notes are tracked in `docs/gold_layer_design.md`.
