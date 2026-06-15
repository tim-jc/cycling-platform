ETL Lifecycle

Overview

All ingestion processes follow a standard lifecycle to ensure consistency, observability, and auditability.

Each platform execution creates a single record in admin.etl_run.

Each entity processed within that execution creates a corresponding record in admin.etl_run_entity.

Workflow

Create etl_run
        ↓
Discover entities to ingest
        ↓
For each entity:
    Create etl_run_entity
            ↓
    Extract data from source
            ↓
    Load data into raw schema
            ↓
    Update etl_run_entity
        ↓
Complete etl_run
        ↓
Send notification

Run Lifecycle

Start Run

Insert a record into admin.etl_run with:

* run_status = RUNNING
* started_at = current_timestamp
* run_mode = MANUAL | SCHEDULED | BACKFILL

Capture the generated run_id.

Entity Lifecycle

For each entity:

Insert a record into admin.etl_run_entity with:

* entity_status = RUNNING
* started_at = current_timestamp

Perform:

1. Extract data from source API
2. Apply minimal transformations required for loading
3. Load data into the raw schema

Update admin.etl_run_entity with:

* rows_inserted
* rows_updated
* rows_deleted
* completed_at
* duration_seconds
* entity_status
* error_message

Complete Run

When all entities have completed:

* Set run_status = SUCCESS if all entities succeeded
* Set run_status = FAILED if one or more entities failed

Update:

* completed_at
* duration_seconds
* error_message

Notifications

Send a notification summarising:

* run_id
* run_status
* duration_seconds
* entities processed
* rows inserted
* rows updated

Principles

* Raw data is loaded with minimal transformation.
* All platform activity is auditable.
* All ingestion processes are idempotent.
* Failures are logged and observable.
* Notifications summarise operational outcomes.