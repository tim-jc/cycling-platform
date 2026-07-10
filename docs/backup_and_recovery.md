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
databases and applies local retention cleanup.

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

Output shape:

```text
backups/
  2026-06-23_230000_cycling_platform_admin.sql.gz
  2026-06-23_230000_cycling_platform_raw.sql.gz
  2026-06-23_230000_cycling_platform_silver.sql.gz
  2026-06-23_230000_cycling_platform_gold.sql.gz
```

Backup files are ignored by git.

## Verification and Cleanup

For each configured database, the script writes to a `.tmp` file first. The file
is promoted to the final `.sql.gz` name only after:

* `mysqldump | gzip` exits successfully
* the temporary file is non-empty
* `gzip -t` passes

This verifies that the compressed dump was written cleanly. It is not a full
restore test; restore verification remains a separate operational task.

Retention cleanup removes:

* completed `*.sql.gz` backups older than `backups.retention_days`
* stale `*.sql.gz.tmp` files older than
  `backups.temporary_file_retention_days`

## Cron Automation

On the Raspberry Pi, schedule backups before ingestion.

Example:

```cron
30 2 * * * /path/to/cycling-platform/scripts/backup_mariadb.sh >> /path/to/cycling-platform/logs/backup.log 2>&1
```

Cron should run the script through an absolute path. The script sets a minimal
cron-safe `PATH`, loads project `.Renviron`, uses a lock directory to avoid
overlapping backups, and removes stale locks after the configured maximum age.

Suggested ordering:

```text
02:30 backup
03:00 ingestion
```

## Restore Sketch

Restore should be tested on a non-production database before being trusted.

Example restore from compressed dumps:

```sh
gunzip -c backups/2026-06-23_230000_cycling_platform_admin.sql.gz \
  | mysql cycling_platform_admin

gunzip -c backups/2026-06-23_230000_cycling_platform_raw.sql.gz \
  | mysql cycling_platform_raw

gunzip -c backups/2026-06-23_230000_cycling_platform_silver.sql.gz \
  | mysql cycling_platform_silver

gunzip -c backups/2026-06-23_230000_cycling_platform_gold.sql.gz \
  | mysql cycling_platform_gold
```

Use the same credential approach as backups: `.Renviron`, environment
variables, or a MariaDB option file such as `.my.cnf`.

## Future Improvements

* copy backups off the Raspberry Pi
* add backup success/failure notifications
* add automated restore verification

## Migration Direction

Bootstrap scripts are for new environments. Existing populated environments
should use migrations for schema changes.

Near-term migration rules:

* prefer additive changes
* avoid dropping raw tables
* back up before `ALTER TABLE`
* document every manual schema change
* avoid destructive bootstrap unless the restore path has been tested
