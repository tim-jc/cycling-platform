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

The initial backup implementation is `scripts/backup_mariadb.sh`. It creates
timestamped compressed `mysqldump` backups for the admin and raw databases and
applies local retention cleanup.

Until restore testing is complete:

* avoid destructive database bootstrap on populated environments
* prefer migrations over rebuilds
* take a manual backup before schema changes
* test restore commands before relying on backups operationally

## Databases to Back Up

Minimum required databases:

* `cycling_platform_admin`
* `cycling_platform_raw`

Future curated layers should add:

* `cycling_platform_silver`
* `cycling_platform_gold`

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

* `BACKUP_DIR`, default `backups`
* `BACKUP_RETENTION_DAYS`, default `30`

Output shape:

```text
backups/
  2026-06-23_230000_cycling_platform_admin.sql.gz
  2026-06-23_230000_cycling_platform_raw.sql.gz
```

Backup files are ignored by git.

## Cron Automation

On the Raspberry Pi, schedule backups before ingestion.

Example:

```cron
30 2 * * * /path/to/cycling-platform/scripts/backup_mariadb.sh >> /path/to/cycling-platform/logs/backup.log 2>&1
```

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
```

Use the same credential approach as backups: `.Renviron`, environment
variables, or a MariaDB option file such as `.my.cnf`.

## Future Improvements

* copy backups off the Raspberry Pi
* add backup success/failure notifications
* add automated restore verification
* add silver/gold dumps once those layers exist

## Migration Direction

Bootstrap scripts are for new environments. Existing populated environments
should use migrations for schema changes.

Near-term migration rules:

* prefer additive changes
* avoid dropping raw tables
* back up before `ALTER TABLE`
* document every manual schema change
* avoid destructive bootstrap unless the restore path has been tested
