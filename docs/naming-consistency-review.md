# Naming Consistency Review

## Purpose

This document records the active naming standard for `cycling-platform`,
based on the naming consistency review. It also preserves the review findings
that explain why broad schema renames are not being performed now.

The platform schemas are:

* `cycling_platform_admin`
* `cycling_platform_stage`
* `cycling_platform_raw`
* `cycling_platform_silver`
* `cycling_platform_gold`

## Executive Summary

The repository is broadly consistent with the intended architecture:

* schema names are clear and layer-specific;
* most physical table names are explicit and domain-oriented;
* Silver activity and stream columns already use explicit unit suffixes;
* Gold best efforts already uses a stable analytical grain:
  `activity_id`, `metric_name`, `duration_seconds`.

The main naming risks are forward-looking rather than urgent defects:

* planned training metric names in docs still use legacy shorthand such as
  `FTP`, `VI`, `IF`, `TSS`, `mean power`, and `normalised power`;
* stream metric names mix source-preserved labels (`watts`) with canonical
  unit names (`cadence_rpm`, `heartrate_bpm`);
* Google/Fitbit raw naming currently mixes provider concepts:
  `google_health`, `fitbit_user_id`, and `google_user_id`;
* timestamp naming is mostly consistent, but Raw Google sleep uses
  `physical_time` / `civil_date`, which should remain Raw-only unless
  conformed later;
* documentation contains older example names such as `moving_time` in
  `docs/data_quality_sql.md` that do not match implemented columns.

Decision: adopt the standard below now for all new Silver, Gold, Admin and
Stage objects. Preserve stable existing objects unless a later versioned
migration has a clear benefit.

## Proposed Naming Standard

### General

* Use `snake_case` for schemas, tables, columns, configuration keys, and metric
  names.
* Use full words unless an abbreviation is a documented cycling domain term.
* Avoid vague table names such as `summary`, `data`, or `metrics` unless the
  scope is explicit, for example `activity_power_metrics`.
* Use plural table names for entity sets, for example `activities` and
  `activity_streams`.
* Use singular identifiers, for example `activity_id`, `run_id`, and
  `source_id`.
* Use `NULL` for unavailable values. Do not create synthetic zeroes to mean
  missing data.
* Do not reproduce legacy scraper or `stravR` names automatically.

### Layer Semantics

Raw:

* May preserve upstream API names when they are part of the source contract.
* Should keep full source payloads as JSON.
* Promoted raw columns should be direct extracts or minimal normalisations.
* Source-specific names are acceptable, for example `source_log_id`.

Stage:

* Should align with the destination table where possible.
* Must include `run_id` for ownership.
* Should use operational names that make temporary purpose clear, such as
  `activity_streams_build`.

Silver:

* Should use canonical platform names.
* Should hide source-specific payload structure from consumers.
* Should include explicit units for measures.
* Should use positive boolean names.

Gold:

* Should use domain-oriented analytical names.
* Should prefer reusable product-neutral concepts over dashboard-specific names.
* Should make derived calculations explicit, including units and provenance.

Admin:

* Should use operational metadata names: run, phase, status, duration,
  counts, error, timeout, and timestamps.
* Should not contain business facts except maintained calculation inputs such
  as future FTP history.

### Units

Use British spelling consistently for metric units:

* `_metres`
* `_kilometres`
* `_metres_per_second`
* `_kilometres_per_hour`

Use conventional non-metric or domain unit suffixes where useful:

* `_miles`
* `_miles_per_hour`
* `_seconds`
* `_watts`
* `_bpm`
* `_rpm`
* `_pct`
* `_celsius`
* `_kilojoules`

Use `_pct` for platform-defined percentage fields, for example
`coverage_pct`, `completion_pct`, and `grade_pct`. Preserve existing
source-specific names such as `grade_smooth_percent` where renaming would
create unnecessary migration risk.

### Time and Dates

Use these names consistently:

* `activity_date`: business date for an activity or daily API response.
* `start_datetime_utc`: UTC activity start timestamp.
* `start_datetime_local`: local activity start timestamp.
* `start_date_local`: local activity date.
* `start_time_local`: local time of day.
* `created_at`: database row creation timestamp.
* `updated_at`: database row update timestamp.
* `retrieved_at`: source API retrieval timestamp.
* `transformed_at`: Silver transformation timestamp.
* `computed_at`: Gold calculation timestamp.
* `staged_at`: Stage row creation timestamp.
* `attempted_at`: ingestion attempt timestamp.
* `effective_from` / `effective_to`: validity windows for maintained inputs
  such as FTP history.
