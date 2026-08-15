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

Backup timing, retention and client configuration exists in
`config/platform.yml`. The durable database set comes from
`config/platform_databases.tsv`, the shared platform database inventory.

The physical dump implementation is `scripts/backup_mariadb.sh`. Normal
operations enter through `scripts/run_backup_workflow.sh backup`, which creates
timestamped compressed `mysqldump` backups for the configured platform
databases, applies local retention cleanup, and reconciles the retained files
against durable operational metadata. The wrapper adds proactive metadata-only
failure/freshness alerting without changing the dump format.

The intended job runs on the Mac, connects across the network to MariaDB on
`cycling-prod`, and stores dumps under
`~/Library/Application Support/cycling-platform/backup/data`. Backups remain
off-host from the production Pi so loss or corruption of its SD card does not
also remove the recovery copy.

Until restore testing is complete:

* avoid destructive database bootstrap on populated environments
* prefer migrations over rebuilds
* take a manual backup before schema changes
* test restore commands before relying on backups operationally

## Databases to Back Up

Configured databases:

* `cycling_platform_admin`
* `cycling_platform_raw`
* `cycling_platform_reference`
* `cycling_platform_silver`
* `cycling_platform_gold`

`cycling_platform_stage` is deliberately excluded because stage objects are
temporary ETL workspace and safe to delete.

Reference is durable and included even while it contains no objects. New backup
runs require all five durable dumps. Retention reconciliation continues to
recognise historical four-file sets—Admin, Raw, Silver and Gold—that predate
Reference. Restore orchestration remains owned by `cycling-infrastructure`.

## Manual or Controlled Backup

After installation, use the deployed operational wrapper. This exercises the
same TCC-safe code and configuration as launchd:

```sh
"$HOME/Library/Application Support/cycling-platform/backup/runtime/scripts/run_backup_workflow.sh" backup
```

The script reads MariaDB connection settings from the protected backup-specific
`backup.env`. Repository `.Renviron` is consulted only by the installer during
the first manual deployment and is never accessed by scheduled jobs.

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
* `BACKUP_STATUS_FILE`, defaults to `latest_success.json` under the
  configured backup directory
* `MYSQLDUMP`, optional absolute path to `mysqldump` or `mariadb-dump`

The script resolves the dump client from `backups.dump_command_candidates`,
then falls back to `mysqldump` or `mariadb-dump` on `PATH`. This is needed
because scheduled launch agents often run with a much smaller `PATH` than an
interactive shell.

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
~/Library/Application Support/cycling-platform/backup/data/
  latest_success.json
  2026-06-23_230000_cycling_platform_admin.sql.gz
  2026-06-23_230000_cycling_platform_raw.sql.gz
  2026-06-23_230000_cycling_platform_reference.sql.gz
  2026-06-23_230000_cycling_platform_silver.sql.gz
  2026-06-23_230000_cycling_platform_gold.sql.gz
