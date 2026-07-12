# Google Health Raw Expansion Proposal

Status: Raw expansion implemented for daily resting heart rate, daily HRV and
sleep-stage metadata. Do not implement Silver for Google Health until these Raw
objects have been exercised through routine runs.

## Purpose

Establish whether Google Health can provide source-reported recovery inputs
that are worth adding to the Raw layer:

1. daily resting heart rate
2. daily heart-rate variability
3. richer sleep detail, especially sleep stages
4. intraday heart-rate variability, only if it adds clear value

The architectural rule is:

* source-reported RHR, HRV and sleep-stage data belong in Raw and then Silver;
* baselines, trends, deviations, readiness and recovery scores belong in Gold.

## Repository Baseline

There is no `docs/standards/` directory at the time of writing. This proposal
therefore applies the current platform standards from:

* `docs/raw_entity_pattern.md`
* `docs/ingestion_patterns.md`
* `docs/platform_principles.md`
* `docs/naming-consistency-review.md`

Current Google Health / Fitbit Raw implementation:

| Area | Current implementation |
| --- | --- |
| Config | `config/platform.yml`, `sources.google_health` |
| Enabled data types | `heart-rate`, `sleep` |
| API base URL | `https://health.googleapis.com/v4` |
| OAuth helper | `R/api/get_google_health_access_token.R` |
| Request helper | `R/api/perform_google_health_request.R` |
| HR API wrapper | `R/api/get_google_health_heart_rate.R` |
| Generic data-point helper | `R/api/get_google_health_data_points.R` |
| Sleep API wrapper | `R/api/get_google_health_sleep_logs.R` |
| HR ingestion | `R/ingestion/ingest_google_health_heart_rate.R` |
| Sleep ingestion | `R/ingestion/ingest_google_health_sleep_logs.R` |
| HR Raw table | `cycling_platform_raw.google_health_heart_rate_responses` |
| Sleep Raw table | `cycling_platform_raw.google_health_sleep_logs` |
| Tests | `tests/testthat/test-google-health-data-points.R`, `tests/testthat/test-google-health-sleep-logs.R`, `tests/testthat/test-google-health-auth.R` |

`platform.R` already runs Google Health HR and sleep ingestion when
`sources.google_health.enabled` is true and the execution mode is not
`streams_only`.

## Current OAuth Position

The current Google Health design and auth flow require:

* `https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly`
* `https://www.googleapis.com/auth/googlehealth.sleep.readonly`

These scopes should be sufficient for the proposed Raw expansion:

* health metrics scope: heart rate, daily resting heart rate, daily HRV and
  intraday HRV;
* sleep scope: sleep sessions and sleep stages.

Capability probe findings from 2026-07-11:

* daily resting heart rate returned one row per day for the tested week;
* daily HRV returned one row per day for the tested week;
* daily HRV included average HRV and deep-sleep RMSSD;
* sleep payloads included `sleep.stages[]`, stage summaries and
  `stagesStatus = SUCCEEDED`;
* intraday HRV remained deferred.

This is capability-level only. The actual account, device, Fitbit migration
state and granted refresh token still need live probing. A token that was
created before adding sleep or health metrics scopes may refresh successfully
but still not authorize the new data types.

## Current Raw Tables

### `raw.google_health_heart_rate_responses`

Current grain:

* one row per API response per user/date/detail level

Business key:

* `source_id`
* `fitbit_user_id`
* `activity_date`
* `detail_level`

Payload:

* `heart_rate_payload`

This table is intentionally response-grain because intraday heart rate can
produce large observation counts. It is suitable for high-volume sample data.

Current issue:

* helper and table names still contain older `data_points` wording in some R
  functions, but the physical Raw table grain is now response-level.

### `raw.google_health_sleep_logs`

Current grain:

* one row per sleep log/session

Business key:

* `sleep_log_key`

Payload:

* `sleep_log_payload`

Promoted metadata:

* `source_log_id`
* `google_user_id`
* `source_name`
* start/end physical times
* start/end UTC offsets
* start/end civil dates

