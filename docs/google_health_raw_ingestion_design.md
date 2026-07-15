# Google Health Raw Ingestion Design

Status note: this document records the initial Google Health ingestion design
and historical reasoning. The current implementation is more specific than the
original generic-table proposal:

* `cycling_platform_raw.google_health_heart_rate_responses`: one row per
  heart-rate API response per user/date/detail level.
* `cycling_platform_raw.google_health_sleep_logs`: one row per sleep
  log/session, with full payload retained and stage metadata promoted on
  refresh.
* `cycling_platform_raw.google_health_daily_resting_heart_rate`: one row per
  source-reported daily RHR data point.
* `cycling_platform_raw.google_health_daily_heart_rate_variability`: one row
  per source-reported daily HRV data point.
* `cycling_platform_raw.google_health_daily_respiratory_rate`: one row per
  source-reported daily respiratory-rate data point.

Intraday HRV remains deferred. Google/Fitbit Raw ingestion exists; Silver
transforms remain future work.

## Purpose

Document the Google Health Raw ingestion design and the decisions that led to
the current source-preserving Raw objects.

This design replaces the earlier Fitbit Web API direction. Fitbit Web API is
not a good new foundation because it is being deprecated. Google Health API is
the better target because it provides a modern REST API for health data and is
positioned as the Fitbit migration path.

Original initial scope, now superseded by the explicit Raw objects above:

* Google Health API only
* heart-rate data points only
* raw layer only
* no silver or gold transformations

Relevant docs:

* Google Health API get started: <https://developers.google.com/health/get-started>
* Data types: <https://developers.google.com/health/data-types>
* Data points list endpoint: <https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/list>
* Rate limits: <https://developers.google.com/health/rate-limits>

## Current Implemented Shape

The platform now uses explicit Raw objects rather than one generic health table.
This keeps grains and business keys clear while still preserving full source
payloads.

Current standalone runners:

```sh
Rscript run_google_health_heart_rate.R manual
Rscript run_google_health_sleep.R manual
Rscript run_google_health_daily_resting_heart_rate.R refresh
Rscript run_google_health_daily_resting_heart_rate.R backfill
Rscript run_google_health_daily_resting_heart_rate.R 2026-07-01 2026-07-08
Rscript run_google_health_daily_heart_rate_variability.R refresh
Rscript run_google_health_daily_heart_rate_variability.R backfill
Rscript run_google_health_daily_heart_rate_variability.R 2026-07-01 2026-07-08
Rscript run_google_health_daily_respiratory_rate.R refresh
Rscript run_google_health_daily_respiratory_rate.R backfill
Rscript run_google_health_daily_respiratory_rate.R repair
Rscript run_google_health_daily_respiratory_rate.R 2026-07-01 2026-07-08
```

The normal platform run ingests daily RHR, daily HRV, and daily respiratory
rate when the corresponding data types are present in `config/platform.yml`.

Successful empty daily requests are represented in
`cycling_platform_admin.etl_request_log` with `request_status = 'SUCCESS'`,
`returned_data_point_count = 0`, and `is_successfully_empty = 1`. No placeholder
metric rows are written.

## Daily RHR/HRV Source Provenance

Google Health is the ingestion API, but daily records can originate from
different source ecosystems. Live payload inspection found:

| Meaning | JSON path | Example values |
| --- | --- | --- |
| originating ecosystem | `$.dataSource.platform` | `FITBIT`, `HEALTH_KIT` |
| recording method | `$.dataSource.recordingMethod` | `DERIVED`, `UNKNOWN`, `PASSIVELY_MEASURED` |
| source device manufacturer | `$.dataSource.device.manufacturer` | `Apple Inc.` |
| source device model | `$.dataSource.device.model` | not always present |
| source data-point identifier | `$.name` | often absent for daily summaries |
| measurement date | `$.dailyRestingHeartRate.date`, `$.dailyHeartRateVariability.date` | source civil date object |
| ingestion source | `admin.data_source.source_name` via `source_id` | `google_health` |

Promoted Raw columns:

* `source_ecosystem`
* `source_platform`
* `source_recording_method`
* `source_device_manufacturer`
* `source_device_model`

`source_ecosystem` is the platform-owned canonical mapping used for querying
and validation:

