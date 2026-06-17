# ETL Lifecycle

## Overview

All ingestion processes follow a standard lifecycle to ensure consistency, observability, and auditability.

Each platform execution creates a single record in `admin.etl_run`.

Each entity processed within that execution creates a corresponding record in `admin.etl_run_entity`.

A single `run_id` represents the complete execution of an ingestion workflow.

## Workflow

```text
Create etl_run
        ↓
Discover entities to ingest
        ↓
For each entity:
    Create etl_run_entity
            ↓
    Extract data from source
            ↓
    Load data into raw layer
            ↓
    Update etl_run_entity
        ↓
Complete etl_run
        ↓
Send notification
```

## Run Lifecycle

### Start Run

Insert a record into `admin.etl_run` with:

* `run_status = RUNNING`
* `started_at = CURRENT_TIMESTAMP`
* `run_mode = MANUAL | SCHEDULED | BACKFILL`

Capture the generated `run_id`.

## Entity Lifecycle

For each entity:

Insert a record into `admin.etl_run_entity` with:

* `entity_status = RUNNING`
* `started_at = CURRENT_TIMESTAMP`

Perform:

1. Extract data from the source API.
2. Apply minimal transformations required for loading.
3. Load data into the `raw` layer.

Update `admin.etl_run_entity` with:

* `rows_inserted`
* `rows_updated`
* `rows_deleted`
* `completed_at`
* `duration_seconds`
* `entity_status`
* `error_message`

### Allowed `entity_status` Values

* `RUNNING`
* `SUCCESS`
* `FAILED`

## Complete Run

When all entities have completed:

* Set `run_status = SUCCESS` if all entities succeeded.
* Set `run_status = FAILED` if one or more entities failed.

Update:

* `completed_at`
* `duration_seconds`
* `error_message`

### Allowed `run_status` Values

* `RUNNING`
* `SUCCESS`
* `FAILED`

## Notifications

Send a notification summarising:

* `run_id`
* `run_mode`
* `run_status`
* `duration_seconds`
* Number of entities processed
* Total rows inserted
* Total rows updated
* Error summary, if applicable

## Principles

* Raw data is loaded with minimal transformation.
* All platform activity is auditable.
* All ingestion processes are idempotent.
* Failures are logged and observable.
* Notifications summarise operational outcomes.
