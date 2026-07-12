# Google Health Silver Design Proposal

## Status

Proposal only. Do not implement until reviewed.

## Purpose

Define the first deliberately small Google Health / Fitbit Silver layer for
`cycling-platform`, based on the Raw implementation that exists today.

The aim is not to design a complete health model. The first Silver pass should
make the current Raw heart-rate and sleep data usable by downstream analytics
without creating a large backlog of derived health metrics.

## Current Raw Implementation

### Implemented Raw Entities

#### `cycling_platform_raw.google_health_heart_rate_responses`

Evidence:

* DDL: `sql/raw/100_create_google_health_heart_rate_responses.sql`
* API shaping: `R/api/get_google_health_data_points.R`
* API wrapper: `R/api/get_google_health_heart_rate.R`
* ingestion orchestration: `R/ingestion/ingest_google_health_heart_rate.R`
* DB helpers: `R/database/upsert_google_health_data_points.R`
* tests: `tests/testthat/test-google-health-data-points.R`

Current grain:

* one row per Google/Fitbit heart-rate API response per
  `source_id`, `fitbit_user_id`, `activity_date`, and `detail_level`

Business key:

* `source_id`
* `fitbit_user_id`
* `activity_date`
* `detail_level`

Stored payload:

* `heart_rate_payload` JSON

The payload is a wrapper object created by the platform:

* `data_type`
* `filter`
* `page_count`
* `pages`

Each page may contain Google Health `dataPoints`. Test payloads show heart-rate
samples under paths like:

```text
heartRate.beatsPerMinute
heartRate.sampleTime.physicalTime
heartRate.sampleTime.utcOffset
dataSource.name
name
```

Current typed metadata:

* `source_id`
* `fitbit_user_id`
* `activity_date`
* `detail_level`
* `run_id`
* `retrieved_at`
* `dataset_interval`

Notes:

* `dataset_interval` is currently populated as `NA`.
* The current raw table stores response-grain rows, not one raw row per sample.
* The helper names still include `data_points`, but the physical table is
  response-grain.

#### `cycling_platform_raw.google_health_sleep_logs`

Evidence:

* DDL: `sql/raw/110_create_google_health_sleep_logs.sql`
* API shaping: `R/api/get_google_health_sleep_logs.R`
* ingestion orchestration: `R/ingestion/ingest_google_health_sleep_logs.R`
* DB helpers: `R/database/upsert_google_health_sleep_logs.R`
* tests: `tests/testthat/test-google-health-sleep-logs.R`

Current grain:

* one row per Google Health sleep log/session where available

Business key:

* `sleep_log_key`

Stored payload:

* `sleep_log_payload` JSON

Current typed metadata:

* `sleep_log_key`
* `source_log_id`
* `google_user_id`
* `run_id`
* `source_id`
* `retrieved_at`
* `source_name`
* `start_physical_time`
* `end_physical_time`
* `start_utc_offset`
* `end_utc_offset`
* `start_civil_date`
* `end_civil_date`

Test payloads show sleep interval values under paths like:

```text
sleep.interval.startTime.physicalTime
sleep.interval.endTime.physicalTime
sleep.interval.startTime.utcOffset
sleep.interval.endTime.utcOffset
sleep.interval.startTime.civilTime.date
sleep.interval.endTime.civilTime.date
```

### Current Orchestration

Google Health raw ingestion is called from `platform.R` after Strava child
entities when Google Health is enabled.

Routine refresh windows:

* `ingestion.google_health_refresh_days`
* `ingestion.google_health_sleep_refresh_days`

Backfill windows:

* `ingestion.google_health_backfill_days`
* `ingestion.google_health_sleep_backfill_days`

Date batching:

* `ingestion.google_health_date_batch_size`

## Data Available Today

Available from current Raw:

