# Platform Architecture

## Data Flow

```text
Source APIs
  - Strava
  - Google Health / Fitbit
    ↓
    Raw
    ↓
  Stage  ← operational workspace only
    ↓
 Validate
    ↓
 Bulk merge
    ↓
 Silver / Gold
    ↓
 cycling-analytics / other consumers
```

### Consumers

* `cycling-analytics`
* `coastal`
* future MCP server

## Data Layers

The platform is organised into the following logical layers:

* `admin`
* `stage`
* `raw`
* `silver`
* `gold`

Silver layer design is documented in `docs/silver_layer_design.md`.

`cycling-platform` is responsible for ingestion, raw data, silver conformed
data, gold analytical objects, operational automation, monitoring, and data
quality.
`cycling-analytics` is responsible for dashboards, reports, exploratory
analysis, reusable analytical functions, MCP server work, AI coaching, and
replacing the legacy scraper project.

The `stage` schema is not part of the medallion architecture. It is temporary
ETL workspace only.

Schema responsibilities:

* `admin`: ETL metadata, run logging, and configuration metadata.
* `stage`: temporary ETL artefacts owned by `run_id`.
* `raw`: retained source data.
* `silver`: integrated and cleaned data.
* `gold`: reusable analytical assets.

## Current Operating Position

The platform raw and silver foundation is in place. The immediate goal is to
make that foundation operational through automation, monitoring, notifications,
and data quality checks.

Current status:

* Strava raw endpoints are deployed for activities, details, streams, and laps.
* Strava activities, details, streams, and laps are complete.
* Google Health/Fitbit Raw ingestion exists for heart-rate responses, sleep
  logs, daily resting heart rate, daily heart-rate variability, and daily
  respiratory rate. These objects are in Raw observation; health Silver and Gold
  transforms remain future work.
* `silver.activities` is complete.
* `silver.activity_streams` is complete following local repair/backfill.
* Coastal project is fully migrated to `cycling-platform`, complete, and no
  longer depends on the legacy scraper database.
* `cycling-analytics` has been created as an empty replacement project for the
  frozen legacy scraper.
* Platform automation v1 is in place for raw ingestion, Silver transforms,
  publication-gate validation, and notification.

The legacy scraper is frozen. It is now a reference implementation and
migration source only, not the target architecture. Scraper tables should not
be recreated one-for-one unless they represent reusable analytical concepts.

MCP development is deliberately paused until the cycling platform is stable,
automated, and no longer needs immediate revisiting.

## Bootstrap and Derived Layers

`bootstrap_platform.R` is for database and table setup. It runs install, admin,
stage, raw, and derived-layer create scripts only. It should not run silver or
gold transformation scripts because those can be long-running rebuilds over
existing raw data.

Derived layers are refreshed explicitly:

```sh
Rscript run_silver.R
```

This keeps raw/admin bootstrap safe to rerun without accidentally launching a
large silver stream expansion.

`platform.R` is currently a raw-ingestion orchestrator. The unattended wrapper
runs Silver transforms only after successful raw ingestion; `platform.R` itself
does not own derived-layer orchestration.

The v1 unattended command is:

```sh
Rscript run_daily_platform.R
```

It runs raw ingestion through `platform.R`, then runs Silver transforms only if
raw ingestion succeeds. Silver streams use repair mode for normal automation, so
the large stream table is not truncated and historical staging repair tooling is
not invoked.

After Silver transforms, `run_daily_platform.R` runs only fast publication-gate
checks. Deep validation runs separately via:

```sh
Rscript run_platform_validation.R
```

Validation run and check status is recorded in `cycling_platform_admin`.

Silver stream samples are rebuilt in activity batches so long rebuilds provide
progress feedback and avoid one large opaque database statement.

Interrupted silver stream rebuilds can be resumed in repair mode:

```sh
Rscript run_silver.R repair
```