* `elapsed_time_seconds`: source-reported elapsed activity time.
* `moving_time_seconds`: source-reported moving activity time.
* `duration_seconds`: generic duration for runs, windows, efforts, and
  configured intervals.
* `elapsed_seconds`: measured execution time for validation/check helpers where
  the existing admin table already uses that name.

For Google Health Raw, `physical_time` and `civil_date` are acceptable as
source-preserved concepts. Silver should translate them into canonical
platform timestamp/date fields if those data become consumer-facing.

### Booleans

Use positive boolean names:

* `is_device_watts`
* `is_manual`
* `is_trainer`
* `is_moving`
* `has_streams`
* `has_details`
* `has_laps`
* `can_refresh` if capability flags are needed later

Avoid negative boolean names such as `is_not_valid`.

### Status Fields

Use `_status` suffixes for state fields:

* `run_status`
* `entity_status`
* `batch_status`
* `check_status`
* `stream_status`
* `details_status`
* `laps_status`
* `calculation_status`

Status values should remain uppercase enumerations documented in
`docs/status_values.md`.

### Derived Values

Use explicit analytical names:

* `average_power_watts`
* `weighted_average_power_watts`
* `normalized_power_watts`
* `variability_index`
* `intensity_factor`
* `training_stress_score`
* `ftp_watts_used`
* `work_kilojoules`

`weighted_average_power_watts` and `normalized_power_watts` should be treated
as distinct fields unless proven equivalent for a specific source. If Strava
provides `weighted_average_watts`, keep the promoted source-derived value as
`weighted_average_power_watts`. If the platform calculates Normalized Power,
write it as `normalized_power_watts` with calculation metadata.

Prefer American spelling for the specific domain term `normalized_power_watts`,
because "Normalized Power" is the established training metric name. Continue
using British spelling for physical distance units such as `metres`.

### Provenance and Calculation Metadata

Use:

* `source_id`
* `source_system`
* `source_object`
* `source_payload`
* `raw_payload`
* `calculation_status`
* `calculation_version`
* `computed_at`
* `sample_count`
* `coverage_pct`
* `completion_pct`
* `source_metric_name`
* `platform_metric_name`

Use `raw_*` prefixes in Silver/Gold only for lineage fields that explicitly
refer back to Raw, for example `raw_stream_retrieved_at`.

## Inventory and Findings