```

Backup files are ignored by git.

`latest_success.json` is updated atomically only after all five expected dumps
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

Retention cleanup groups recognised filenames by exact run prefix. It removes
expired complete or incomplete prefixes as sets rather than aging individual
files independently. It:

* never removes the newest valid complete four- or five-file recovery set,
  even when it is older than `backups.retention_days`
* recognises retained historical four-file and current five-file generations
  (after the first retained five-file set, later four-file prefixes are
  incomplete current runs, not historical sets)
* never promotes an incomplete prefix into `latest_success.json`
* removes stale `*.sql.gz.tmp` files older than
  `backups.temporary_file_retention_days`

After cleanup, the Mac compares physical `*.sql.gz` files with successful
backup metadata and appends a result to
`cycling_platform_admin.backup_reconciliation_run`. Reconciliation detects:

* missing files for successful runs still inside the retention window
* successful retained runs that do not match their recognised format: the
  historical four-database set or the current five-database set including
  Reference
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

## Recovery authority and restored Admin lag

The verified Mac inventory and the canonical data directory's
`latest_success.json` are authoritative
for identifying the newest verified physical recovery point available.
Admin backup tables are platform observability/history, not the physical
inventory. Admin is dumped before the current run records its own success, so a
restored Admin dump necessarily cannot describe the complete set containing it.

A recovered Pi can therefore report stale or missing Admin backup metadata
while newer complete recovery sets exist on the Mac. Verify
`latest_success.json` and the exact-prefix Mac files before concluding that the
physical recovery asset is stale. A later successful backup reconciles Admin
observability. The Pi remains deliberately uncoupled from the Mac filesystem.

### macOS scheduled runtime

The authoritative Git checkout remains under the macOS-protected `Documents`
folder, but scheduled jobs never access that checkout. A manually invoked
installer deploys a minimal, generated runtime to TCC-safe user locations:

```text
runtime  ~/Library/Application Support/cycling-platform/backup/runtime
config   ~/Library/Application Support/cycling-platform/backup/config/backup.env
data     ~/Library/Application Support/cycling-platform/backup/data
logs     ~/Library/Logs/cycling-platform
plists   ~/Library/LaunchAgents
```

The repository is source authority; the Application Support runtime must never
be edited manually. Its JSON manifest records the source Git commit,
installation timestamp, schema version, file inventory, and SHA-256 hashes.
`verify` detects any installed-file drift.

The runtime code directory and the mutable backup root are deliberately
separate. Each installed wrapper derives the backup root as the parent of its
own `runtime` directory, then resolves `config/backup.env` and `data` as sibling
paths. Consequently, direct invocation works without launchd environment
variables:

```sh
"$HOME/Library/Application Support/cycling-platform/backup/runtime/scripts/run_backup_workflow.sh" health
```

The plists still set `BACKUP_CONFIG_FILE` and `BACKUP_DIR` explicitly as useful
operational overrides, but they are not required for canonical path discovery.
Backup mode fails immediately with the expected config path when
`config/backup.env` is absent; it never falls back to `runtime/backup.env` or a
`runtime/backups` directory.

The installed runtime contains only the backup scripts, a backup-specific R
bootstrap, the database inventory, connection and SQL helpers, the backup
observability helper, and its three Admin DDL files. A generated, backup-only
`config/platform.yml` fragment is retained because freshness, retention, lock,
retry, dump-command, and durable-database settings are runtime dependencies; it
contains no credentials. The runtime contains no exploration, tests, OAuth
code, ingestion/transforms, `.Renviron`, or project `renv` library. The minimal
R bootstrap explicitly sources only those backup dependencies.

Scheduled R uses the already-installed Mac R packages `DBI`, `RMariaDB`,
`jsonlite`, and `purrr`. The installer verifies code and paths but does not
install packages or copy the broad project library. Package availability is
checked by the non-destructive health command before enabling reliance on the
new schedule.

Installation is the only point at which Terminal reads the protected checkout.
Normal backup, retention, finalisation, health, and alert executions operate
entirely from Application Support, Library Logs, and the off-host data folder.
No Full Disk Access is required.

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

The Mac wrapper separately sends proactive ntfy attention notifications for
physical dump/verification failure, observability/finalizer failure after dumps
verify, and missing, malformed, incomplete, stale or critical
`latest_success.json` state. The hourly check also confirms that every file
named by the artefact still exists and is non-empty (five for current artefacts,
or four for a retained historical artefact); it does not repeatedly decompress
the large dumps.
Messages contain only host, fixed failure class, freshness/age and prefix—not
credentials, dumps or arbitrary errors. Fingerprints in
`backups/.alert-state` suppress unchanged alerts. Notification failure never
replaces the backup exit status, and no success notification is sent.

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

## Mac Scheduling with launchd

Schedule backups on the Mac, not on `cycling-prod`. This is deliberately
different from ingestion and validation, whose production schedules belong on
`cycling-prod`.

Install or update the user LaunchAgents:

```sh
scripts/install_backup_launchd.sh render /tmp/cycling-platform-backup-render
scripts/install_backup_launchd.sh install
scripts/install_backup_launchd.sh verify
scripts/install_backup_launchd.sh status
scripts/install_backup_launchd.sh health
```

The 05:00 calendar job is coalesced by launchd after ordinary sleep/wake. An
hourly, run-at-load health agent checks the authoritative Mac artefact, so a
missed run can alert even though no backup process failed. Existing locks
prevent overlap.

`render` creates an inspectable runtime and plists without loading anything.
`install` renders into a sibling staging directory, validates it, migrates
existing archives without deleting the source, atomically switches the active
runtime, reloads both agents, and verifies the result. The preceding runtime is
retained as `runtime.previous` for rollback. Repeated installs are idempotent.

The installer creates `backup.env` with mode `0600` in a `0700` directory. On
first install it extracts only `MARIADB_HOST`, `MARIADB_PORT`, `MARIADB_USER`,
`MARIADB_PASSWORD`, `NTFY_TOPIC`, and `NTFY_BASE_URL` when present. Strava,
Google Health, OAuth, and other platform secrets are deliberately excluded.
An existing `backup.env` is preserved rather than overwritten. Plists contain
paths but no secret values.

The database list remains generated from Git-controlled
`config/platform_databases.tsv`; the installed inventory is regenerated on
each install, so a future durable database addition cannot be silently omitted
after deployment. Logs are `~/Library/Logs/cycling-platform/backup-launchd.log`
and `backup-health-launchd.log`.

Disable or re-enable with:

```sh
scripts/install_backup_launchd.sh uninstall
scripts/install_backup_launchd.sh install
```

`uninstall` removes only active LaunchAgents and installed runtime code. It
preserves backup archives, `backup.env`, logs, and `runtime.previous`.

### First rollout and controlled verification

From the authoritative checkout in Terminal:

```sh
scripts/install_backup_launchd.sh render /tmp/cycling-platform-backup-render
scripts/install_backup_launchd.sh install
scripts/install_backup_launchd.sh verify
scripts/install_backup_launchd.sh health
```

Inspect the rendered inventory and confirm neither runtime nor plist contains a
`/Documents/` path. `health` is non-destructive: it verifies installed hashes,
configuration permissions, writable data/log locations, the latest-success
artefact, and existing freshness alert behaviour without creating dumps.

Then run one controlled backup from the installed runtime:

```sh
"$HOME/Library/Application Support/cycling-platform/backup/runtime/scripts/run_backup_workflow.sh" backup
scripts/install_backup_launchd.sh verify
scripts/install_backup_launchd.sh status
```

Confirm five same-prefix `.sql.gz` files, successful gzip verification in the
log, an advanced `latest_success.json`, healthy retention reconciliation in
Admin, expected ntfy behaviour, and LaunchAgent last exit status `0`. Retain
the old repository backup directory until this completes and the owner approves
its later disposition; the installer never deletes it.

### Recovery and rollback

On a replacement Mac, restore the Git checkout and the encrypted recovery copy
of `backup.env`, install R plus the four minimal R packages and MariaDB client,
restore backup archives to the canonical data directory, then run `install`,
`verify`, and `health`. The repository does not currently define the encrypted
recovery source for `backup.env`; selecting and documenting that source is an
owner follow-up. Machine-local config alone is not sufficient disaster
recovery.

To roll back before the controlled backup succeeds:

1. run `scripts/install_backup_launchd.sh uninstall`;
2. retain both old and new archive directories and their success artefacts;
3. inspect `runtime.previous` if restoring the preceding installed runtime;
4. reinstall the former Git revision, or temporarily restore the reviewed cron
   command from Terminal if launchd must be abandoned;
5. run a health check before trusting the restored schedule.

Do not delete either archive or copy one `latest_success.json` over another
during rollback. Cron fallback may invoke the installed Application Support
runtime; pointing cron back into Documents reintroduces the same TCC risk.

The backup time does not need to share the production application schedule, but
avoid known maintenance/restart windows and verify that MariaDB is reachable.

## Restore Sketch

Restore should be tested on a non-production database before being trusted.

Restore in dependency order: Admin, Raw, Reference, Silver, then Gold. Stage is
not restored. Historical backup sets created before Reference was introduced
legitimately omit the Reference dump.

Example restore from compressed dumps:

```sh
gunzip -c backups/2026-06-23_230000_cycling_platform_admin.sql.gz \
  | mariadb --host="$MARIADB_HOST" --port="$MARIADB_PORT" \
      --user="$MARIADB_USER" --password cycling_platform_admin