* heart-rate samples in `heart_rate_payload`
* heart-rate sample timestamps in the payload
* source data-point names in the payload
* heart-rate source names in the payload
* one row per sleep session/log
* sleep session start and end timestamps as promoted Raw columns
* sleep source names as promoted Raw columns
* sleep local/civil dates as promoted Raw columns

Not currently available as implemented Raw entities:

* HRV
* resting heart rate
* respiratory rate
* oxygen saturation
* skin temperature
* sleep stages, unless present in the retained sleep payload but not yet
  understood or promoted
* daily health summaries
* readiness/recovery scores

The older design document mentions HRV, resting heart rate, oxygen saturation
and other health metrics as possible future data types, but `config/platform.yml`
currently enables only:

```yaml
sources:
  google_health:
    data_types:
      - heart-rate
      - sleep
```

## Source-Reported vs Calculated Metrics

### Source-Reported / Source-Derived

These can be represented in Silver because they are direct source values or
minimal normalisations:

* `heart_rate_bpm`
* `sample_datetime_utc`
* `sample_utc_offset`
* `source_data_point_id`
* `source_name`
* `sleep_start_datetime_utc`
* `sleep_end_datetime_utc`
* `sleep_start_utc_offset`
* `sleep_end_utc_offset`
* `sleep_start_civil_date`
* `sleep_end_civil_date`
* `sleep_duration_seconds`, calculated directly from source start/end times

`sleep_duration_seconds` is acceptable in Silver because it is a deterministic
normalisation of source timestamps, not an analytical score.

### Calculated / Derived

These should not be part of the first Silver implementation:

* resting heart rate
* HRV
* daily average heart rate
* sleep score
* sleep efficiency
* sleep regularity
* recovery/readiness metrics
* rolling baselines
* training-load interpretations using sleep or heart rate

These belong in Gold or require additional Raw ingestion first.

## Naming Decisions

Follow `docs/naming-consistency-review.md`.

Apply these conventions:

* Use `snake_case`.
* Use British physical unit spelling where relevant.
* Use `_bpm` for heart rate.
* Use `_seconds` for durations.
* Use `_pct` for future platform-defined percentages.
* Use `google_health_user_id` in Silver, even though Raw currently has both
  `fitbit_user_id` and `google_user_id`.
* Preserve Raw source-specific names only as lineage fields where useful.

## Recommended First Silver Tables

Build only two Silver tables initially:

1. `cycling_platform_silver.health_heart_rate_samples`
2. `cycling_platform_silver.health_sleep_sessions`

Do not build daily summaries yet. Do not build HRV, resting heart rate or
recovery objects until the Raw layer actually ingests those inputs.

## Table 1: `silver.health_heart_rate_samples`

### Purpose

Expose one row per heart-rate sample without requiring consumers to parse raw
Google Health response JSON.

### Source

`cycling_platform_raw.google_health_heart_rate_responses`

### Grain

One row per Google Health heart-rate sample.

### Business Key

Recommended primary key:

```text
heart_rate_sample_key
```

Construct as a deterministic hash from:

* `source_id`
* `google_health_user_id`
* source data-point name if present
* `sample_datetime_utc`
* `heart_rate_bpm`
* `source_name`

Use the source data-point name as the strongest natural identifier where
present. Include timestamp/value/source fallback material because the Raw table
is response-grain and does not currently promote a sample-level key.

### Proposed Columns

Identifiers:

* `heart_rate_sample_key CHAR(64) NOT NULL`
* `source_id INT NOT NULL`
* `google_health_user_id VARCHAR(100) NOT NULL`
* `source_data_point_id VARCHAR(500) NULL`
* `source_name TEXT NULL`

Time:

* `sample_datetime_utc DATETIME NOT NULL`
* `sample_utc_offset VARCHAR(32) NULL`
* `sample_date_utc DATE NOT NULL`
* `sample_date_local DATE NULL`

Measures:

* `heart_rate_bpm INT NOT NULL`

Raw lineage:

