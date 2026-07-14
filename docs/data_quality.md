# Data Quality

## Purpose

Data quality checks should make ingestion failures, source anomalies, and
modelling assumptions visible without adding unnecessary transformation logic to
the raw layer.

The raw layer preserves Strava source fidelity. Data quality checks should
therefore focus first on completeness, keys, payload validity, lineage, and
ingestion status. Business interpretation belongs mostly in silver and gold.

## Principles

* Check source fidelity before derived correctness.
* Prefer small, repeatable checks over broad manual inspection.
* Record failures with enough context to support reruns.
* Keep raw checks close to ingestion and lineage.
* Push coaching and analytics assumptions into curated layers.

## Raw Layer Checks

### Structural Checks

* Required raw tables exist.
* Expected primary keys and indexes exist.
* Expected payload columns exist and are non-null.
* Foreign keys to admin metadata are valid.

### Key Checks

* `raw.activities.activity_id` is unique.
* `raw.activity_streams` is unique by `activity_id`, `stream_type`.
* `raw.activity_details.activity_id` is unique.
* `raw.activity_laps` is unique by `activity_id`, `lap_index`.
* `raw.google_health_daily_resting_heart_rate` is unique by
  `daily_resting_heart_rate_key`.
* `raw.google_health_daily_heart_rate_variability` is unique by
  `daily_heart_rate_variability_key`.
* `raw.google_health_daily_respiratory_rate` is unique by
  `daily_respiratory_rate_key`.
* Google Health daily RHR/HRV/respiratory-rate may legitimately contain
  multiple rows per user and date when Google Health returns multiple source
  ecosystems such as `FITBIT` and `HEALTH_KIT`.
* Google Health daily RHR/HRV/respiratory-rate provenance columns should expose
  `source_ecosystem`, `source_platform` and `source_recording_method` where the
  payload provides them.
* Google Health daily RHR/HRV/respiratory-rate duplicate checks must use the
  source data-point grain, not `google_health_user_id + activity_date`.
  Same-day Apple Health and Fitbit observations are valid Raw records.
* Child rows have matching parent activities.
* Raw child tables contain no orphaned records.

### Payload Checks

* `raw.activities.raw_payload` contains valid JSON.
* `raw.activity_streams.stream_payload` contains valid JSON.
* `raw.activity_details.details_payload` contains valid JSON.
* `raw.activity_laps.lap_payload` contains valid JSON.
* `raw.google_health_daily_resting_heart_rate.daily_resting_heart_rate_payload`
  contains valid JSON.
* `raw.google_health_daily_heart_rate_variability.daily_heart_rate_variability_payload`
  contains valid JSON.
* `raw.google_health_daily_respiratory_rate.daily_respiratory_rate_payload`
  contains valid JSON.
* `raw.google_health_sleep_logs.sleep_log_payload` contains valid JSON and may
  include source-reported stage arrays and stage summaries.
* Payload columns are not empty strings.
* Stream payload checksums are stable across repeated ingestion when the source
  payload has not changed.
* Stream `latlng` payloads retain source numeric precision and are not rounded
  by JSON serialization.

### Known Payload Issue: Stream Coordinate Precision

Historical `raw.activity_streams` payloads loaded before the stream JSON
serialization fix have insufficient coordinate precision. `jsonlite::toJSON()`
was previously called without `digits = NA`, so values such as `53.196583`
could be stored as `53.1966`.

The production serializer now preserves full numeric precision for newly loaded
stream payloads. Existing raw stream data should be fully reloaded from Strava
before map views, route matching, or other location-sensitive outputs are
treated as reliable.

Near-term quality checks should flag suspicious `latlng` values that appear to
have only four decimal places, and should separately record whether a full raw
stream reload has been completed after the precision fix.

### Payload Integrity Checks

Checksum validation can detect unexpected payload changes, partial writes, or
serialization drift.

Initial checksum candidates:

* checksum of `raw.activity_streams.stream_payload`
* checksum of `raw.activity_details.details_payload`
* checksum of `raw.activity_laps.lap_payload`
* optional checksum of `raw.activities.raw_payload`

The checksum should be computed from a canonical representation of the payload.
If checksums are computed from raw JSON text, formatting or key-order changes
can produce false positives. For stream arrays this is less risky, but activity
and detail payloads may need canonical JSON before checksums are reliable.

### Promoted Column Reconciliation Checks

Promoted raw columns are convenient cached extracts from source payloads. They
should therefore reconcile back to the corresponding JSON values wherever the
relationship is direct.

Examples:

* `raw.activities.activity_id` should match `raw_payload.id`.
* `raw.activities.sport_type` should match `raw_payload.sport_type`.
* promoted distance, duration, elevation, and speed fields should match their
  equivalent payload fields after type conversion.
* `raw.activity_details.activity_id` should match `details_payload.id`.

If a promoted column and payload value disagree, curated layers should treat the
payload as authoritative and the mismatch should be surfaced as a data quality
failure. These checks protect the silver-layer rule that promoted columns may be
used for efficiency only when they remain equivalent to the source payload.

### Completeness Checks

* Activities in scope for a run are loaded.
* Activities requiring streams are not left indefinitely `PENDING`.
* Activities requiring details are not left indefinitely `PENDING`.
* Activities requiring laps are not left indefinitely `PENDING`.
* `FAILED` statuses are visible and recoverable.
* `NOT_FOUND` statuses are reconciled against activity metadata to distinguish
  expected source behaviour from suspicious gaps.
* Status fields reconcile to the actual presence or absence of child data.

### Status Reconciliation Checks

Status fields on `raw.activities` are operational metadata and should be
validated against raw child tables.

Examples:

* `stream_status = 'SUCCESS'` should have at least one matching row in
  `raw.activity_streams`.
* `details_status = 'SUCCESS'` should have one matching row in
  `raw.activity_details`.
* `laps_status = 'SUCCESS'` should have at least one matching row in
  `raw.activity_laps`, unless Strava returns a valid empty lap collection.
* `stream_status = 'NOT_FOUND'` should have no matching stream rows unless a
  later source response has changed the outcome.
* `details_status = 'NOT_FOUND'` should have no matching detail row unless a
  later source response has changed the outcome.
* `laps_status = 'NOT_FOUND'` should have no matching lap rows unless a later
  source response has changed the outcome.
* `PENDING` records should not have complete child data unless status updates
  failed after a successful load.

These checks are useful even when foreign keys exist because they catch
operational drift, manual deletions, interrupted maintenance, and inconsistent
reruns.

### Not Found Reconciliation

`NOT_FOUND` should record the source/API outcome. Data quality checks should
then classify whether that outcome is expected.

Expected `NOT_FOUND` cases may include:

* manually entered activities
* activities without an upload/device source
* sport types or activity types that do not support streams
* source records where Strava exposes summary metadata but not child payloads

Useful activity metadata for reconciliation may include:

* `manual` from `raw_payload`
* `upload_id` from `raw_payload`
* `device_name` from `raw_payload`
* `sport_type`
* `trainer`
* visibility or privacy fields, if present

Near-term classifications:

* `NOT_FOUND_EXPECTED`: metadata indicates streams, details, or laps are not
  expected.
* `NOT_FOUND_UNEXPLAINED`: activity appears to have source/device data, but the
  child endpoint returned no payload.

The raw ingestion status can remain `NOT_FOUND`; the classification can live in
data quality results or later curated metadata.

### Lineage Checks

* Every raw row has `run_id`, `source_id`, and `retrieved_at`.
* Every `run_id` exists in `admin.etl_run`.
* Every `source_id` exists in `admin.data_source`.
* Entity run counts reconcile with inserted and updated rows where practical.
* Successful empty Google Health daily requests are represented in
  `admin.etl_request_log`, not as placeholder Raw metric rows.

### Freshness Checks

* Latest successful platform run completed within the expected schedule window.
* Latest activity retrieval time is recent for routine ingestion.
* Historical backfills have no unexpected long-term `PENDING` or `FAILED`
  statuses.

## Silver Layer Checks

Silver checks should validate curated, conformed entities.

Potential checks:

* required dimensions and facts are populated
* timestamps are consistently normalised
* distance, duration, elevation, and power fields have sensible units
* activity type mappings are complete
* derived fields are reproducible from raw payloads
* one source activity maps to one curated activity

## Gold Layer Checks

Gold checks should validate analytics-ready models.

## Completeness Validation

The platform includes a reusable completeness validation suite. It is split into
two operational scopes.

### Publication Gate

The publication gate is blocking and runs inside `run_daily_platform.R` after
Silver transforms:

```sh
Rscript run_daily_platform.R
```

It contains only fast checks required before downstream consumers should treat
the refreshed Silver layer as published:

* Raw activities must exist in `silver.activities`.
* Silver activities with `has_streams = 1` must have Silver stream rows.

If these checks fail, daily automation exits non-zero.

### Deep Validation

Deep validation is asynchronous and should be scheduled separately:

```sh
Rscript run_platform_validation.R
```

For Raw/Silver-only validation:

```sh
Rscript run_platform_validation.R --silver-only
```

For compatibility, `Rscript validate_platform.R` delegates to the same runner.