| Source evidence | Canonical `source_ecosystem` |
| --- | --- |
| `$.dataSource.platform = "FITBIT"` | `fitbit` |
| `$.dataSource.platform = "HEALTH_KIT"` | `apple_health` |
| `$.dataSource.platform = "GOOGLE_FIT"` | `google_fit` |
| missing platform with Apple device manufacturer | `apple_health` |
| missing platform with Fitbit device manufacturer | `fitbit` |
| no recognised evidence | `unknown` |

`source_name` and `source_data_point_id` remain available, but live daily
summary payloads often have them as `NULL`.

Multiple rows for the same user and date are expected. For example, Google
Health can return both `FITBIT` and `HEALTH_KIT` daily observations for the
same date, and HRV can contain more than one `HEALTH_KIT` source data point.
The Raw grain is therefore the retained source data point, represented by the
deterministic Raw key, not `google_health_user_id + activity_date`.

When Google Health provides `$.name`, that source data-point identifier is the
best business key. Where it is absent, the platform falls back to a deterministic
key using the data type, user, activity date, source name, and retained payload
hash. Validation uses the fuller source grain for diagnostics:

* `google_health_user_id`
* `activity_date`
* `source_data_point_id` where present
* `source_ecosystem`
* `source_platform`
* `source_recording_method`
* `source_device_manufacturer`
* `source_device_model`
* retained payload hash

This preserves Apple Health and Fitbit observations side by side. No Raw
deduplication, preferred-source selection, or cross-ecosystem merge is performed.

Existing rows can be backfilled from retained payloads without refetching the
API:

```sh
Rscript run_google_health_daily_source_provenance_backfill.R --dry-run
Rscript run_google_health_daily_source_provenance_backfill.R
```

The backfill reports examined, updated, already-populated, unknown-source, and
unparseable counts for both daily RHR and daily HRV.

## Daily Respiratory Rate

Daily respiratory rate uses the same Google Health daily data-point pattern as
RHR and HRV. Google defines this metric as a daily average respiratory rate in
breaths per minute, one data point per day, calculated for the main sleep.

Endpoint:

```text
GET /users/me/dataTypes/daily-respiratory-rate/dataPoints
```

Filter:

```text
daily_respiratory_rate.date >= "YYYY-MM-DD"
AND daily_respiratory_rate.date < "YYYY-MM-DD"
```

Live capability probing returned daily records for the recent test window.
Observed payload paths:

| Meaning | JSON path | Observed values |
| --- | --- | --- |
| respiratory-rate value | `$.dailyRespiratoryRate.breathsPerMinute` | numeric breaths per minute |
| unit | API field semantics | breaths per minute |
| measurement date | `$.dailyRespiratoryRate.date` | source civil date object |
| source ecosystem | `$.dataSource.platform` | `FITBIT` in the tested window |
| recording method | `$.dataSource.recordingMethod` | `DERIVED` in the tested window |
| source device | `$.dataSource.device` | present as an empty object in the tested window |
| source application | `$.dataSource.application` | not observed in the tested window |
| source record identifier | `$.name` | absent in the tested window |

Raw grain:

```text
one row per Google Health daily respiratory-rate source data point
```

The physical primary key is `daily_respiratory_rate_key`. If Google Health
provides `$.name`, that identifier is used as the stable source record
identity. If `$.name` is absent, the key falls back to the data type, Google
Health user, activity date, source name and retained payload hash. This avoids
assuming one record per user/date and keeps same-day multi-ecosystem records
representable if they appear later.

Promoted columns include:

* `google_health_user_id`
* `activity_date`
* `respiratory_rate_brpm`
* `source_ecosystem`
* `source_platform`
* `source_recording_method`
* `source_device_manufacturer`
* `source_device_model`
* `source_data_point_id`
* `source_name`

`daily_respiratory_rate_payload` remains the source of truth.

Runner modes:

* `refresh`: recent configured window.
* `repair`: recent configured window, recorded as `REPAIR` in Admin metadata.
* `backfill`: configured historical window.
* explicit `start_date end_date`: bounded manual date window.

Daily automation includes respiratory rate when `daily-respiratory-rate` is
listed under `sources.google_health.data_types`. No Silver or Gold respiratory
rate object exists yet; the metric remains in Raw observation.

### Sleep Payload Date Note

Live sleep payload inspection confirmed that retained sleep JSON contains
interval timestamps at:

* `$.sleep.interval.startTime`
* `$.sleep.interval.startUtcOffset`
* `$.sleep.interval.endTime`
* `$.sleep.interval.endUtcOffset`

The current stored rows have `start_civil_date` and `end_civil_date` as `NULL`,
so overlap validation currently reports missing sleep dates even when sleep
payloads are present. This is a promoted metadata repair issue, not evidence
that sleep was not ingested. The retained sleep payload remains authoritative.

## Original Recommended Shape

Use a generic raw table:

```text
cycling_platform_raw.google_health_data_points
```

Do not create a heart-rate-specific table first. The Google Health endpoint is
generic across data types, so a generic raw data-point table gives us a clean
path to add HRV, sleep, resting heart rate, oxygen saturation, and other health
metrics later.

First enabled data type:

```text
heart-rate
```

## Config Additions

```yaml
sources:
  google_health:
    enabled: true
    api_base_url: https://health.googleapis.com/v4
    user_id: me
    data_types:
      - heart-rate
      - sleep
      - daily-resting-heart-rate
      - daily-heart-rate-variability
      - daily-respiratory-rate

ingestion:
  google_health_refresh_days: 7
  google_health_backfill_days: 365
  google_health_sleep_refresh_days: 7
  google_health_sleep_backfill_days: 365
  google_health_daily_resting_heart_rate_refresh_days: 14
  google_health_daily_resting_heart_rate_backfill_days: 365
  google_health_daily_heart_rate_variability_refresh_days: 14
  google_health_daily_heart_rate_variability_backfill_days: 365
  google_health_daily_respiratory_rate_refresh_days: 14
  google_health_daily_respiratory_rate_backfill_days: 365
  google_health_page_size: 10000
  google_health_request_pause_seconds: 0.25
```

Optional later:

```yaml
ingestion:
  google_health_backfill_start_date: "2024-01-01"
```

## Admin Source

Add a new source row:

```sql
INSERT IGNORE INTO cycling_platform_admin.data_source (
    source_id,
    source_name,
    source_description,
    is_active
)
VALUES (
    2,
    'google_health',
    'Google Health API',
    TRUE
);
```

## OAuth and Token Storage

The operational authentication runbook is maintained in
`docs/google_health_authentication.md`. This section records the design context
for the Raw ingestion implementation.

Add Google Health-specific helpers rather than generalising Strava token logic
immediately.

Environment variables:

```text
GOOGLE_HEALTH_CLIENT_ID
GOOGLE_HEALTH_CLIENT_SECRET
GOOGLE_HEALTH_REFRESH_TOKEN
```

Required scopes:

```text
https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
https://www.googleapis.com/auth/googlehealth.sleep.readonly
```

Both scopes are required because the platform now ingests:

* heart-rate data from Google/Fitbit health metrics;
* sleep logs from Google/Fitbit sleep data.

If a refresh token is generated with only one of these scopes, the other
endpoint may fail even though token refresh itself succeeds.

Proposed helper files:

```text
R/api/get_google_health_access_token.R
R/api/perform_google_health_request.R
```

Token approach:

* refresh access tokens using Google's OAuth token endpoint
* read and write tokens through a single project `.Renviron` path
* persist a rotated `GOOGLE_HEALTH_REFRESH_TOKEN` with `update_renviron()` if
  Google returns one
* update the current R process environment after writing a rotated refresh token
* keep access tokens ephemeral
* use bearer auth in `perform_google_health_request()`

Manual auth diagnostics:

```sh
Rscript run_google_health_auth_check.R
```

This command prints the token file path, modified timestamp, whether the
required secrets are present, and whether refresh succeeded. It never prints the
full refresh token.

### Obtaining a New Refresh Token

The platform does not create the initial Google OAuth refresh token itself. When
the current refresh token is revoked, expires, or was generated with the wrong
scopes, generate a new token using the Google OAuth consent flow and then store
it in the project `.Renviron`.

The refresh token must be requested with:

```text
access_type=offline
prompt=consent
```

The consent request must include both platform scopes:

```text
https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly
https://www.googleapis.com/auth/googlehealth.sleep.readonly
```

After completing the consent flow, paste the returned refresh token into the
project `.Renviron`:

```text
GOOGLE_HEALTH_REFRESH_TOKEN=1//...
```

