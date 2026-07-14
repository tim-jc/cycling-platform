# Ingestion Sequence

## Overview

The platform orchestrates ingestion through a standard execution flow.

Each execution creates a single `run_id` in `admin.etl_run`.

All entity-level processing is associated with that `run_id` through `admin.etl_run_entity`.

For `manual`, `scheduled`, and `backfill`, execution mode controls only the
activity refresh window. `scheduled` uses the routine manual refresh window but
records the Raw ETL run as `SCHEDULED`. Child entities are selected by status
from `raw.activities`, so pending or failed stream, detail, and lap work
resumes on any standard platform run.

`streams_only` is a recovery mode. It creates an ETL run as usual, skips
activities, details, and laps, then runs only pending or failed stream ingestion
with a safe activity cap.

## Happy Path

```text id="9wsu6g"
platform.R
    ↓
load_config()
    ↓
resolve execution mode
    ↓
get_connection()
    ↓
create_etl_run()
    ↓
ingest_activities()
        ↓
    create_etl_run_entity()
        ↓
    get_activities()
        ↓
    upsert_activities()
            ↓
        get_existing_activity_ids()
        ↓
        insert_activities()
        ↓
        update_activities()
        ↓
    update_etl_run_entity()
    ↓
get_pending_stream_activity_ids()
    ↓
ingest_streams()
        ↓
    create_etl_run_entity()
        ↓
    split activity IDs into batches
        ↓
    for each batch:
        get_streams()
            ↓
        upsert_streams()
            ↓
        update stream_status
            ↓
        commit batch transaction
        ↓
    update_etl_run_entity()
    ↓
get_pending_detail_activity_ids()
    ↓
ingest_activity_details()
        ↓
    create_etl_run_entity()
        ↓
    split activity IDs into batches
        ↓
    for each batch:
        get_activity_details()
            ↓
        upsert_activity_details()
            ↓
        update details_status
            ↓
        commit batch transaction
        ↓
    update_etl_run_entity()
    ↓
get_pending_lap_activity_ids()
    ↓
ingest_activity_laps()
        ↓
    create_etl_run_entity()
        ↓
    split activity IDs into batches
        ↓
    for each batch:
        get_activity_laps()
            ↓
        upsert_activity_laps()
            ↓
        update laps_status
            ↓
        commit batch transaction
        ↓
    update_etl_run_entity()
    ↓
if Google Health enabled:
    ingest configured Google Health Raw entities:
        - heart-rate responses
        - sleep logs
        - daily resting heart rate
        - daily heart-rate variability
        - daily respiratory rate
        ↓
    for each enabled entity:
        create_etl_run_entity()
        ↓
        split date windows into batches
        ↓
        for each date/window:
            get Google Health data points
            ↓
            shape rows at the entity's Raw grain
            ↓
            upsert Raw rows
            ↓
            record successful empty responses in admin metadata
            ↓
            commit batch transaction
        ↓
        update_etl_run_entity()
    ↓
update_etl_run()
    ↓
send_notification()
```

## Streams-Only Recovery Path

```text id="streams-only"
platform.R streams_only
    ↓
load_config()
    ↓
resolve execution mode
    ↓
get_connection()
    ↓
create_etl_run(run_mode = STREAMS_ONLY)
    ↓
get_pending_stream_activity_ids()
    ↓
cap pending stream activity IDs
    ↓
ingest_streams()
    ↓
update_etl_run()
    ↓
send_notification()
```

## Responsibilities

| Function                  | Responsibility                                          |
| ------------------------- | ------------------------------------------------------- |
| `load_config()`           | Load platform configuration from `config/platform.yml`. |
| `create_etl_run()`        | Create a platform execution record and return `run_id`. |
| `ingest_activities()`     | Orchestrate activity ingestion.                         |
| `create_etl_run_entity()` | Create an entity execution record.                      |
| `get_activities()`        | Extract activities from the Strava API.                 |
| `upsert_activities()`     | Load activities into `raw.activities`.                  |
| `get_pending_stream_activity_ids()` | Return activities requiring stream ingestion. |
| `ingest_streams()`        | Orchestrate batched stream ingestion.                   |
| `get_streams()`           | Extract activity streams from the Strava API.           |
| `upsert_streams()`        | Load streams into `raw.activity_streams`.               |
| `get_pending_detail_activity_ids()` | Return activities requiring detail ingestion. |
| `ingest_activity_details()` | Orchestrate batched activity detail ingestion.        |
| `get_activity_details()`  | Extract full activity details from the Strava API.      |
| `upsert_activity_details()` | Load details into `raw.activity_details`.             |
| `get_pending_lap_activity_ids()` | Return activities requiring lap ingestion.       |
| `ingest_activity_laps()` | Orchestrate batched activity lap ingestion.             |
| `get_activity_laps()`    | Extract activity laps from the Strava API.              |
| `upsert_activity_laps()` | Load laps into `raw.activity_laps`.                     |
| `ingest_google_health_heart_rate()` | Orchestrate Google/Fitbit heart-rate response ingestion. |
| `get_google_health_heart_rate()` | Extract Google/Fitbit heart-rate responses.       |
| `upsert_google_health_data_points()` | Load response-grain rows into `raw.google_health_heart_rate_responses`. |
| `ingest_google_health_sleep_logs()` | Orchestrate Google Health sleep-log ingestion. |
| `ingest_google_health_daily_resting_heart_rate()` | Orchestrate source-reported daily RHR ingestion. |
| `ingest_google_health_daily_heart_rate_variability()` | Orchestrate source-reported daily HRV ingestion. |
| `ingest_google_health_daily_respiratory_rate()` | Orchestrate source-reported daily respiratory-rate ingestion. |
| `get_google_health_daily_summaries()` | Shared API shaping helper for low-volume daily Google Health summary data types. |
| `update_etl_run_entity()` | Record entity execution outcomes.                       |
| `update_etl_run()`        | Record overall execution outcomes.                      |
| `send_notification()`     | Send a summary notification.                            |

In `streams_only` mode, `ingest_activities()`,
`ingest_activity_details()`, and `ingest_activity_laps()` are intentionally
skipped.

## Error Handling

```text id="yd3smd"
Any step fails
        ↓
Update etl_run_entity(status = FAILED)
        ↓
Update etl_run(status = FAILED)
        ↓
Send notification
```

All failures should be logged with sufficient detail to support troubleshooting and reruns.

For streams, activity details, and activity laps, each batch is committed
independently. If a later batch fails because of a Strava rate limit or another
transient issue, completed batches remain marked `SUCCESS`; the current and
remaining activity IDs are marked `FAILED` and selected again on the next run.