* `raw_activity_date DATE NOT NULL`
* `raw_detail_level VARCHAR(100) NOT NULL`
* `raw_response_key CHAR(64) NOT NULL`
* `raw_retrieved_at DATETIME NOT NULL`
* `transformed_at DATETIME NOT NULL`

Indexes:

* primary key on `heart_rate_sample_key`
* index on `sample_datetime_utc`
* index on `sample_date_local`
* index on `raw_response_key`

### Notes

`raw_response_key` should be a deterministic hash of the Raw response natural
key:

```text
source_id + google_health_user_id + raw_activity_date + raw_detail_level
```

This gives the transform a stable delete/repair target without altering the
Raw table.

## Table 2: `silver.health_sleep_sessions`

### Purpose

Expose one row per sleep session/log with canonical timestamp and duration
fields.

### Source

`cycling_platform_raw.google_health_sleep_logs`

### Grain

One row per sleep session/log.

### Business Key

Recommended primary key:

```text
sleep_session_key
```

Use Raw `sleep_log_key` directly as `sleep_session_key`.

### Proposed Columns

Identifiers:

* `sleep_session_key CHAR(64) NOT NULL`
* `source_id INT NOT NULL`
* `google_health_user_id VARCHAR(100) NOT NULL`
* `source_log_id VARCHAR(500) NULL`
* `source_name TEXT NULL`

Time:

* `sleep_start_datetime_utc DATETIME NOT NULL`
* `sleep_end_datetime_utc DATETIME NOT NULL`
* `sleep_start_utc_offset VARCHAR(32) NULL`
* `sleep_end_utc_offset VARCHAR(32) NULL`
* `sleep_start_civil_date DATE NULL`
* `sleep_end_civil_date DATE NULL`
* `sleep_duration_seconds INT NOT NULL`

Raw lineage:

* `raw_retrieved_at DATETIME NOT NULL`
* `transformed_at DATETIME NOT NULL`

Indexes:

* primary key on `sleep_session_key`
* index on `sleep_start_datetime_utc`
* index on `sleep_end_datetime_utc`
* index on `sleep_start_civil_date`

### Notes

The first implementation should not infer sleep date, sleep stages, sleep
quality or nightly summaries. Those are either Gold concerns or require more
evidence from actual sleep payloads.

## Silver vs Gold Boundary

### Belongs In Silver

* JSON unpacking from implemented Raw payloads
* canonical timestamps and dates
* canonical user identifier naming
* direct source values with units
* deterministic source-key hashes
* deterministic source interval duration
* Raw lineage fields needed for repair and validation

### Defer To Gold

* daily sleep summaries
* daily heart-rate summaries
* resting heart rate
* HRV
* sleep regularity
* sleep efficiency
* recovery/readiness features
* trend and rolling-window metrics
* joins to Strava activities or training load

## Incremental Transform Strategy

### Heart Rate

Use response-level repair.

1. Identify Raw heart-rate response rows whose response natural key is missing
   from Silver, has mismatched sample counts, or has `updated_at` newer than
   the last corresponding Silver `transformed_at`.
2. For each selected Raw response:
   * parse `heart_rate_payload`;
   * flatten all `pages[].dataPoints[]`;
   * build `health_heart_rate_samples` rows;
   * start a transaction;
   * delete existing Silver rows for that `raw_response_key`;
   * insert rebuilt rows;
   * commit.
3. Record transform run and batch metadata in Admin, consistent with existing
   Silver transform logging.

The transform should be idempotent because each selected Raw response deletes
and rebuilds only its own sample set.

### Sleep

Use session-level repair.

1. Identify Raw sleep logs whose `sleep_log_key` is missing from Silver or
   whose Raw `updated_at` is newer than Silver `transformed_at`.
2. For each selected sleep log:
   * map promoted Raw columns to canonical Silver names;
   * calculate `sleep_duration_seconds`;
   * upsert or delete/insert by `sleep_session_key`.

