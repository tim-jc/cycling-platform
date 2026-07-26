# Backup and Recovery

## Purpose

The historical raw load is expensive to recreate because activity details and
streams require one API request per activity. Once populated, the raw and admin
databases should be treated as valuable platform state.

The known raw stream coordinate precision issue is an exception where a full
raw stream reload is required. Backups still matter before that work begins:
they preserve current state if the reload is interrupted or exposes a migration
problem.

## Current Position

Backup configuration exists in `config/platform.yml`.

The backup implementation is `scripts/backup_mariadb.sh`. It creates
timestamped compressed `mysqldump` backups for the configured platform
databases, applies local retention cleanup, and reconciles the retained files
against durable operational metadata.

The intended job runs on the Mac, connects across the network to MariaDB on
`cycling-prod`, and stores dumps under the Mac checkout (or another configured
Mac path). Backups must remain off-host from the production Pi so loss or
corruption of its SD card does not also remove the recovery copy.

Until restore testing is complete:

* avoid destructive database bootstrap on populated environments
* prefer migrations over rebuilds
* take a manual backup before schema changes
* test restore commands before relying on backups operationally

## Databases to Back Up

Configured databases:

* `cycling_platform_admin`
* `cycling_platform_raw`
* `cycling_platform_silver`
* `cycling_platform_gold`

`cycling_platform_stage` is deliberately excluded because stage objects are
temporary ETL workspace and safe to delete.

## Manual Backup

Run from the project root:

```sh
scripts/backup_mariadb.sh
```

The script reads MariaDB connection settings from environment variables. If a
project `.Renviron` file exists, it is sourced first.

Required values:

* `MARIADB_HOST`
* `MARIADB_PORT`
* `MARIADB_USER`
* `MARIADB_PASSWORD`

Optional values:

* `BACKUP_DIR`, defaults to `backups.directory`
* `BACKUP_RETENTION_DAYS`, defaults to `backups.retention_days`
* `BACKUP_TEMPORARY_FILE_RETENTION_DAYS`, defaults to
  `backups.temporary_file_retention_days`
* `BACKUP_LOCK_DIR`, defaults to `backups.lock_dir`
* `BACKUP_LOCK_MAX_AGE_SECONDS`, defaults to `backups.lock_max_age_seconds`
* `BACKUP_DUMP_MAX_ATTEMPTS`, defaults to `backups.dump_max_attempts`
* `BACKUP_DUMP_RETRY_SLEEP_SECONDS`, defaults to
  `backups.dump_retry_sleep_seconds`
* `BACKUP_STATUS_FILE`, defaults to `backups/latest_success.json` under the
  configured backup directory
* `MYSQLDUMP`, optional absolute path to `mysqldump` or `mariadb-dump`

The script resolves the dump client from `backups.dump_command_candidates`,
then falls back to `mysqldump` or `mariadb-dump` on `PATH`. This is needed
because cron often runs with a much smaller `PATH` than an interactive shell.

Before dumping any database, the script performs a TCP connectivity preflight
to `MARIADB_HOST:MARIADB_PORT` when `nc` is available. If the Raspberry Pi is
offline, name/address resolution has changed, MariaDB is stopped, or the
configured port is not reachable, the backup fails before creating partial dump
files.

The TCP preflight only proves that the port is reachable. The actual
`mysqldump` connection can still fail transiently, so each configured database
dump is retried according to `backups.dump_max_attempts` and
`backups.dump_retry_sleep_seconds`.

Output shape:

```text
backups/
  latest_success.json
  2026-06-23_230000_cycling_platform_admin.sql.gz
  2026-06-23_230000_cycling_platform_raw.sql.gz
  2026-06-23_230000_cycling_platform_silver.sql.gz
  2026-06-23_230000_cycling_platform_gold.sql.gz
```

Backup files are ignored by git.

`latest_success.json` is updated atomically only after all four expected dumps
have passed verification. A failed or incomplete backup therefore leaves the
previous successful artefact intact. It contains the UTC start/completion
timestamps, Mac backup host, MariaDB source host, filename prefix, database
list, filenames, compressed/uncompressed byte counts, and per-file verification
timestamps.

The same successful run is recorded append-only in:

* `cycling_platform_admin.backup_run`
* `cycling_platform_admin.backup_run_file`

Backup metadata is deliberately retained beyond the 30-day file window. It is
small operational history and is not deleted when physical dumps expire.

## Verification and Cleanup

For each configured database, the script writes to a `.tmp` file first. The file
is promoted to the final `.sql.gz` name only after:

* TCP connectivity to the configured MariaDB host and port succeeds, where
  `nc` is available
* `mysqldump | gzip` exits successfully
* the temporary file is non-empty
* `gzip -t` passes
* `gzip -l` reports a non-zero uncompressed dump size

This verifies that the compressed dump was written cleanly. It is not a full
restore test; restore verification remains a separate operational task.

