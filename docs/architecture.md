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

## Database Schemas

* `admin`
* `raw`
* `silver`
* `gold`

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

---

# `raw.activities` Design

## Grain

* One row per Strava activity

## Load Strategy

* `UPSERT` using `activity_id` as the business key
* Activities are refreshed using a rolling refresh window
* The Strava API does not expose a reliable activity modification timestamp

### Daily Run

```text
Refresh last 30 days
        ↓
UPSERT by activity_id
```

### Monthly Hygiene Run

```text
Refresh last 365 days
        ↓
UPSERT by activity_id
```

### Annual Hygiene Run

```text
Refresh all activities
        ↓
UPSERT by activity_id
```

## Raw Data Retention

* Retain the complete API response payload
* Store the payload in `raw_payload`
* Treat `raw_payload` as the source of truth
* Promote commonly queried fields to dedicated columns

## Design Principles

* Preserve source-system fidelity
* Support idempotent ingestion
* Prioritise auditability and lineage
* Optimise for convergence rather than change detection
* Separate ingestion concerns from analytics concerns


raw_payload is stored using MariaDB's JSON type, which is implemented as validated text in MariaDB 10.5.