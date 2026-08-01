# Cycling Platform

Personal cycling data platform for Strava and selected Google/Fitbit health
data.

`cycling-platform` owns source ingestion, Raw persistence, Silver transforms,
Gold data products, validation, notifications, and operational metadata.
Downstream projects such as `cycling-analytics` and `coastal` connect
independently to the curated production databases; they do not run ingestion.

## Operating Model

Development happens primarily on an Apple Silicon Mac. Native macOS R is useful
for interactive development, debugging, SQL exploration, and fast tests.
`renv.lock` controls R package versions.

The authoritative production runtime is the Docker image defined by
`Dockerfile`. Local container testing on the Mac is the portability check before
deployment. Both the Mac and the Raspberry Pi production host are ARM64, which
provides strong architecture parity, while Docker also checks Linux system
dependencies and filesystem assumptions that native macOS execution cannot.

Production runs on a Raspberry Pi 5 named `cycling-prod`, using Raspberry Pi OS
Lite / Debian:

* MariaDB 11.8 runs continuously under Docker Compose.
* `cycling-platform` is not a continuous service. It runs as an ephemeral job
  container.
* Normal execution is `docker compose run --rm cycling-platform`.
* The image default command is `Rscript run_daily_platform.R scheduled`.
* Deep validation is a separate ephemeral job.
* Platform scheduling belongs on `cycling-prod`; legacy Mac scheduling is being
  retired.
* Logical backups run from the Mac and remain off the Pi.

See [Development and Deployment](docs/development_and_deployment.md) for the
full workflow.

For Strava credential administration, use [Strava
Authentication](docs/strava_authentication.md). For a new or changed API
source, follow [Add an API Endpoint](docs/runbooks/add-api-endpoint.md) from
design through scheduled production acceptance.

## Data Architecture

The platform uses five MariaDB databases:

| Database | Responsibility |
| --- | --- |
| `cycling_platform_admin` | ETL, control, audit, transform, notification, and validation metadata |
| `cycling_platform_raw` | Source-aligned persisted ingestion |
| `cycling_platform_stage` | Disposable rebuild and working state |
| `cycling_platform_silver` | Canonical transformed data |
| `cycling_platform_gold` | Derived, consumer-facing data products |

There is no single `cycling` application database. Application connections must
select an appropriate platform database. Control and cross-database operations
normally enter through `cycling_platform_admin`; they must not assume access to
the MariaDB `mysql` system database.

The Stage database is intentionally excluded from backups and must not be used
by consumers. Technical details are in [Platform
Architecture](docs/architecture.md).

All five databases use the explicit platform standard `utf8mb4` /
`utf8mb4_general_ci` with InnoDB tables. Schema DDL never relies on a MariaDB
server default; bootstrap also applies checksum-protected versioned migrations
needed after upgrades or restores.

## Production Commands

From the Compose project directory on `cycling-prod`, normal scheduled
processing uses the image default command:

```sh
docker compose run --rm cycling-platform
```

The explicit equivalent is:

```sh
docker compose run --rm cycling-platform \
  Rscript run_daily_platform.R scheduled
```

Run deep validation separately:

```sh
docker compose run --rm cycling-platform \
  Rscript run_platform_validation.R
```

Long-running manual Silver runs publish durable heartbeat/status JSON. Inspect
the latest full rebuild from another session with:

```sh
docker compose run --rm cycling-platform \
  Rscript scripts/show_job_status.R silver-full
```

See the [manual job status runbook](docs/runbooks/manual-job-status.md) for
staleness, persistent host paths, history, and failure interpretation.

Pulling new source onto `cycling-prod` does not update an existing image because
the application is copied into the image at build time. Rebuild after
application code, SQL, `renv.lock`, or `Dockerfile` changes:

```sh
git pull
docker compose build cycling-platform
```

Then run the relevant smoke check or operational command before relying on the
next scheduled job.

