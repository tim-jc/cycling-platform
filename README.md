# Cycling Platform

Personal cycling data platform for Strava and selected Google/Fitbit health
data.

The immediate goal is practical: finish the silver stream backfill, build the
first gold analytical objects, and prepare `cycling-analytics` to replace the
old scraper project.

## Current Status

Implemented and deployed:

* Strava raw ingestion for activities, activity details, activity streams, and
  activity laps.
* Silver transforms for activities and activity streams.
* ETL run and entity logging.
* Local smoke checks and focused regression tests.
* Backup runbook and MariaDB dump script.

In progress:

* Local silver stream transformation/backfill is in the final stages.
* Google/Fitbit raw ingestion for heart rate and sleep. This exists but is
  early and not yet production-ready.
* `cycling-analytics` has been created as an empty replacement project for the
  old scraper.

Not yet in place:

* Platform automation.
* Routine monitoring.
* Fully validated notification workflow.
* Gold analytics models.
* MCP server or AI coaching features.

## Current Priority

The project is currently focused on platform stabilisation and the data
foundation needed by `cycling-analytics`.

The Coastal project repoint is complete. `cycling-platform` owns ingestion and
the raw/silver/gold data foundation, plus automation and operational monitoring.
`cycling-analytics` will own dashboards, reports, exploratory analysis,
reusable analytics, MCP, AI coaching, and the legacy scraper replacement.

The old scraper is a migration source only, not the target architecture. Do not
recreate scraper tables one-for-one unless they represent reusable analytical
concepts.

MCP development is deliberately paused until the cycling platform is stable,
automated, and no longer needs immediate revisiting.

## Roadmap

1. Platform foundation: Strava raw and silver.
2. Gold analytical layer.
3. Platform automation and operational readiness.
4. `cycling-analytics` migration.
5. MCP development.
6. AI coaching.

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