| Current name | File/object | Layer | Meaning | Source-preserved? | Recommended name | Migration risk | Classification |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `cycling_platform_admin` | `sql/install/001_create_databases.sql` | Admin | Operational metadata schema | No | Preserve | High | Preserve |
| `cycling_platform_stage` | `sql/install/001_create_databases.sql` | Stage | Temporary ETL workspace | No | Preserve | High | Preserve |
| `cycling_platform_raw` | `sql/install/001_create_databases.sql` | Raw | Source-retention schema | No | Preserve | High | Preserve |
| `cycling_platform_silver` | `sql/install/001_create_databases.sql` | Silver | Conformed data schema | No | Preserve | High | Preserve |
| `cycling_platform_gold` | `sql/install/001_create_databases.sql` | Gold | Analytical assets schema | No | Preserve | High | Preserve |
| `activities` | `sql/raw/010_create_strava_activities.sql`, `sql/silver/010_create_activities.sql` | Raw/Silver | Activity entity set | Mixed | Preserve | High | Preserve |
| `activity_streams` | Raw/Silver/Stage | Raw/Silver/Stage | Activity stream samples or stream payloads | Mixed | Preserve | High | Preserve |
| `activity_laps` | `sql/raw/040_create_strava_activity_laps.sql` | Raw | Strava lap payload rows | Yes | Preserve | Medium | Preserve |
| `activity_details` | `sql/raw/030_create_strava_activity_details.sql` | Raw | Strava detail payload row | Yes | Preserve | Medium | Preserve |
| `activity_streams_build` | `sql/stage/010_create_activity_streams_build.sql` | Stage | Temporary stream rebuild rows | No | Preserve for staging pattern | Low | Recommended |
| `google_health_heart_rate_responses` | `sql/raw/100_create_google_health_heart_rate_responses.sql` | Raw | One raw HR API response per user/date/detail level | Yes | Preserve for current raw object | Medium | Preserve |
| `google_health_sleep_logs` | `sql/raw/110_create_google_health_sleep_logs.sql` | Raw | Raw sleep log/session payloads | Yes | Preserve | Medium | Preserve |
| `fitbit_user_id` | HR raw table and R helpers | Raw | Google Health user id for Fitbit-origin HR data | Partly | Consider `google_health_user_id` in future Silver | Medium | Recommended |
| `google_user_id` | Sleep raw table and R helpers | Raw | Google Health user id for sleep data | Partly | Consider `google_health_user_id` in future Silver | Medium | Recommended |
| `dataset_interval` | HR raw table | Raw | Source response interval metadata | Yes | Preserve in Raw; use `dataset_interval_seconds` in Silver if unit confirmed | Low | Optional |
| `activity_date` | HR raw table/config/tests | Raw | Date-window business key | No | Preserve | Medium | Preserve |
| `source_log_id` | Sleep raw table | Raw | Provider sleep log identifier | Yes | Preserve | Low | Preserve |
| `start_physical_time` / `end_physical_time` | Sleep raw table | Raw | Google Health physical timestamps | Yes | Preserve in Raw; map to canonical timestamps in Silver | Medium | Preserve |
| `start_civil_date` / `end_civil_date` | Sleep raw table | Raw | Google Health civil dates | Yes | Preserve in Raw; map to canonical dates in Silver | Medium | Preserve |
| `start_datetime_utc` | Raw/Silver activities | Raw/Silver | UTC activity start timestamp | Platform-normalised | Preserve | High | Preserve |
| `start_datetime_local` | Raw/Silver activities | Raw/Silver | Local activity start timestamp | Platform-normalised | Preserve | High | Preserve |
| `start_time_local` | Silver activities | Silver | Local activity time of day | Platform-defined | Preserve | Medium | Preserve |
| `time_seconds` | Silver streams, Gold provenance | Silver/Gold | Stream sample elapsed time | Platform-defined | Preserve | High | Preserve |
| `duration_seconds` | Admin, validation, Gold best efforts | Admin/Gold | Run duration or effort window length | Platform-defined | Preserve | High | Preserve |
| `elapsed_seconds` | Validation run checks | Admin | Measured check execution time | Platform-defined | Preserve | Medium | Preserve |
| `distance_metres` | Activities/streams/gold | Raw/Silver/Gold | Distance in metres | Platform-normalised | Preserve | High | Preserve |
| `distance_kilometres` | Silver activities | Silver | Distance in kilometres | Platform-defined | Preserve | Medium | Preserve |
| `distance_miles` | Silver activities | Silver | Distance in miles | Platform-defined | Preserve | Medium | Preserve |
| `average_speed_metres_per_second` | Raw/Silver activities | Raw/Silver | Average speed | Platform-normalised | Preserve | High | Preserve |
| `velocity_smooth_metres_per_second` | Silver streams | Silver | Strava velocity stream | Source-derived | Preserve; source adjective is useful | High | Preserve |
| `grade_smooth_percent` | Silver streams | Silver | Strava grade stream | Source-derived | Preserve as an existing source-specific name; use `grade_pct` for new platform-derived grade fields | Medium | Preserve |
| `watts` | Silver streams, Gold metric name | Silver/Gold | Stream power samples | Source-derived | Preserve for stream column; consider `power_watts` only for future derived fields | High | Preserve |
| `average_power_watts` | Raw/Silver activities | Raw/Silver | Source activity average power | Source-derived | Preserve | High | Preserve |
| `weighted_average_power_watts` | Raw/Silver activities | Raw/Silver | Strava weighted average watts | Source-derived | Preserve; do not call NP unless calculated/verified | High | Preserve |
| `cadence_rpm` | Silver streams, Gold metric name | Silver/Gold | Cadence samples | Source-derived | Preserve | Medium | Preserve |
| `average_cadence_rpm` | Raw/Silver activities | Raw/Silver | Activity average cadence | Source-derived | Preserve | Medium | Preserve |
| `heartrate_bpm` | Silver streams, Gold metric name | Silver/Gold | HR samples | Source-derived | Preserve | Medium | Preserve |
| `average_heartrate_bpm` | Raw/Silver activities | Raw/Silver | Activity average HR | Source-derived | Preserve | Medium | Preserve |
| `temperature_celsius` | Silver streams | Silver | Temperature stream | Source-derived | Preserve | Medium | Preserve |
| `energy_kilojoules` | Raw/Silver activities | Raw/Silver | Source energy/work value | Source-derived | Preserve; future derived work should use `work_kilojoules` | Medium | Recommended |
| `metric_name` | Gold best efforts | Gold | Analytical metric identifier | Platform-defined | Preserve | High | Preserve |
| `peak_value` | Gold best efforts | Gold | Best rolling mean value | Platform-defined | Preserve for generic metric table | High | Preserve |
| `sample_count` | Gold best efforts | Gold | Samples used in calculation | Platform-defined | Preserve | Medium | Preserve |
| `computed_at` | Gold best efforts | Gold | Calculation timestamp | Platform-defined | Preserve | Medium | Preserve |
| `FTP used` | `docs/backlog.md`, `docs/gold_layer_design.md` | Docs/future Gold | FTP value used in activity metric calculations | No | `ftp_watts_used` | Low now, high after implementation | Required for future |
| `mean power` | `docs/backlog.md`, `docs/gold_layer_design.md` | Docs/future Gold | Average power | No | `average_power_watts` | Low now | Required for future |
| `normalised power` | `docs/backlog.md`, `docs/gold_layer_design.md` | Docs/future Gold | Normalized Power | No | `normalized_power_watts` | Low now | Required for future |
| `VI` | `docs/backlog.md`, `docs/gold_layer_design.md` | Docs/future Gold | Variability index | No | `variability_index` | Low now | Required for future |
| `IF` | `docs/backlog.md`, `docs/gold_layer_design.md` | Docs/future Gold | Intensity factor | No | `intensity_factor` | Low now | Required for future |
| `TSS` | `docs/backlog.md`, `docs/gold_layer_design.md` | Docs/future Gold | Training stress score | No | `training_stress_score` | Low now | Required for future |
| `moving_time` | `docs/data_quality_sql.md` | Docs | Old example name | No | `moving_time_seconds` | Low | Required documentation cleanup |
| `run_status`, `entity_status`, `batch_status`, `check_status` | Admin tables/R | Admin | Operational statuses | No | Preserve | High | Preserve |
| `stream_status`, `details_status`, `laps_status` | Raw activities | Raw | Child endpoint ingestion statuses | No | Preserve | High | Preserve |
| `has_streams`, `has_details`, `has_laps` | Silver activities | Silver | Child-data availability flags | No | Preserve | High | Preserve |
| `is_device_watts`, `is_manual`, `is_trainer`, `is_moving` | Raw/Silver | Raw/Silver | Positive boolean flags | Mixed | Preserve | High | Preserve |

