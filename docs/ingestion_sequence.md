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