This table already retains the full sleep payload. If the API response includes
sleep stages, they should already be retained in `sleep_log_payload`; the
current code simply does not promote stage metadata or create a stage-level Raw
child table.

## Current Sample Payload Evidence

Current tests confirm the expected retained structure for:

* heart-rate observations: `heartRate.beatsPerMinute` and
  `heartRate.sampleTime.physicalTime`;
* sleep sessions: `sleep.interval.startTime`, `sleep.interval.endTime`, UTC
  offsets and civil dates.

Current test payloads do not include:

* daily resting heart rate;
* daily HRV;
* intraday HRV;
* sleep stages;
* sleep summary;
* sleep stage summary.

Live retained payload inspection is still required to confirm whether existing
`raw.google_health_sleep_logs.sleep_log_payload` rows already contain
`sleep.stages`, `sleep.summary` or `sleep.metadata.stagesStatus`.

Suggested inspection query:

```sql
SELECT
    COUNT(*) AS sleep_logs,
    SUM(JSON_CONTAINS_PATH(sleep_log_payload, 'one', '$.sleep.stages')) AS with_stages,
    SUM(JSON_CONTAINS_PATH(sleep_log_payload, 'one', '$.sleep.summary')) AS with_summary,
    SUM(JSON_CONTAINS_PATH(sleep_log_payload, 'one', '$.sleep.metadata.stagesStatus')) AS with_stage_status
FROM cycling_platform_raw.google_health_sleep_logs;
```

## API Capability Review

The Google Health `users.dataTypes.dataPoints.list` endpoint is used for all
candidate objects:

```text
GET /users/me/dataTypes/{dataType}/dataPoints
```

Google's API reference confirms the DataPoint union includes:

* `dailyRestingHeartRate` for `daily-resting-heart-rate`
* `dailyHeartRateVariability` for `daily-heart-rate-variability`
* `heartRateVariability` for `heart-rate-variability`
* `sleep` for `sleep`

The same API reference confirms sleep sessions can include `stages`,
`outOfBedSegments`, `metadata`, and `summary`.

Reference links:

* <https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints>
* <https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/list>

### Daily Resting Heart Rate

Candidate data type:

```text
daily-resting-heart-rate
```

Expected response field:

```text
dailyRestingHeartRate
```

Confirmed source-reported fields from API documentation:

* `date`
* `beatsPerMinute`
* `dailyRestingHeartRateMetadata.calculationMethod`

Filter pattern:

```text
dailyRestingHeartRate.date >= "YYYY-MM-DD"
AND dailyRestingHeartRate.date < "YYYY-MM-DD"
```

The current `get_google_health_data_points()` helper should not be reused
unchanged. It builds a sample-time filter from the data type name, which is
appropriate for heart-rate samples but not for daily summary data.

### Daily Heart-Rate Variability

Candidate data type:

```text
daily-heart-rate-variability
```

Expected response field:

```text
dailyHeartRateVariability
```

Confirmed source-reported fields from API documentation:

* `date`
* `averageHeartRateVariabilityMilliseconds`
* `nonRemHeartRateBeatsPerMinute`
* `entropy`
* `deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds`

Filter pattern:

```text
dailyHeartRateVariability.date >= "YYYY-MM-DD"
AND dailyHeartRateVariability.date < "YYYY-MM-DD"
```

This is the preferred HRV source for recovery use cases because it is already a
daily source-reported summary and should be low volume.

### Intraday Heart-Rate Variability

Candidate data type:

```text
heart-rate-variability
```

Expected response field:

```text
heartRateVariability
```

Confirmed source-reported fields from API documentation:

* `sampleTime`
* `rootMeanSquareOfSuccessiveDifferencesMilliseconds`
* `standardDeviationMilliseconds`

Filter pattern to live-probe:

```text
heart_rate_variability.sample_time.physical_time >= "YYYY-MM-DDT00:00:00Z"
AND heart_rate_variability.sample_time.physical_time < "YYYY-MM-DDT00:00:00Z"
```

This may be valuable later for sleep-window or overnight HRV analysis, but it is
not required for the first recovery Raw scope unless daily HRV is absent or too
coarse.

### Sleep Detail and Stages

