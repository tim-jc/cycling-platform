# Ingestion Sequence

## Overview

The platform orchestrates ingestion through a standard execution flow.

Each execution creates a single `run_id` in `admin.etl_run`.

All entity-level processing is associated with that `run_id` through `admin.etl_run_entity`.

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
| `update_etl_run_entity()` | Record entity execution outcomes.                       |
| `update_etl_run()`        | Record overall execution outcomes.                      |
| `send_notification()`     | Send a summary notification.                            |

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

For streams and activity details, each batch is committed independently. If a
later batch fails because of a Strava rate limit or another transient issue,
completed batches remain marked `SUCCESS`; the current and remaining activity
IDs are marked `FAILED` and selected again on the next run.
