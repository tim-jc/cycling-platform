# Google Health Raw Ingestion Design

Status note: this document records the initial Google Health ingestion design.
The implemented heart-rate raw grain has since been changed to one row per API
response per user/date/detail level in
`cycling_platform_raw.google_health_heart_rate_responses`. Sleep remains one
row per sleep log/session where available. Google/Fitbit raw ingestion is
implemented; validation and silver transforms remain future work.

## Purpose

Design a future raw-layer ingestion path for Google Health API heart-rate data.

This design replaces the earlier Fitbit Web API direction. Fitbit Web API is
not a good new foundation because it is being deprecated. Google Health API is
the better target because it provides a modern REST API for health data and is
positioned as the Fitbit migration path.

Initial scope:

* Google Health API only
* heart-rate data points only
* raw layer only
* no silver or gold transformations

Relevant docs:

* Google Health API get started: <https://developers.google.com/health/get-started>
* Data types: <https://developers.google.com/health/data-types>
* Data points list endpoint: <https://developers.google.com/health/reference/rest/v4/users.dataTypes.dataPoints/list>
* Rate limits: <https://developers.google.com/health/rate-limits>

## Recommended Shape

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

ingestion:
  google_health_refresh_days: 7
  google_health_backfill_days: 365
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

## Recommendation

Build a generic Google Health raw data-point ingestion path with heart rate as
the first enabled data type.

This keeps the initial implementation small while avoiding a dead-end
Fitbit-specific design. It also gives the platform a reusable raw ingestion
pattern for future health data without committing to silver/gold modelling yet.