Candidate data type:

```text
sleep
```

Endpoint:

```text
GET /users/me/dataTypes/sleep/dataPoints
```

The implemented sleep helper already uses the API's supported sleep filter:

```text
sleep.interval.end_time >= "YYYY-MM-DDT00:00:00Z"
AND sleep.interval.end_time < "YYYY-MM-DDT00:00:00Z"
```

The API documentation confirms sleep payloads may include:

* `sleep.type`
* `sleep.stages[]`
* `sleep.outOfBedSegments[]`
* `sleep.metadata.stagesStatus`
* `sleep.metadata.processed`
* `sleep.metadata.nap`
* `sleep.metadata.manuallyEdited`
* `sleep.summary`
* `sleep.summary.stagesSummary[]`

The existing Raw table may already retain this information if the account and
device return it. The first step is therefore inspection/probing, not a new
endpoint.

## Availability Assessment

| Candidate | API supports data type | Current config enabled | Current code can retrieve | Current account proven | Recommendation |
| --- | --- | --- | --- | --- | --- |
| Daily RHR | Yes | No | No | No | Add first |
| Daily HRV | Yes | No | No | No | Add second |
| Sleep stages | Yes, inside `sleep` | Sleep enabled | Payload retained if returned | Unknown | Probe existing payloads before schema change |
| Intraday HRV | Yes | No | No | No | Defer until daily HRV is assessed |

Known current account/app proof:

* heart-rate ingestion has written Raw rows;
* sleep ingestion has written Raw rows after the correct scopes were granted;
* daily RHR, daily HRV, intraday HRV and sleep-stage presence have not yet been
  proven in this repository.

## Recommended Smallest Useful Raw Scope

For the recovery use case, the smallest useful Raw expansion is:

1. daily resting heart rate;
2. daily HRV;
3. sleep-stage capability inspection and, if present, promoted sleep-stage
   metadata or a Raw child table;
4. intraday HRV only after confirming volume, cadence and analytical value.

This avoids building a large Google Health backlog before proving that the
account and device provide the source-reported recovery metrics.

## Proposed Raw Objects

### 1. `raw.google_health_daily_resting_heart_rate`

Purpose:

* Retain source-reported daily resting heart rate.

Grain:

* one row per `source_id` x `google_health_user_id` x `activity_date`

Business key:

* `daily_resting_heart_rate_key`

Promoted metadata:

* `source_id`
* `google_health_user_id`
* `activity_date`
* `run_id`
* `retrieved_at`
* `source_data_point_id`
* `source_name`
* `resting_heart_rate_bpm`
* `calculation_method`
* `created_at`
* `updated_at`

Payload:

* `daily_resting_heart_rate_payload`

Notes:

* Use `google_health_user_id`, not `fitbit_user_id`, for new Google Health
  objects.
* The payload is the source of truth. Promoted columns are for filtering,
  lineage and common access only.
* The deterministic key uses the source data-point id when present. When the
  source omits an id, the key falls back to stable source attributes plus the
  payload hash so multiple same-date records are not silently overwritten.

### 2. `raw.google_health_daily_heart_rate_variability`

Purpose:

* Retain source-reported daily HRV values.

Grain:

* one row per `source_id` x `google_health_user_id` x `activity_date`

Business key:

* `daily_heart_rate_variability_key`

Promoted metadata:

* `source_id`
* `google_health_user_id`
* `activity_date`
* `run_id`
* `retrieved_at`
* `source_data_point_id`
* `source_name`
* `average_hrv_milliseconds`
* `non_rem_heart_rate_bpm`
* `entropy`
* `deep_sleep_rmssd_milliseconds`
* `created_at`
* `updated_at`

Payload:

* `daily_heart_rate_variability_payload`

Naming note:

* `average_hrv_milliseconds` and `deep_sleep_rmssd_milliseconds` use accepted
  HRV terminology while preserving units. The full Google field names remain in
  the JSON payload.
* Daily HRV is separate from intraday/sample HRV.

### 3. `raw.google_health_sleep_logs`

Purpose:

* Continue retaining one row per sleep session/log.

Recommended short-term action:

* Do not create a new endpoint.
* Inspect existing retained payloads for stages and summaries.
* Add tests using representative sleep-stage payloads before any code change.

Promoted metadata now added because stages were confirmed:

* `sleep_type`
* `stages_status`
* `is_processed`
* `is_nap`
* `is_manually_edited`
* `has_sleep_stages`
* `sleep_stage_count`
* `has_sleep_summary`

Possible Raw child object if stage rows need independent lineage:

```text
raw.google_health_sleep_stage_segments
```

Grain:

* one row per `sleep_log_key` x `stage_index`

Business key:

* `sleep_log_key`
* `stage_index`

Promoted metadata:

* `sleep_log_key`
* `stage_index`
* `run_id`
* `source_id`
* `retrieved_at`
* `stage_type`
* `stage_start_datetime_utc`
* `stage_end_datetime_utc`
* `start_utc_offset`
* `end_utc_offset`
* `created_at`
* `updated_at`

Payload:

* `sleep_stage_payload`

Recommendation:

* Keep the parent `sleep_log_payload` as the Raw source of truth. Defer the
  child table until Silver design proves stage rows need independent Raw
  lineage.

### 4. `raw.google_health_heart_rate_variability_responses`

Status:

* deferred candidate.

Purpose:

* Retain intraday/sample HRV if daily HRV proves insufficient.

Preferred initial grain:

* one row per API response per user/date/detail level, matching the current
  heart-rate response pattern.

Business key:

* `source_id`
* `google_health_user_id`
* `activity_date`
* `detail_level`

Promoted metadata:

* `source_id`
* `google_health_user_id`
* `activity_date`
* `detail_level`
* `run_id`
* `retrieved_at`
* `page_count`
* `data_point_count`
* `created_at`
* `updated_at`

Payload:

* `heart_rate_variability_payload`

Reason to defer:

* daily HRV is lower volume and closer to the recovery use case;
* intraday HRV volume and cadence are unknown;
* intraday HRV may become useful only after sleep sessions are conformed.

## Incremental Ingestion Strategy

Use the existing Google Health date-window pattern.

Daily RHR and daily HRV:

* routine refresh: configurable recent window, default 7 days;
* historical backfill: configurable wider window;
* one API request per date window;
* idempotent upsert by source/user/date;
* preserve full response payload with `digits = NA`;
* keep `run_id`, `source_id` and `retrieved_at`.

Sleep:

* continue filtering by sleep end time;
* refresh recent days because sleep records may be processed or updated after
  the first retrieval;
* repair by rerunning a bounded date window;
* upsert by `sleep_log_key`.

Intraday HRV, if later enabled:

* use response-grain Raw storage first;
* start with a short probe window before enabling routine ingestion;
* add a separate refresh/backfill window so HRV sample volume does not affect
  daily summary ingestion.

## Repair and Idempotency

The Raw expansion should follow the existing Raw entity pattern:

* create an `etl_run_entity` row per entity;
* retrieve data;
* load inside database transactions;
* upsert by natural business key;
* update entity-run status;
* rethrow failures after logging.

Repair behaviour:

* RHR/HRV daily objects: rerun affected dates and upsert;
* sleep logs: rerun affected sleep end dates and upsert;
* sleep stage child table, if implemented: delete/reinsert child rows for
  affected `sleep_log_key` values only after parent payload is available;
* intraday HRV responses: rerun affected response dates and upsert.

No Google Health Raw expansion needs Stage unless future volume proves that
bulk rebuilds are expensive.

## Operational Checks

Fast checks suitable for routine automation:

* Google Health OAuth diagnostics report required env vars and token presence;
* enabled data types are present in `config/platform.yml`;
* one recent probe request per enabled daily data type returns either data or a
  clean empty response;
* no duplicate Raw business keys;
* `run_id`, `source_id`, `retrieved_at` and payload columns are non-null;
* daily records have valid `activity_date` values;
* sleep rows have coherent start/end times where both are present.

Deep validation:

* compare requested date windows with loaded Raw dates;
* flag missing days in recent windows separately from truly empty API responses;
* count sleep payloads with stage arrays, summaries and stage statuses;
* validate sleep stages are non-overlapping and within parent sleep interval;
* compare sleep summary stage totals with stage segment durations where both
  are present;