## Layer-Specific Assessment

### Admin

Admin naming is consistent and operationally clear. The following families are
worth preserving:

* `etl_run`, `etl_run_entity`
* `transform_run`, `transform_run_batch`
* `validation_run`, `validation_run_check`
* `run_status`, `entity_status`, `batch_status`, `check_status`
* `duration_seconds`, `elapsed_seconds`

The one nuance is that `duration_seconds` is used for run and phase duration,
while validation checks use `elapsed_seconds`. That is acceptable because it is
already implemented and semantically clear enough. New admin objects should
prefer `duration_seconds` unless they are specifically check-level elapsed
timings.

### Stage

`cycling_platform_stage.activity_streams_build` follows the agreed staging
architecture:

* table name describes the temporary build target;
* `run_id` is mandatory;
* columns align with `silver.activity_streams`;
* `staged_at` clearly identifies staging lifecycle.

Future stage objects should use the same pattern:

```text
{target_entity}_build
```

with a mandatory `run_id` column rather than separate physical tables per run.

### Raw

Raw naming is intentionally closer to source contracts. This is acceptable.
Promoted columns in `raw.activities` are already clearer than raw Strava names:

* `average_watts` becomes `average_power_watts`;
* `weighted_average_watts` becomes `weighted_average_power_watts`;
* `device_watts` becomes `is_device_watts`;
* `kilojoules` becomes `energy_kilojoules`.

Google/Fitbit raw objects need future attention before Silver is built:

* HR uses `fitbit_user_id`.
* Sleep uses `google_user_id`.

Because the source is now Google Health but payloads are Fitbit-derived, the
recommended future Silver name is `google_health_user_id`, with optional
source-specific lineage fields retained in Raw.

### Silver

Silver naming is mostly canonical and consumer-friendly. It already uses:

* explicit units;
* positive boolean prefixes;
* local and UTC activity timestamp distinctions;
* lineage fields such as `raw_activity_retrieved_at` and
  `raw_stream_retrieved_at`.

Current stream metric columns should be preserved. Renaming `watts` to
`power_watts` would be clearer in isolation but expensive now because it is
used by Gold best efforts, validation, tests, and dashboard consumers. Use
`power_watts` only for future derived or calculated fields where ambiguity
matters.

### Gold

`gold.activity_best_efforts` has a good reusable grain and should be preserved.
The generic names `metric_name` and `peak_value` are appropriate because the
same table stores watts, cadence, and heart-rate efforts.

Future Gold work should avoid shorthand:

* do not create columns called `NP`, `VI`, `IF`, `TSS`, `ftp`, or
  `mean_power`;