Because sleep rows are already Raw session-grain, the Silver transform should
be much simpler than heart-rate sample expansion.

## Repair Strategy

Manual repair modes should support:

* all Raw Google Health rows;
* one date range;
* selected `raw_response_key` values for heart-rate;
* selected `sleep_session_key` values for sleep.

For heart rate, prefer delete-and-reinsert by `raw_response_key`. For sleep,
prefer upsert by `sleep_session_key`.

Do not use the historical Silver stream staging repair path for this first
implementation. Current Google Health volumes are much smaller than Strava
streams and should not require staging unless real runtimes prove otherwise.

## Validation Approach

### Publication Gate

Do not add Google Health Silver checks to the daily publication gate at first.
Current downstream consumers are cycling dashboards, and Google Health Silver
will initially be exploratory.

### Deep Validation

Add Google Health checks to deep validation once the Silver tables exist.

Heart-rate checks:

* every Raw response has matching Silver rows unless the payload contains zero
  data points;
* no duplicate `heart_rate_sample_key`;
* `heart_rate_bpm` is non-null and positive;
* `sample_datetime_utc` is non-null;
* Silver row count per `raw_response_key` matches parsed Raw data-point count;
* `raw_retrieved_at` and `transformed_at` are populated.

Sleep checks:

* every Raw sleep log has one Silver sleep session;
* no duplicate `sleep_session_key`;
* start and end timestamps are populated;
* `sleep_end_datetime_utc >= sleep_start_datetime_utc`;
* `sleep_duration_seconds > 0`;
* `raw_retrieved_at` and `transformed_at` are populated.

Warnings, not failures:

* missing local/civil dates;
* missing source names;
* unusually long or short sleep sessions;
* unusually low or high heart-rate values.

## Raw Gaps Identified

These should not block the first Silver implementation, but they should be
tracked:

1. HRV and resting heart rate are not currently ingested.
2. Heart-rate Raw rows do not promote source sample counts.
3. Heart-rate Raw rows do not promote a response key; Silver can compute one
   without changing Raw.
4. Heart-rate `dataset_interval` is currently always `NA`.
5. Sleep Raw may contain richer sleep-stage data in payloads, but the current
   implementation only promotes session/log interval metadata.
6. There is no Google Health date-level ingestion status table. Idempotent
   upsert mitigates this for now, but status tracking may be useful if Google
   Health becomes operationally important.
7. The older Google Health design document still describes a generic
   `google_health_data_points` Raw table, but implementation now uses a
   heart-rate-specific response-grain table.

## Implementation Sequence

Recommended first implementation:

1. Create DDL for `silver.health_sleep_sessions`.
2. Implement and validate the sleep transform first. It is simpler and tests
   the Google Health Silver pattern.
3. Create DDL for `silver.health_heart_rate_samples`.
4. Implement response-level heart-rate JSON flattening in R.
5. Add focused tests using existing test payloads.
6. Add deep validation checks.
7. Leave daily summaries, RHR, HRV and recovery metrics out of scope.

## Open Questions

1. Should `google_health_user_id` be the only Silver user identifier, or should
   Silver retain source-specific `fitbit_user_id` / `google_user_id` lineage
   columns as well?
2. Should `heart_rate_bpm` values outside a plausible physiological range be
   warnings only, or should extreme values fail validation?
3. Do real sleep payloads include stage-level data that should become a third
   Silver table later, such as `health_sleep_stages`?
4. Should Gold daily health summaries be built inside `cycling-platform`, or
   should some exploratory health analysis initially live in
   `cycling-analytics` until the model stabilises?

## Recommendation

Proceed with two Silver tables only:

```text
cycling_platform_silver.health_sleep_sessions
cycling_platform_silver.health_heart_rate_samples
```

Implement sleep first, then heart rate. Defer HRV, RHR, daily summaries and
recovery metrics until additional Raw endpoints exist or downstream analytic
requirements become concrete.
