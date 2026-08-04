# Specialist Scripts

Run these commands from the repository root. Broad platform entry points remain
in the repository root; this directory contains narrower operator and developer
utilities.

## Google Health

`google_health/` contains manual endpoint runners, the authentication check,
the capability probe, and the source-provenance backfill.

## Strava

`strava/bootstrap_oauth.R` is the canonical manual OAuth bootstrap and
re-authorisation command.

## Gold

`gold/` contains the independent activity best-effort and achievement repair
and backfill runners.

## Audits

`audits/` contains read-only or report-producing implementation-alignment and
classification audits.

## Contracts

`contracts/generate_metadata.R` refreshes generated physical metadata and
`contracts/validate.R` validates managed data contracts.

## Operations

`operations/run_notifications.R` manages achievement notification queueing and
delivery. `operations/show_job_status.R` reads durable status for long-running
manual jobs.

Backup tooling remains together at `backup_mariadb.sh` and
`finalize_backup_observability.R`. The root-level shell wrappers in this
directory are retained compatibility and host-orchestration tools.
