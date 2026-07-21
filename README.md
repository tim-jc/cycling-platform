# Cycling Platform

Personal cycling data platform for Strava and selected Google/Fitbit health
data.

The immediate goal is practical: automate the stable raw and silver foundation,
build the first gold analytical objects, and prepare `cycling-analytics` to
replace the frozen legacy scraper project.

## Current Status

Implemented and deployed:

* Strava raw ingestion for activities, activity details, activity streams, and
  activity laps.
* Silver transforms for activities and activity streams.
* Coastal project migration to `cycling-platform`.
* ETL run and entity logging.
* Platform automation v1 for raw ingestion, Silver transforms, publication-gate
  validation, and notification.
* Local smoke checks and focused regression tests.
* Backup runbook and MariaDB dump script.

In progress:

* Google Health/Fitbit Raw observation for heart-rate responses, sleep logs,
  daily resting heart rate, daily heart-rate variability, and daily
  respiratory rate. These Raw entities are implemented; health Silver and Gold
  modelling remain future work.
* `cycling-analytics` has been created as an empty replacement project for the
  frozen legacy scraper.

Not yet in place:

* Routine monitoring.
* MCP server or AI coaching features.

## Current Priority

The project is currently focused on platform stabilisation and the data
foundation needed by `cycling-analytics`.

The Coastal project repoint is complete. `cycling-platform` owns ingestion and
the raw/silver/gold data foundation, plus operational automation, monitoring,
and data quality. `cycling-analytics` will own dashboards, reports,
exploratory analysis, reusable analytical functions, MCP, AI coaching, and the
legacy scraper replacement.

The legacy scraper is frozen and is now a reference implementation only. Do not
recreate scraper architecture or tables one-for-one unless they represent
reusable analytical concepts.

MCP development is deliberately paused until the cycling platform is stable,
automated, and no longer needs immediate revisiting.

## Roadmap

1. Platform foundation: Strava raw and silver.
2. Platform automation and operational readiness.
3. Gold analytical layer.
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
* `cycling_platform_stage`
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

Run unattended raw-to-Silver-to-Gold platform automation:

```sh
Rscript run_daily_platform.R
```

This runs fast publication-gate checks only. Deep validation is scheduled
separately so long-running audits cannot block successful Silver publication.

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

Run Gold activity best efforts:

```sh
Rscript run_gold_activity_best_efforts.R repair
Rscript run_gold_activity_best_efforts.R backfill
```

Run Gold activity achievements:

```sh
Rscript run_gold_activity_achievements.R repair
Rscript run_gold_activity_achievements.R backfill
```

Audit power-source classification:

```sh
Rscript run_power_source_classification_audit.R power_source_audit.csv
```

Run queued platform notifications:

```sh
Rscript run_platform_notifications.R queue_and_deliver
```

Check Google Health OAuth refresh:

```sh
Rscript run_google_health_auth_check.R
```

Google Health scopes and token regeneration are documented in
`docs/google_health_authentication.md`.

Probe Google Health recovery data availability without writing to the database:

```sh
env RENV_CONFIG_AUTOLOADER_ENABLED=false Rscript run_google_health_capability_probe.R
```

Run the source-reported daily recovery Raw ingestions manually:

```sh
Rscript run_google_health_daily_resting_heart_rate.R refresh
Rscript run_google_health_daily_heart_rate_variability.R refresh
Rscript run_google_health_daily_respiratory_rate.R refresh
```

Run deep platform completeness validation:

```sh
Rscript run_platform_validation.R
Rscript run_platform_validation.R --silver-only
```

`Rscript validate_platform.R` remains as a compatibility wrapper.

Run smoke checks:

```sh
Rscript --vanilla tests/smoke_check.R
```
