# Platform Architecture

## Data Flow

```text
Strava API
    ↓
    Raw
    ↓
   Silver
    ↓
    Gold
    ↓
 Consumers
```

### Consumers

* Dashboard
* MCP

## Data Layers

The platform is organised into the following logical layers:

* `admin`
* `raw`
* `silver`
* `gold`

Silver layer design is documented in `docs/silver_layer_design.md`.

## ETL Lifecycle

```text
Create run
    ↓
Ingest entity
    ↓
Log entity result
    ↓
Repeat
    ↓
Complete run
    ↓
Notify
```

### Allowed `run_status` Values

* `RUNNING`
* `SUCCESS`
* `FAILED`

## Execution Modes

The platform currently supports two execution modes:

* `manual`: refreshes the routine activity window using
  `ingestion.activity_refresh_days`.
* `backfill`: refreshes the historical activity window using
  `ingestion.activity_backfill_days`.

Execution mode only controls the activity refresh window. Stream and activity
detail ingestion are always state-driven across the full `raw.activities` table:
all activities with `PENDING` or `FAILED` child-entity status are selected,
regardless of whether they were included in the current activity refresh window.

```sh
Rscript platform.R
Rscript platform.R backfill
```

---

## `raw.activities` Design

### Grain

* One row per Strava activity.

### Business Key

* `activity_id`

### Load Strategy

* Use `UPSERT` with `activity_id` as the business key.
* Activities are refreshed using a rolling refresh window.
* The Strava API does not expose a reliable activity modification timestamp.

#### Daily Run

```text
Refresh last 30 days
        ↓
UPSERT by activity_id
```

#### Monthly Hygiene Run

```text
Refresh last 365 days
        ↓
UPSERT by activity_id
```

#### Annual Hygiene Run

```text
Refresh all activities
        ↓
UPSERT by activity_id
```

### Raw Data Retention

* Retain the complete API response payload.
* Store the payload in `raw_payload`.
* Treat `raw_payload` as the source of truth.
* Promote commonly queried fields to dedicated columns.

### Design Principles

* Preserve source-system fidelity.
* Support idempotent ingestion.
* Prioritise auditability and lineage.
* Optimise for convergence rather than change detection.
* Separate ingestion concerns from analytics concerns.

### JSON Storage

`raw_payload` is stored using MariaDB's `JSON` type.

In MariaDB 10.5, the `JSON` type is implemented as validated text rather than a native binary JSON format.

The platform treats `raw_payload` as an immutable copy of the source API response.


# `raw.activity_streams` Design

## Grain

One row per `activity_id` × `stream_type`.

## Business Key

(`activity_id`, `stream_type`)

## Load Strategy

UPSERT using (`activity_id`, `stream_type`) as the business key.

Streams are ingested in configurable activity ID batches. Each batch is fetched,
loaded, and status-marked inside its own database transaction so long historical
backfills can resume after rate limits or interruptions.

Pending stream work is discovered from `raw.activities.stream_status`, not from
the current activity refresh window.

## Raw Data Retention

- Retain the complete stream payload returned by the API.
- Store the payload in `stream_payload`.
- Treat `stream_payload` as the source of truth.
- Promote commonly queried metadata to dedicated columns.

## Design Principles

- Preserve source-system fidelity.
- Minimise transformation in the raw layer.
- Support idempotent ingestion.
- Optimise for reprocessing and downstream flexibility.

# `raw.activity_details` Design

## Grain

One row per Strava activity.

## Business Key

`activity_id`

## Load Strategy

UPSERT using `activity_id` as the business key.

Activity details are ingested in configurable activity ID batches. Each batch is
committed independently and updates `raw.activities.details_status` for
successful, missing, or failed activity IDs.

Pending detail work is discovered from `raw.activities.details_status`, not from
the current activity refresh window.

## Raw Data Retention

- Retain the complete activity detail payload returned by the API.
- Store the payload in `details_payload`.
- Treat `details_payload` as the source of truth.
- Promote fields into curated layers later rather than expanding raw
  transformation logic.

## Design Principles

- Preserve source-system fidelity.
- Support idempotent ingestion.
- Keep raw activity details available for future silver/gold modelling.
- Support resumable historical backfills.