gunzip -c backups/2026-06-23_230000_cycling_platform_raw.sql.gz \
  | mariadb --host="$MARIADB_HOST" --port="$MARIADB_PORT" \
      --user="$MARIADB_USER" --password cycling_platform_raw

gunzip -c backups/2026-06-23_230000_cycling_platform_reference.sql.gz \
  | mariadb --host="$MARIADB_HOST" --port="$MARIADB_PORT" \
      --user="$MARIADB_USER" --password cycling_platform_reference

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

### Schema reconciliation after restore

A restore can combine historical tables with newer platform DDL. Before any
scheduled ingestion or transformation, rebuild the current application image
and run:

```sh
docker compose run --rm cycling-platform Rscript bootstrap_platform.R
docker compose run --rm cycling-platform \
  Rscript run_platform_validation.R --publication
```

Historical versioned migrations reconcile the five pre-Reference databases and
their existing tables. Infrastructure creates Reference with `utf8mb4` /
`utf8mb4_general_ci`; publication validation checks all six database defaults
and every managed table/column. This prevents joins from depending on either
the restored server's or the target server's defaults.

The conversion may rebuild large InnoDB tables and needs a maintenance window,
free disk space, and a verified pre-migration backup. MariaDB DDL auto-commits;
if conversion stops part-way through, resolve the cause and rerun bootstrap.
The migration ledger is updated only after the whole migration file succeeds.

Verify recovery migration evidence directly:

```sql
SELECT
    migration_version,
    migration_filename,
    migration_checksum,
    applied_at
FROM cycling_platform_admin.schema_migration
ORDER BY migration_version;
```

For migration 001, verify filename
`001_enforce_canonical_collation.sql` and SHA-256 checksum
`d21cd9713ed4a9736626f41575d10fa762945a58400b40de80f36b4a5fe55224`.
A ledger row alone is not sufficient recovery evidence: the canonical schema
publication check and the complete daily platform must also succeed.

Backup-health warnings must not be suppressed merely because execution is on a
recovery-test host. A restored backup contains historical backup metadata, so a
stale or critical result may be genuine and useful. Rehearsal operators should
record that expected condition, then establish a current verified off-host
backup through the normal backup owner before treating the recovered service as
production-ready.

## Future Improvements

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