Retention cleanup removes:

* completed `*.sql.gz` backups older than `backups.retention_days`
* stale `*.sql.gz.tmp` files older than
  `backups.temporary_file_retention_days`

After cleanup, the Mac compares physical `*.sql.gz` files with successful
backup metadata and appends a result to
`cycling_platform_admin.backup_reconciliation_run`. Reconciliation detects:

* missing files for successful runs still inside the retention window
* successful retained runs without exactly Admin, Raw, Silver, and Gold
* retained files without managed backup metadata
* files older than the configured retention threshold
* malformed filenames and unexpected schemas, including Stage

Metadata older than the retention window is not treated as missing when its
physical files have expired normally. Files predating the first observability
record are not treated as orphans during rollout, but expired legacy files are
still detected.

If metadata recording fails after dumps succeed, the verified files and local
success artefact remain in place and the script exits with an error. It does
not delete a valid new backup merely because observability failed.

## Freshness and Notifications

Pi-hosted platform and validation notifications read backup state from
`cycling_platform_admin`; they never inspect the Mac filesystem directly.
Normal summary lines are:

```text
Off-host backup: 25 Jul 05:16 — 21h ago ✓
Retention: 30-day set reconciled ✓
```

Freshness is healthy through 30 hours, stale above 30 hours, and critical above
48 hours. Reconciliation problems are warnings regardless of age. These lines
are added to existing notifications—there is no separate success notification
or notification channel.

Because the platform runs at 02:00, validation at 03:30, and the Mac backup at
05:00, Pi notifications normally describe the previous day's 05:00 backup.
That is intentional: the check asks whether the off-host backup regime is
current, not whether a future backup has run.

For an existing deployment, run the normal bootstrap after pulling/rebuilding
to create the new Admin tables safely:

```sh
docker compose run --rm cycling-platform Rscript bootstrap_platform.R
```

The backup finalizer also uses idempotent table creation, but applying schema
changes during deployment avoids a temporary “observability unavailable” line.

## Mac Scheduling

Schedule backups on the Mac, not on `cycling-prod`. This is deliberately
different from ingestion and validation, whose production schedules belong on
`cycling-prod`.

Example:

```cron
0 5 * * * /path/to/cycling-platform/scripts/backup_mariadb.sh >> /path/to/cycling-platform/logs/database_backup.log 2>&1
```

Cron should use absolute paths. The script sets a constrained `PATH`, loads the
project `.Renviron`, resolves the dump client from configured locations, uses a
lock directory to avoid overlapping backups, and removes stale locks after the
configured maximum age. On macOS, the cron process also needs filesystem
permission to read the checkout and write the backup directory.

The backup time does not need to share the production application schedule, but
avoid known maintenance/restart windows and verify that MariaDB is reachable.

## Restore Sketch

Restore should be tested on a non-production database before being trusted.

Restore in dependency order: Admin, Raw, Silver, then Gold. Stage is not
restored.

Example restore from compressed dumps:

```sh
gunzip -c backups/2026-06-23_230000_cycling_platform_admin.sql.gz \
  | mariadb --host="$MARIADB_HOST" --port="$MARIADB_PORT" \
      --user="$MARIADB_USER" --password cycling_platform_admin

gunzip -c backups/2026-06-23_230000_cycling_platform_raw.sql.gz \
  | mariadb --host="$MARIADB_HOST" --port="$MARIADB_PORT" \
      --user="$MARIADB_USER" --password cycling_platform_raw

gunzip -c backups/2026-06-23_230000_cycling_platform_silver.sql.gz \
  | mariadb --host="$MARIADB_HOST" --port="$MARIADB_PORT" \
      --user="$MARIADB_USER" --password cycling_platform_silver

gunzip -c backups/2026-06-23_230000_cycling_platform_gold.sql.gz \
  | mariadb --host="$MARIADB_HOST" --port="$MARIADB_PORT" \
      --user="$MARIADB_USER" --password cycling_platform_gold
```

Use the same credential approach as backups: `.Renviron`, environment
variables, or a MariaDB option file such as `.my.cnf`.

`--password` prompts interactively and avoids placing the password in shell
history. For unattended restore testing, prefer a protected MariaDB option file.

Logical dump/restore preserves logical schema and row contents, not physical
InnoDB page layout. Restored tables can therefore have different allocated or
reported physical sizes even when row counts, keys, and logical contents match.
Validate logical contents rather than expecting byte-for-byte table sizes.

## Future Improvements

* add backup success/failure notifications
* add automated restore verification
* document and exercise a complete disaster-recovery test on a non-production
  MariaDB instance

## Migration Direction

Bootstrap scripts are for new environments. Existing populated environments
should use migrations for schema changes.

Near-term migration rules:

* prefer additive changes
* avoid dropping raw tables
* back up before `ALTER TABLE`
* document every manual schema change
* avoid destructive bootstrap unless the restore path has been tested
