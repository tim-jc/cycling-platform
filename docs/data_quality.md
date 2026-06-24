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
* Child rows have matching parent activities.
* Raw child tables contain no orphaned records.

### Payload Checks

* `raw.activities.raw_payload` contains valid JSON.
* `raw.activity_streams.stream_payload` contains valid JSON.
* `raw.activity_details.details_payload` contains valid JSON.
* Payload columns are not empty strings.
* Stream payload checksums are stable across repeated ingestion when the source
  payload has not changed.

### Payload Integrity Checks

Checksum validation can detect unexpected payload changes, partial writes, or
serialization drift.

Initial checksum candidates:

* checksum of `raw.activity_streams.stream_payload`
* checksum of `raw.activity_details.details_payload`
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
* `stream_status = 'NOT_FOUND'` should have no matching stream rows unless a
  later source response has changed the outcome.
* `details_status = 'NOT_FOUND'` should have no matching detail row unless a
  later source response has changed the outcome.
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

* `NOT_FOUND_EXPECTED`: metadata indicates streams or details are not expected.
* `NOT_FOUND_UNEXPLAINED`: activity appears to have source/device data, but the
  child endpoint returned no payload.

The raw ingestion status can remain `NOT_FOUND`; the classification can live in
data quality results or later curated metadata.

### Lineage Checks

* Every raw row has `run_id`, `source_id`, and `retrieved_at`.
* Every `run_id` exists in `admin.etl_run`.
* Every `source_id` exists in `admin.data_source`.
* Entity run counts reconcile with inserted and updated rows where practical.

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
4. stream and detail payload checksum drift
5. promoted raw columns that do not match source payload values
6. status fields that do not match child table data
7. stale `PENDING` statuses
8. unexplained `NOT_FOUND` statuses
9. recent failed entity runs

Possible implementation:

* `R/quality/check_raw_<entity>.R`
* `R/quality/run_data_quality_checks.R`
* `R/quality/report_raw_status.R`
* `admin.data_quality_check`
* `admin.data_quality_check_result`

Results should eventually be included in notifications so routine automation
surfaces problems without manual database inspection.

Initial SQL sketches are captured in `docs/data_quality_sql.md`.

## Open Questions

* Should raw data quality failures fail the whole platform run, or warn only?
* Which checks are blockers for automation on the Raspberry Pi?
* Should check results live in `admin`, or in a separate metadata schema?
* Should historical backfill checks use different thresholds from routine runs?