* use `normalized_power_watts`, `variability_index`, `intensity_factor`,
  `training_stress_score`, `ftp_watts_used`, and `average_power_watts`.

Future Gold work should use specific object names rather than a generic
`activity_training_metrics` catch-all:

* `gold.activity_power_metrics`: one row per activity for power-specific
  calculations such as `average_power_watts`, `normalized_power_watts`,
  `variability_index`, and `work_kilojoules`.
* `gold.activity_training_load`: one row per activity for FTP-dependent load
  calculations such as `ftp_watts_used`, `intensity_factor`, and
  `training_stress_score`.
* `gold.ftp_history`: authoritative FTP timeline used by training-load
  calculations.

The authoritative FTP timeline should be maintained separately from activities.
If it is treated as maintained calculation input only, Admin is acceptable. If
dashboards, MCP resources, or coaching workflows consume it directly, publish a
consumer-facing Gold object.

## Future Product Fit

The proposed standard supports the intended future products:

Activity Catalogue:

* `silver.activities` already has clear identifiers, dates, flags, units, and
  activity descriptors.

Activity Performance:

* `gold.activity_best_efforts` has a durable grain and provenance fields.
* Metric names should remain explicit: `watts`, `cadence_rpm`,
  `heartrate_bpm`; future metrics should use unit suffixes.
* `gold.activity_power_metrics` should use explicit columns:
  `average_power_watts`, `normalized_power_watts`, `variability_index`,
  `work_kilojoules`, and `moving_time_seconds`.

Training Load:

* `gold.activity_training_load` should use explicit columns:
  `ftp_watts_used`, `intensity_factor`, `training_stress_score`, and
  calculation metadata.

Health and Recovery:

* Google/Fitbit Raw naming is sufficient for ingestion.
* Future Silver/Gold health objects should hide Google/Fitbit naming where
  possible and use platform concepts such as `sleep_start_datetime_utc`,
  `sleep_end_datetime_utc`, `heart_rate_bpm`, and `sample_datetime_utc`.

## Dependency Considerations

Before any rename, check:

* SQL DDL and transforms under `sql/`;
* R ingestion, database, validation, and transform modules under `R/`;
* runner scripts such as `platform.R`, `run_daily_platform.R`,
  `run_silver.R`, and `run_gold_activity_best_efforts.R`;
* tests under `tests/testthat/` and `tests/smoke_check.R`;
* shell scripts under `scripts/`;
* documentation under `docs/` and `README.md`;
* downstream `cycling-analytics` queries once that repository starts consuming
  platform objects;
* any MCP-facing code when MCP work resumes;
* historical rebuild and staging tooling.

Do not assume a column is unused because it appears in only one SQL file.
Several columns are read dynamically by R code, validation SQL, tests, or
future dashboard queries.

## Recommended Cleanup Backlog

### Required Before Power and Training Load Gold Objects

1. Keep Gold design documentation aligned to the standard names:
   `ftp_watts_used`, `average_power_watts`, `normalized_power_watts`,
   `variability_index`, `intensity_factor`, and
   `training_stress_score`.
2. Design specific objects rather than a generic
   `gold.activity_training_metrics` table. Current target names are
   `gold.activity_power_metrics`, `gold.activity_training_load`, and
   `gold.ftp_history`.
3. Decide whether authoritative FTP history is maintained in Admin, Gold, or
   both as input-plus-publication.
4. Add the naming standard to future Gold DDL review checklists.

### Recommended Before Health Silver

1. Choose canonical Google Health user naming for conformed layers:
   `google_health_user_id` is recommended.
2. Keep `fitbit_user_id` and `google_user_id` only in Raw or lineage fields.
3. Decide whether `dataset_interval` needs `_seconds` once the unit is
   confirmed.
4. Define Silver health timestamp names before exposing health data to
   consumers.

### Documentation Cleanup

1. Fix stale examples in `docs/data_quality_sql.md`, especially `moving_time`
   to `moving_time_seconds`.
2. Add this naming standard to `docs/platform_principles.md` or link this file
   from that page.
3. Keep legacy names documented only as legacy source examples.

### Optional Future Renames

These should not be done casually:

* `watts` to `power_watts` in `silver.activity_streams`.
* `peak_value` to metric-specific columns in `gold.activity_best_efforts`.
* `duration_seconds` to more specific run/window variants.

All three are currently stable and useful enough to preserve.

## Decision

Adopt this standard for new work immediately. Do not perform broad schema
renames now. The highest-value next step is to apply the standard to the
upcoming `activity_power_metrics`, `activity_training_load`, and `ftp_history`
designs before those objects become real dependencies.