* compare daily HRV availability against sleep availability to identify device
  or account limitations;
* profile intraday HRV row/page volume before routine scheduling.

## Required Config Changes

Add data types only after live probing succeeds:

```yaml
sources:
  google_health:
    data_types:
      - heart-rate
      - sleep
      - daily-resting-heart-rate
      - daily-heart-rate-variability
      # - heart-rate-variability
```

Recommended ingestion config:

```yaml
ingestion:
  google_health_daily_resting_heart_rate_refresh_days: 14
  google_health_daily_resting_heart_rate_backfill_days: 365
  google_health_daily_heart_rate_variability_refresh_days: 14
  google_health_daily_heart_rate_variability_backfill_days: 365
  google_health_intraday_heart_rate_variability_refresh_days: 7
  google_health_intraday_heart_rate_variability_backfill_days: 30
```

Use separate refresh windows because daily summary data and high-volume sample
data have different operational profiles.

## Required OAuth Changes

Before implementation, confirm the refresh token has both required scopes:

* health metrics and measurements readonly;
* sleep readonly.

If the token does not contain both, regenerate it and update `.Renviron`.

The auth check should eventually report:

* token file path;
* refresh-token presence and prefix;
* granted scopes from token introspection;
* whether each configured Google Health data type has a required scope;
* a small live probe result for each newly enabled data type.

## Required Code Changes When Implemented

Expected new or changed files:

* `sql/raw/120_create_google_health_daily_resting_heart_rate.sql`
* `sql/raw/130_create_google_health_daily_heart_rate_variability.sql`
* `sql/raw/153_alter_google_health_sleep_logs_stage_metadata.sql`
* optional later: `sql/raw/<next>_create_google_health_sleep_stage_segments.sql`
* optional later: `sql/raw/<next>_create_google_health_heart_rate_variability_responses.sql`
* `R/api/get_google_health_daily_summaries.R`
* optional later: `R/api/get_google_health_heart_rate_variability.R`
* matching insert/update/upsert helpers under `R/database/`
* matching ingestion orchestrators under `R/ingestion/`
* `platform.R`, after manual validation of standalone runners
* `docs/endpoint_inventory.md`
* tests under `tests/testthat/`

Implementation guidance:

* keep the existing heart-rate and sleep code stable;
* add a daily-summary data-point helper rather than overloading the current
  sample-time helper;
* use daily filter names from the API contract, for example
  `dailyHeartRateVariability.date`;
* preserve Raw payload JSON using `google_health_payload_to_json()`.

## Required Tests

Add small unit tests for shaping:

* daily RHR payload with `dailyRestingHeartRate.date`,
  `beatsPerMinute` and `calculationMethod`;
* daily HRV payload with `dailyHeartRateVariability.date`,
  `averageHeartRateVariabilityMilliseconds` and
  `deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds`;
* sleep payload containing `sleep.stages[]`, `sleep.metadata.stagesStatus` and
  `sleep.summary.stagesSummary[]`;
* empty API response handling;
* business-key split/upsert typing.

Add smoke checks for new files and DDL existence after implementation.

## Live Probing Plan

Run these probes before implementing DDL.

1. Confirm token scopes:

```sh
Rscript run_google_health_auth_check.R
```

2. Probe daily RHR for a recent short window:

```text
GET /users/me/dataTypes/daily-resting-heart-rate/dataPoints
filter=dailyRestingHeartRate.date >= "2026-07-01" AND dailyRestingHeartRate.date < "2026-07-08"
```

3. Probe daily HRV for the same window:

```text
GET /users/me/dataTypes/daily-heart-rate-variability/dataPoints
filter=dailyHeartRateVariability.date >= "2026-07-01" AND dailyHeartRateVariability.date < "2026-07-08"
```

4. Inspect current sleep payloads for stages:

```sql
SELECT
    sleep_log_key,
    JSON_EXTRACT(sleep_log_payload, '$.sleep.type') AS sleep_type,
    JSON_EXTRACT(sleep_log_payload, '$.sleep.metadata.stagesStatus') AS stages_status,
    JSON_LENGTH(JSON_EXTRACT(sleep_log_payload, '$.sleep.stages')) AS stage_count,
    JSON_EXTRACT(sleep_log_payload, '$.sleep.summary') AS sleep_summary
FROM cycling_platform_raw.google_health_sleep_logs
ORDER BY end_physical_time DESC
LIMIT 20;
```

5. Probe intraday HRV only if daily HRV is missing or insufficient:

```text
GET /users/me/dataTypes/heart-rate-variability/dataPoints
filter=heart_rate_variability.sample_time.physical_time >= "2026-07-01T00:00:00Z" AND heart_rate_variability.sample_time.physical_time < "2026-07-02T00:00:00Z"
```

If the intraday HRV filter fails, test the API's accepted field casing before
designing ingestion.

## Risks and Unknowns

* Google Health API support does not guarantee the Fitbit account/device
  supplies the data.
* Granted OAuth scopes may not match the current `.Renviron` refresh token.
* Daily RHR and daily HRV filters use daily summary field names, not the current
  sample-time filter builder.
* Sleep stages may already be present in payloads; adding a new endpoint would
  be unnecessary if so.
* Sleep stages may be absent for naps, short sleeps, low coverage, manually
  edited sleeps or unsupported devices.
* Daily HRV and intraday HRV may represent different calculations; do not mix
  them in one Raw table.
* Intraday HRV may be sparse, noisy or high-volume relative to the recovery
  value it adds.
* Current Raw HR uses `fitbit_user_id`, while new Google Health objects should
  use `google_health_user_id` to avoid extending the naming inconsistency.

## Confirmed Available Data Types

Confirmed by Google Health API documentation:

* `daily-resting-heart-rate`
* `daily-heart-rate-variability`
* `heart-rate-variability`
* `sleep`, including possible stages, metadata and summaries

Confirmed in this repository/account:

* `heart-rate` Raw ingestion works;
* `sleep` Raw ingestion works;
* `daily-resting-heart-rate` returns source-reported RHR;
* `daily-heart-rate-variability` returns average HRV, deep-sleep RMSSD,
  non-REM heart rate and entropy;
* `sleep` payloads include stage arrays, stage summaries and successful stage
  processing status;
* intraday HRV remains deferred.

## Unresolved API Questions

* How often do daily RHR and daily HRV revise after first retrieval?
* Does the account return intraday HRV rows, and at what volume?
* Are sleep stages consistently available for main sleeps only or also for naps?
* Does the API accept snake_case or camelCase filter fields for
  `heart-rate-variability`?
* Are daily HRV values populated as average HRV, deep-sleep RMSSD, entropy,
  non-REM heart rate, or a subset of those fields?

## Recommended Raw Objects

Implemented:

1. `raw.google_health_daily_resting_heart_rate`
2. `raw.google_health_daily_heart_rate_variability`

Implemented as parent metadata only:

3. `raw.google_health_sleep_logs` promoted metadata for stage availability,
   stage status and summaries.

Defer:

4. `raw.google_health_heart_rate_variability_responses`

## Current Implementation Order

1. Capability probe confirmed daily RHR, daily HRV and rich sleep payloads.
2. Daily RHR Raw ingestion was implemented.
3. Daily HRV Raw ingestion was implemented.
4. Sleep-stage availability metadata was added to `raw.google_health_sleep_logs`.
5. Intraday HRV stayed deferred.
6. Google Health Silver remains paused until the new Raw objects have been
   exercised through routine runs.

## Owner Decision Checklist

Remaining decisions:

* How large should the first historical backfill be for daily RHR and daily HRV?
* Should historical sleep rows be repaired immediately to populate stage
  metadata, or allowed to update through the routine refresh window?
* How much routine evidence is enough before Google Health Silver design
  resumes?
* Should intraday HRV remain deferred until after daily HRV and sleep Silver
  exist?
* Should a future Silver stage table be derived directly from
  `sleep_log_payload`, or should Raw child stage rows be introduced later if
  operational lineage requires it?