Then validate the token with:

```sh
Rscript run_google_health_auth_check.R
```

Expected successful output includes:

```text
Google Health refresh succeeded
Google Health access token refresh succeeded
```

It is normal for the refresh response to say:

```text
response did not include a new refresh token
```

Google generally does not rotate refresh tokens on every access-token refresh.
This differs from Strava.

If the auth check fails with `invalid_grant`, the stored refresh token is no
longer valid for this OAuth client and scope set. Generate a new refresh token,
replace `GOOGLE_HEALTH_REFRESH_TOKEN` in `.Renviron`, and rerun the auth check.

If the auth check succeeds but platform ingestion fails with a scope error,
regenerate the refresh token and confirm both required scopes were present in the
OAuth consent request.

## Endpoint

For heart rate:

```text
GET /users/me/dataTypes/heart-rate/dataPoints
```

Example window filter:

```text
heart_rate.sample_time.physical_time >= "2026-06-27T00:00:00Z"
AND heart_rate.sample_time.physical_time < "2026-06-28T00:00:00Z"
```

Use `pageSize = google_health_page_size` and follow `nextPageToken`.

## Raw Table DDL Sketch

```sql
CREATE TABLE IF NOT EXISTS cycling_platform_raw.google_health_data_points (
    data_point_key CHAR(64) NOT NULL,

    data_type VARCHAR(100) NOT NULL,
    google_user_id VARCHAR(100) NOT NULL,

    run_id BIGINT NOT NULL,
    source_id INT NOT NULL,
    retrieved_at DATETIME NOT NULL,

    source_name TEXT NULL,
    sample_physical_time DATETIME NULL,
    sample_utc_offset VARCHAR(32) NULL,
    sample_civil_date DATE NULL,

    value_numeric DECIMAL(18,6) NULL,
    value_name VARCHAR(100) NULL,

    data_point_name TEXT NULL,
    data_point_payload JSON NOT NULL,

    created_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP,

    updated_at DATETIME NOT NULL
        DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (data_point_key),

    KEY idx_google_health_type_time (
        data_type,
        sample_physical_time
    ),

    KEY idx_google_health_run_id (run_id),

    KEY idx_google_health_source_id (source_id),

    KEY idx_google_health_retrieved_at (retrieved_at),

    CONSTRAINT fk_google_health_data_points_run_id
        FOREIGN KEY (run_id)
        REFERENCES cycling_platform_admin.etl_run (run_id),

    CONSTRAINT fk_google_health_data_points_source_id
        FOREIGN KEY (source_id)
        REFERENCES cycling_platform_admin.data_source (source_id)
);
```

For heart rate:

* `data_type = 'heart-rate'`
* `value_name = 'beats_per_minute'`
* `value_numeric = heartRate.beatsPerMinute`
* the full Google `DataPoint` is retained in `data_point_payload`

## Business Key

Use a deterministic hash key:

```text
SHA256(data_type + data_point_name + sample_physical_time + source_name + payload)
```

Google Health `DataPoint.name` may be empty for some data types, so the key
cannot rely on `name` alone. Including the payload makes repeated loads
idempotent while still distinguishing genuinely different samples.

If this proves too broad, the heart-rate-specific fallback key is:

```text
SHA256(data_type + sample_physical_time + source_name + beats_per_minute)
```

## API Functions

Proposed files:

```text
R/api/get_google_health_data_points.R
R/api/get_google_health_heart_rate.R
```

`get_google_health_data_points()` should be generic:

* input: `data_type`, `start_datetime`, `end_datetime`, `run_id`, `source_id`,
  `config`
* build the Google Health filter
* paginate through `nextPageToken`
* retain full payload JSON using `jsonlite::toJSON(..., digits = NA)`
* promote only ingestion-useful fields
* return a tibble ready for upsert

`get_google_health_heart_rate()` should be a thin wrapper:

* set `data_type = "heart-rate"`
* map heart-rate values into `value_numeric`
* set `value_name = "beats_per_minute"`

## Database Helper Functions

Proposed files:

```text
R/database/get_existing_google_health_data_point_keys.R
R/database/insert_google_health_data_points.R
R/database/update_google_health_data_points.R
R/database/upsert_google_health_data_points.R
```

Use the existing `split_existing_rows()` pattern with:

```r
key_columns = "data_point_key"
```