Gold processing is orchestrated by `run_daily_platform.R` after successful
Silver publication checks. `platform.R` remains focused on Raw ingestion; the
daily wrapper owns Raw-to-Silver-to-Gold publication sequencing.

## Operational Lessons

Large historical repairs should not reuse the incremental ETL path. The Strava
stream backfill showed that historical silver rebuilds are a separate workload:
they need staging tables, bulk merge into indexed production tables, clear
timing logs, and recovery-oriented tooling. Incremental daily processing should
stay optimised for small reliable deltas; historical repair tooling should
prioritise throughput and recoverability.

Recommended pattern for large rebuilds:

```text
Raw
 ↓
Stage
 ↓
Validate
 ↓
Bulk merge
 ↓
Silver / Gold
```

Stage objects are safe to delete and should never be queried by dashboards,
analytics, MCP tools, or coaching workflows. Persistent business data belongs
only in raw, silver, or gold.

Stage housekeeping should be explicit:

* report orphaned stage rows before automated cleanup;
* report old retained stage rows before age-based cleanup;
* remove completed or obsolete stage data by `run_id`;
* remove old retained stage rows by age when they are no longer useful for
  investigation;
* truncate all stage tables only as a deliberate manual action.

## Transform Logging

Silver and gold transformations should write operational metadata to admin
tables. The initial implementation logs silver activity and stream rebuilds:

* `cycling_platform_admin.transform_run`: one row per transform run, including
  layer, entity, mode, status, planned batches, completed batches, activities,
  expected rows, inserted/deleted rows, timing, and errors.
* `cycling_platform_admin.transform_run_batch`: one row per transform batch,
  including batch number, status, activity count, expected rows,
  inserted/deleted rows, activity ID range, timing, and errors.

This supports progress tracking, recovery after failed batches, performance
review, and future automation notifications.

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

The platform currently supports four execution modes:

* `manual`: refreshes the routine activity window using
  `ingestion.activity_refresh_days`.
* `scheduled`: uses the same routine activity window as `manual`, but records
  the Raw ETL run as `SCHEDULED` for unattended automation.
* `backfill`: refreshes the historical activity window using
  `ingestion.activity_backfill_days`.
* `streams_only`: recovery mode that creates an ETL run, skips activities,
  details, and laps, then attempts pending stream ingestion only.

For `manual`, `scheduled`, and `backfill`, execution mode controls the activity
refresh window. Stream, detail, and lap ingestion are state-driven across the full
`raw.activities` table: all activities with `PENDING` or `FAILED` child-entity
status are selected, regardless of whether they were included in the current
activity refresh window.

`streams_only` exists for recovery after stream-specific issues. It caps the
number of attempted activities using `ingestion.streams_only_activity_limit`
when configured, otherwise it defaults to 900 pending stream activities.

```sh
Rscript platform.R
Rscript platform.R backfill
Rscript platform.R streams_only
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

Stream payload JSON is serialised with `digits = NA` so Strava latitude and
longitude values retain full numeric precision. Earlier historical stream
payloads were written with jsonlite's default numeric precision, which rounded
`latlng` coordinates to around four decimal places. Existing raw stream data
loaded before that fix should be treated as insufficiently precise for mapping
and location-sensitive analytics until the raw stream payloads are fully
reloaded from Strava.

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

# `raw.activity_laps` Design

## Grain

One row per `activity_id` x `lap_index`.

## Business Key

(`activity_id`, `lap_index`)

## Load Strategy

UPSERT using (`activity_id`, `lap_index`) as the business key.

Activity laps are ingested in configurable activity ID batches. Each batch is
committed independently and updates `raw.activities.laps_status` for
successful, missing, or failed activity IDs.

Pending lap work is discovered from `raw.activities.laps_status`, not from the
current activity refresh window.

## Raw Data Retention

- Retain the complete lap payload returned by the API.
- Store the payload in `lap_payload`.
- Preserve lap order using `lap_index`.
- Keep raw lap data available for future silver/gold modelling.