Deep validation preserves the full completeness suite and checks that records do
not disappear unexpectedly across layer boundaries:

* Raw activities must exist in `silver.activities`.
* Raw and Silver activity counts must match.
* Silver activities with `has_streams = 1` must have Silver stream rows.
* Silver stream rows must have parent Silver activities.
* Silver stream `activity_id` and `sample_index` keys must be unique.
* Raw activities with `stream_status = 'SUCCESS'` and raw stream payloads must
  have Silver stream rows.
* Raw stream expected sample counts must agree with Silver stream row counts.
* Google Health daily RHR, daily HRV and daily respiratory-rate Raw rows must
  have required lineage, valid dates, non-null payloads, positive RHR and
  respiratory-rate values, and non-negative HRV values where present.
* Google Health daily RHR, daily HRV and daily respiratory-rate Raw rows are
  checked for duplicate source-grain records using source identifiers, promoted
  provenance and payload hash fallback.
* Dates containing multiple source ecosystems are reported as INFO diagnostics.
  They are expected when Apple Health and Fitbit both contribute observations.
* Missing or unknown Google Health source provenance is reported as a warning so
  future Silver transforms do not silently lose source context.
* Google Health daily request failures and successful empty responses are
  visible through `admin.etl_request_log`.
* Google Health sleep-stage metadata is checked against retained sleep payload
  indicators where promoted columns are populated.
* Google Health RHR/HRV/sleep date overlap is diagnostic only. Current live
  inspection shows sleep payloads are present but promoted sleep interval dates
  are null, so overlap warnings can indicate missing sleep metadata rather than
  missing sleep ingestion.
* Gold publication checks must confirm required Gold transforms are successful
  and fresh before deep Gold completeness checks run.
* `gold.activity_best_efforts` must contain expected watts, cadence, and
  heartrate rows where the source Silver streams support them.
* Gold best-effort keys, peak values, sample counts, window ordering, and GPS
  provenance are validated.

Critical publication-gate failures cause `run_daily_platform.R` to exit with a
non-zero status. Critical deep-validation failures cause
`run_platform_validation.R` to exit non-zero, but they do not roll back or hide a
successful Silver transform.

Deep-validation warnings do not make the scheduled validation process fail.
Instead, the validation outcome is recorded as `PASSED_WITH_WARNINGS` and an
attention notification is sent when `notifications.validation_notify_on_warning`
is enabled. This keeps cron exit-code behaviour stable while avoiding manual log
inspection for warning-only validation runs.

Both scopes record status and timing in:

* `cycling_platform_admin.validation_run`
* `cycling_platform_admin.validation_run_check`

Use these tables to inspect validation freshness, failure status, timed-out
checks, and the slowest checks from recent runs.

Common failures:

* Raw activity missing from Silver usually means the Silver activity transform
  did not run after ingestion.
* Raw/Silver stream count mismatch usually means the Silver stream repair
  transform should be rerun.
* Stale Gold publication checks usually mean the daily Gold transform failed or
  did not run after Silver streams were refreshed.
* Missing Gold best-effort rows after a successful Gold publication usually
  means `Rscript run_gold_activity_best_efforts.R repair` should be run and the
  failing activities inspected for sparse or missing metric samples.

Potential checks:

* weekly and monthly aggregates reconcile to silver activity totals
* training load measures are non-negative
* equipment mileage reconciles to activity distances
* coaching summaries exclude unsupported or incomplete activities
* dashboard-facing models have expected date coverage

## Implementation Direction

Start with lightweight SQL-backed checks that can run after ingestion.

Near-term checks:

1. duplicate business keys
2. child rows without parent activities
3. invalid or empty payloads
4. stream, detail, and lap payload checksum drift
5. stream coordinate precision checks
6. promoted raw columns that do not match source payload values
7. status fields that do not match child table data
8. stale `PENDING` statuses
9. unexplained `NOT_FOUND` statuses
10. recent failed entity runs

Possible implementation:

* `R/quality/check_raw_<entity>.R`
* `R/quality/run_data_quality_checks.R`
* `R/quality/report_raw_status.R`
* `admin.data_quality_check`
* `admin.data_quality_check_result`

Validation results are surfaced through automation notifications. Fatal
validation failures produce failure notifications; non-fatal warning outcomes
produce attention notifications with affected check names, issue counts and
sample rows.

Initial SQL sketches are captured in `docs/data_quality_sql.md`.

## Open Questions

* Should raw data quality failures fail the whole platform run, or warn only?
* Which checks are blockers for automation on the Raspberry Pi?
* Should check results live in `admin`, or in a separate metadata schema?
* Should historical backfill checks use different thresholds from routine runs?