The infrastructure repository owns the production checkout, Compose file,
mounts, host permissions, scheduler, and deployment wrapper. This repository
owns the image contents and application commands; see [Development and
Deployment](docs/development_and_deployment.md#repository-ownership-boundary).

## Native Development Commands

Run these from the repository root on the Mac when native R is appropriate:

```sh
# Routine Raw ingestion only
Rscript platform.R manual

# Full Raw-to-Silver-to-Gold scheduled pipeline
Rscript run_daily_platform.R scheduled

# Monthly configured-window activity hygiene and selective repair
Rscript run_daily_platform.R hygiene

# Annual configured-history reconciliation; achievement alerts suppressed
Rscript run_daily_platform.R activity_backfill

# Deep validation
Rscript run_platform_validation.R

# Fast repository checks
Rscript --vanilla tests/smoke_check.R

# Focused regression suite
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
```

Native success does not prove Linux/container portability. Build and test the
Docker image before production deployment where practical.

## Execution Modes

Normal scheduled execution is incremental and assumes the platform databases
and tables already exist. A brand-new database is a different workflow.

Canonical initial-load sequence:

```sh
Rscript bootstrap_platform.R
Rscript platform.R backfill
Rscript run_silver.R repair
Rscript run_gold_activity_best_efforts.R backfill
Rscript run_gold_activity_achievements.R backfill
Rscript run_daily_platform.R scheduled
```

When running on `cycling-prod`, prefix each command with
`docker compose run --rm cycling-platform`.

Other recovery and maintenance commands:

```sh
# Pending stream recovery only
Rscript platform.R streams_only

# Silver repair or full rebuild
Rscript run_silver.R repair
Rscript run_silver.R full

# Gold repair/backfill
Rscript run_gold_activity_best_efforts.R repair
Rscript run_gold_activity_best_efforts.R backfill
Rscript run_gold_activity_achievements.R repair
Rscript run_gold_activity_achievements.R backfill

# Notifications
Rscript run_platform_notifications.R queue_and_deliver

# Google Health credential check
Rscript run_google_health_auth_check.R
```

Detailed behaviour is documented in [Platform
Automation](docs/platform_automation.md) and [Historical
Backfill](docs/historical_backfill.md).

Strava gear is ingested after activities and before child activity endpoints.
Raw retains distinct source observations; Silver publishes one canonical
resolved row per gear ID. Ride-summary consumers join
`silver.activities.gear_id` to `silver.gear.gear_id`. See the
[endpoint-onboarding runbook](docs/runbooks/add-api-endpoint.md), which uses
gear as the reference implementation.

## Configuration and Secrets

`.Renviron.example` lists required secret names without values:

* MariaDB: `MARIADB_HOST`, `MARIADB_PORT`, `MARIADB_USER`,
  `MARIADB_PASSWORD`
* Strava: `STRAVA_CLIENT_ID`, `STRAVA_CLIENT_SECRET`,
  `STRAVA_REFRESH_TOKEN`
* Google Health: `GOOGLE_HEALTH_CLIENT_ID`,
  `GOOGLE_HEALTH_CLIENT_SECRET`, `GOOGLE_HEALTH_REFRESH_TOKEN`
* Notifications: `NTFY_TOPIC`

For native Mac execution, place values in the ignored project `.Renviron`.
Production Compose injects client credentials and bind-mounts a persistent
runtime `.Renviron` for rotating refresh tokens. The mounted file is selected
with `CYCLING_PLATFORM_RENVIRON_PATH` and `R_ENVIRON_USER` at
`/run/cycling-platform/runtime.Renviron`, backed by the host file
`/srv/cycling/config/platform/runtime.Renviron`. `.Renviron` is excluded from
the Docker build context and secrets must never be baked into the image or
committed. See [Strava Authentication](docs/strava_authentication.md) for the
interactive bootstrap and scope-expansion procedure.

Non-secret runtime behaviour is configured in `config/platform.yml`.

## Backups

`scripts/backup_mariadb.sh` creates compressed logical dumps of Admin, Raw,
Silver, and Gold. Stage is excluded intentionally. The backup job runs on the
Mac against MariaDB on `cycling-prod`, keeping the dumps off-host from the Pi SD
card. Each fully verified run writes `backups/latest_success.json`, records
append-only run/file metadata in `cycling_platform_admin`, and reconciles the
30-day Mac file set. Existing platform notifications report freshness and
retention health; the backup does not send a separate success notification.

See [Backup and Recovery](docs/backup_and_recovery.md).

## Documentation Map

- [Data contract governance](docs/data_contract_governance.md) — Silver/Gold contract authority, lifecycle, TODOs and validation.

* [Architecture and data layers](docs/architecture.md)
* [Development and deployment](docs/development_and_deployment.md)
* [Automation, run modes, and validation](docs/platform_automation.md)
* [Backup and recovery](docs/backup_and_recovery.md)
* [Data quality](docs/data_quality.md)
* [Google Health authentication](docs/google_health_authentication.md)
* [Backlog and technical debt](docs/backlog.md)
* [Add an API endpoint](docs/runbooks/add-api-endpoint.md)
