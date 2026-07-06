# ADR-001: Introduce Stage Schema for Historical Rebuilds

## Context

During the historical Strava stream backfill, direct writes into
`cycling_platform_silver.activity_streams` became slow and unreliable. The
workload was much larger than the expected daily incremental processing pattern:
many activities, many stream samples, and repeated writes into an indexed Silver
table hosted on the Raspberry Pi.

The platform already separated persistent business data into Raw, Silver, and
Gold layers, with Admin used for run metadata. The backfill exposed the need for
a separate operational workspace that could support rebuilds without treating
temporary rows as platform data products.

## Problem

Historical rebuilds and repair jobs have different characteristics from routine
incremental ETL:

* they may process a large volume of rows;
* they need resumability and inspection when interrupted;
* they should avoid repeatedly writing directly into indexed production tables;
* they should not pollute Raw, Silver, or Gold with temporary artefacts;
* failed rebuild attempts should leave enough evidence to diagnose the issue.

The platform needed a controlled place to build, validate, and merge temporary
rows without weakening the medallion-layer responsibilities.

## Alternatives Considered

### Write directly into Silver

This was the simplest approach and matched the first repair implementation.
However, it performed poorly for large historical stream rebuilds and made
failure recovery riskier because delete and insert work happened directly
against the production Silver table.

### Create temporary per-run tables

Per-run physical tables would isolate rebuild attempts, but they would create
schema sprawl and require extra lifecycle management. They would also make
generic housekeeping and monitoring harder.

### Use local files as rebuild intermediates

Local files could reduce database pressure during row construction, but they
would be harder to inspect, validate, resume, and merge consistently from the
platform itself.

### Add a dedicated Stage schema

A dedicated schema gives rebuild tooling a database-native workspace while
keeping temporary artefacts out of Raw, Silver, and Gold. A shared staging table
with mandatory `run_id` ownership avoids per-run table sprawl and supports
targeted cleanup.

## Decision

Introduce `cycling_platform_stage` as a dedicated operational schema.

The Stage schema is not part of the medallion architecture. It exists only as
temporary ETL workspace. Stage rows must be owned by `run_id`, must not be
queried by dashboards or analytics, and must be safe to delete when no longer
needed.

Historical rebuilds should generally follow this pattern:

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

For Silver stream repair, `cycling_platform_stage.activity_streams_build` is the
reference implementation. Rows are staged under a `run_id`, validated against
Raw expected sample counts, merged into Silver in activity-ID batches, and
removed from Stage only after successful merge.

## Consequences

Positive consequences:

* historical rebuilds no longer need to write directly into indexed Silver
  tables row-by-row;
* interrupted rebuilds are easier to inspect and resume;
* temporary ETL artefacts are clearly separated from persistent platform data;
* stage housekeeping can be standardised across future rebuild tools;
* the platform now has a reusable pattern for large Raw-to-Silver and
  Raw-to-Gold rebuilds.

Trade-offs and responsibilities:

* Stage introduces another schema that must be bootstrapped and monitored;
* every staged row needs clear `run_id` ownership;
* stale stage rows must be reported and cleaned up deliberately;
* automated merges should require scoped `run_id` usage;
* manual rescue modes may exist, but they must be explicit and clearly logged;
* Stage must not become a hidden data product or compatibility layer.

This decision supports operational reliability while preserving the core rule
that persistent business data belongs only in Raw, Silver, or Gold.
