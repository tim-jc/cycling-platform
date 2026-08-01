# Silver Layer Design

## Purpose

The silver layer provides conformed, analytics-ready entities for dashboards,
MCP tools, and future gold models.

Consumers should use silver or gold data only. Raw tables remain the source of
truth for ingestion, auditability, and reprocessing.

Draft object-level semantic contracts and generated mechanical metadata are in
[Silver data contracts](data-contracts/silver/README.md). The contracts are the
review surface for meaning; this design document and the implementation remain
inputs rather than substitutes for semantic agreement.

## Design Principles

* Preserve raw payloads in the raw layer; do not duplicate full source JSON in
  silver.
* Use stable business keys from Strava.
* Standardise naming, units, and timestamp handling.
* Keep silver close to source semantics, but remove raw ingestion concerns.
* Make consumer migration easy by exposing activities and streams in familiar
  analytical shapes.
* Ensure transformations are reproducible from raw data.

## Implementation

Silver transformations are SQL-first and orchestrated by R.

Current structure:

```text
sql/silver/
  010_create_activities.sql
  020_transform_activities.sql
  030_create_activity_streams.sql

R/transforms/
  run_silver_transformations.R
  rebuild_silver_activity_streams.R
```

`bootstrap_platform.R` should run only create scripts for derived layers. Silver
transformation scripts are intentionally excluded from bootstrap and should be
run explicitly with `Rscript run_silver.R`.

R owns orchestration, run metadata, data quality checks, and any later
analytics that are awkward in SQL.

## Refresh Strategy

Silver tables are rebuildable from Raw data.

Current strategy:

* `silver.activities` is rebuilt deterministically from Raw;
* scheduled automation runs `silver.activity_streams` in repair mode, rebuilding
  only missing or incomplete activities;
* explicit full mode truncates and rebuilds all Silver stream samples;
* stream work runs in activity/expected-row batches rather than one opaque
  whole-table statement;
* bootstrap creates tables but never launches derived transformations;
* transform metadata and publication gates are recorded in Admin.

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
* `raw.gear_observations` through the separate `silver.gear` relationship
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

## `silver.gear`

The grain and primary key are one row per Strava `gear_id`. The latest Raw
payload supplies the current canonical attributes, while Raw retains prior
payload observations. `first_observed_at`, `last_observed_at`,
`source_observation_run_id`, `source_payload_hash`, and
`transform_version = strava_gear_v1` provide lineage.

Canonical `gear_type` values are `bike`, `shoes`, and `unknown`. `unknown`
means an individually resolved historical record whose type could not be
established from the current `/athlete` collection; the transform does not
infer type from an ID prefix.

`is_current` means the gear appeared in the latest completely successful gear
entity run. Failed or incomplete ingestion cannot retire prior gear.
`is_historical` is the inverse for resolved gear retained to support historical
activities. Silver is a simple current entity rather than an SCD; observation
history remains in Raw.

The supported relationship is:

```text
cycling_platform_silver.activities.gear_id
  → cycling_platform_silver.gear.gear_id
```

Names are not duplicated into every activity. Consumer presentation uses a
join so Strava renames propagate predictably.
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

The expected-row cap should be conservative on MariaDB on `cycling-prod`
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

The historical Mac-to-Pi migration used a local R backfill helper to parse Raw
stream JSON in R. The helper remains recovery tooling. Large historical repairs
should use a staging table and bulk merge into the indexed production table,
keeping repair workloads separate from incremental daily ETL.

The reference implementation is
`backfill_silver_activity_streams_local(mode = "staging_repair")`. It writes
rebuilt rows to `cycling_platform_stage.activity_streams_build` using `run_id`
ownership, validates staged row counts, bulk merges into
`cycling_platform_silver.activity_streams` in small activity-ID batches, and
removes staged rows for each batch only after a successful commit.

If staging has already been populated, merge can be retried without rebuilding
rows by running `backfill_silver_activity_streams_local(mode =
"staging_merge", run_id = <run_id>)`.

Silver stream rebuilds write run and batch progress to
`cycling_platform_admin.transform_run` and
`cycling_platform_admin.transform_run_batch`. These logs record planned and
completed batches, activity counts, expected rows, inserted/deleted rows,
duration, and failures.

### Rebuild progress and ETA

Long-running rebuilds emit a whole-run progress block after the first batch,
the final batch, and otherwise every 10 completed batches or 60 seconds,
whichever occurs first. The defaults are configurable with
`transforms.silver_stream_progress_every_batches` and
`transforms.silver_stream_progress_every_seconds`. Batch start/completion and
warnings remain at INFO. Fetch, parse, insert-chunk, commit, and transaction
detail is emitted only when `logging.level: DEBUG` is configured.

Progress uses cumulative expected rows divided by total expected rows because
stream batch sizes vary substantially. If expected-row totals are unavailable,
it falls back first to completed activities and then to completed batches; the
active basis is printed with the percentage.

The implementation calculates an overall estimate internally from elapsed
time and progress. Operator output remains `ETA: calculating...` for the first
four completed batches. From the fifth batch it uses throughput from up to the
10 most recent batches, and shows both a rolling ETA and an estimated local
finish time. Estimates can move as the mix of short and long activities
changes.

Each progress block includes elapsed time, activities, expected rows,
inserted/deleted rows, average rows per second, and whether recent throughput
is improving, stable, or degrading. A batch is warned as unusually slow when
it exceeds 60 seconds and, once five prior batches exist, three times their
median duration. The completion or failure summary reports aggregate
throughput, average batch duration, failed batches, and up to the five slowest
completed batches. These metrics also remain queryable from the existing Admin
run and batch tables; no progress notifications are sent.

Example INFO output:

```text
Silver streams progress
Batch: 840 / 2,784
Progress: 29.7% (expected_rows)
Activities: 839 / 2,784
Expected rows: 5,482,391 / 18,442,103
Rows inserted/deleted: 5,481,992 / 0
Elapsed: 1h 03m 00s
ETA: 3h 17m 12s (rolling)
Projected finish: 21:03 BST (estimate)
Throughput: 1,450.3 rows/sec (stable)
```

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
not recreate old scraper tables one-for-one. The scraper is frozen and should
be treated as a reference implementation only. Analytical work should adapt to
the platform model, with reusable gold objects built where the old scraper
exposed derived concepts such as peaks and power summaries.

Gold design notes are tracked in `docs/gold_layer_design.md`.
