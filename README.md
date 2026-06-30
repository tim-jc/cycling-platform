# Cycling Platform

Personal cycling data platform for Strava and selected Google/Fitbit health
data.

The immediate goal is practical: build enough reliable raw and silver data to
repoint existing dashboards from the old scraper database to
`cycling-platform`, then decommission the old scraper database.

## Current Status

Implemented and deployed:

* Strava raw ingestion for activities, activity details, activity streams, and
  activity laps.
* Silver transforms for activities and activity streams.
* ETL run and entity logging.
* Local smoke checks and focused regression tests.
* Backup runbook and MariaDB dump script.

In progress:

* Strava laps historical backfill. Activities, details, and streams are
  substantially backfilled; laps remain API-limited and are expected to take a
  few more days.
* Local silver stream transformation/backfill. This is expected to complete
  soon and is required for dashboard migration.
* Google/Fitbit raw ingestion for heart rate and sleep. This exists but is
  early and not yet production-ready.

Not yet in place:

* Platform automation.
* Routine monitoring.
* Fully validated notification workflow.
* Gold analytics models.
* MCP server or AI coaching features.

## Current Priority

The project is currently focused on platform stabilisation and legacy scraper
replacement.

MCP development is deliberately paused until the cycling platform is stable,
automated, and no longer needs immediate revisiting.

## Roadmap

1. Platform stabilisation and legacy scraper replacement.
2. Automation and operational reliability.
3. Gold analytics layer.
4. MCP learning and development.
5. AI coaching features built on top of MCP and platform analytics.

Detailed milestones are tracked in `docs/backlog.md`.

## Architecture

The platform uses a lakehouse-inspired layered structure:

```text
Raw
  ↓
Silver
  ↓
Gold
  ↓
Consumers
```

Logical schemas:

* `cycling_platform_admin`
* `cycling_platform_raw`
* `cycling_platform_silver`
* `cycling_platform_gold`

Technical architecture is documented in `docs/architecture.md`.

## Common Commands

Bootstrap database objects:

```sh
Rscript bootstrap_platform.R
```

Run routine platform ingestion:

```sh
Rscript platform.R
```

Run historical Strava activity discovery:

```sh
Rscript platform.R backfill
```

Run stream-only recovery:

```sh
Rscript platform.R streams_only
```

Run silver transforms:

```sh
Rscript run_silver.R
Rscript run_silver.R repair
```

Run smoke checks:

```sh
Rscript --vanilla tests/smoke_check.R
```