The insert/update/upsert flow should match existing raw entities:

```text
get existing keys
    ↓
split incoming rows into insert/update sets
    ↓
insert new rows
    ↓
update existing rows
```

## Ingestion Function

Proposed file:

```text
R/ingestion/ingest_google_health_heart_rate.R
```

Responsibilities:

1. create `etl_run_entity(entity_name = "google_health_heart_rate")`
2. build date windows
3. fetch one date window at a time
4. upsert rows inside a transaction per window or batch
5. update entity run counts
6. mark entity run `SUCCESS` or `FAILED`
7. rethrow failures after logging

The function should be rerunnable. Already-loaded data points are updated rather
than duplicated.

## Date-Based Pending and Backfill Strategy

Google Health heart-rate data does not have a Strava-style parent table, so use
date windows rather than parent status fields.

Manual run:

```text
Sys.Date() - google_health_refresh_days through today
```

Backfill run:

```text
Sys.Date() - google_health_backfill_days through today
```

For each date:

* query `[date 00:00:00 UTC, next date 00:00:00 UTC)`
* upsert all returned data points
* treat empty responses as successful empty days

Near-term implementation can derive pending dates directly from config and
existing raw rows. Later, add a lightweight date-level control table if we need
explicit status tracking:

```text
cycling_platform_raw.google_health_date_ingestion_status
```

Suggested future columns:

* `data_type`
* `date`
* `status`
* `attempted_at`
* `sample_count`
* `error_message`

Do not add this table until the simple date-window approach proves insufficient.

## Rate Limits and Throttling

Google Health API has published rate limits. Current defaults are generous for
our likely use case, but the request helper should still be defensive.

`perform_google_health_request()` should:

* apply bearer auth
* use configured timeout
* use configured request pause
* retry transient network and `5xx` failures
* back off on `429`
* log rate-limit failures clearly
* keep `pageSize` high enough to minimise request count

Do not reuse Strava's practical 100 requests per 15-minute throttle. That was
source-specific behaviour.

## Platform Integration

Initial implementation should not refactor `platform.R` heavily.

Recommended first step:

```text
Rscript run_google_health_heart_rate.R
```

Once proven, integrate into the main platform orchestration as an optional
source guarded by:

```yaml
sources:
  google_health:
    enabled: true
```

This avoids coupling a new OAuth source into the Strava run path before it is
stable.

## Data Quality Checks

Initial checks:

* duplicate `data_point_key`
* invalid JSON payloads
* missing `run_id`, `source_id`, or `retrieved_at`
* `source_id` exists in `admin.data_source`
* heart-rate values are non-negative
* heart-rate values are within a plausible human range
* date windows expected from config have at least been attempted
* latest successful Google Health run is recent

Payload reconciliation checks should compare promoted fields back to
`data_point_payload`, with the payload treated as authoritative.

## Risks and Unknowns

* Google Health API is new, so docs and behaviour may change.
* OAuth consent, app verification, and production access requirements need to
  be confirmed before automation.
* Fitbit-originating data availability depends on Fitbit-to-Google sync.
* Time handling needs care: preserve physical UTC time, UTC offset, and civil
  time where provided.
* Heart-rate numeric values may arrive as integer-like strings; parse
  explicitly.
* `DataPoint.name` may be empty, so deterministic key design needs testing
  against real payloads.
* The first implementation should be validated against a small date range
  before attempting a full history load.

## Open Implementation Questions

* Should the first load use UTC day windows or local civil day windows?
* Should the raw table keep only generic promoted columns, or add
  heart-rate-specific promoted fields?
* Should date-level ingestion status be implemented immediately or deferred?
* Should Google Health run as a separate script until stable, or be added to
  `platform.R` behind a config flag from the start?
* What historical range is actually available after Fitbit migration/sync?

## Historical Recommendation

Build a generic Google Health raw data-point ingestion path with heart rate as
the first enabled data type.

This keeps the initial implementation small while avoiding a dead-end
Fitbit-specific design. It also gives the platform a reusable raw ingestion
pattern for future health data without committing to silver/gold modelling yet.

This recommendation is retained as history. The implemented design now uses
explicit Raw objects for heart-rate responses, sleep logs, daily RHR, daily
HRV, and daily respiratory rate so each object has a clear source grain,
business key, and validation policy.
