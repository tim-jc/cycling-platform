# Manual job status and heartbeat

Long-running manual Silver transforms publish small, durable JSON status files.
This is operational evidence for an ephemeral job container, not a scheduler or
replacement for Admin ETL metadata.

## Supported job

The first instrumented commands are unchanged:

```sh
docker compose run --rm cycling-platform Rscript run_silver.R full
docker compose run --rm cycling-platform Rscript run_silver.R repair
```

They publish `silver-full` and `silver-repair` status respectively. Both reuse
the existing platform-wide MariaDB advisory lock, so a manual Silver job is
refused if a daily, hygiene, backfill, repair, or other exclusive platform run
is active. Lock refusal is recorded as a failed run-specific status with a
concise error, but deliberately does not replace the latest file owned by the
active run.

## Files and production mapping

The canonical files are below `logging.directory/status`, normally:

```text
logs/status/silver-full-latest.json
logs/status/silver-full-<run-id>.json
```

`latest` is replaced throughout the run for easy inspection. The run-specific
file is also updated while active and becomes application-immutable after final
`SUCCESS` or `FAILED` status, providing history. Files are mode `0640`; the
status directory is created as `0750` where it does not already exist.

In the production image this is `/opt/cycling-platform/logs/status`. Compose
bind-mounts `/srv/cycling/logs/platform` to `/opt/cycling-platform/logs`, so the
host files survive container removal at:

```text
/srv/cycling/logs/platform/status/
```

Atomic replacement uses a sibling temporary file in the status directory,
flushes and closes it, applies permissions, then renames it. The rename remains
within one mounted filesystem. No status file is itself a Docker bind-mount
point.

Run-specific files older than `logging.retention_days` (30 days by default)
are removed when a new status tracker starts. The latest file and active run
are retained. Manual cleanup, if required, should remove only old run-specific
files after confirming they are completed; never remove `*-latest.json` during
an active job.

## Lifecycle and schema

Lifecycle values are `STARTING`, `RUNNING`, `SUCCESS`, and `FAILED`. Status is
written at bootstrap, lock acquisition/phase transitions, stream planning,
batch boundaries, periodic heartbeats, and finalisation. Gracefully caught
errors always produce `FAILED`. An uncatchable process or host termination may
leave `RUNNING`; staleness is then an observation, not an inferred mutation.

Example JSON:

```json
{
  "schema_version": 1,
  "job_name": "silver-full",
  "run_mode": "full",
  "run_id": "20260801T150000Z-417-8a92f41067cd",
  "host": "cycling-prod",
  "pid": 417,
  "pid_scope": "container",
  "started_at": "2026-08-01T15:00:00Z",
  "last_heartbeat_at": "2026-08-01T19:43:58Z",
  "finished_at": null,
  "elapsed_seconds": 17038,
  "status": "RUNNING",
  "current_phase": "rebuild",
  "current_entity": "activity_streams",
  "progress_completed": 2814,
  "progress_total": 3886,
  "progress_unit": "activities",
  "rows_processed": 38422000,
  "rows_written": 38421774,
  "rows_deleted": 0,
  "current_batch": 29,
  "total_batches": 40,
  "completed_batches": 28,
  "last_business_key": "12345678901",
  "error": null,
  "summary": null
}
```

`rows_processed` is expected stream rows completed; `rows_written` and
`rows_deleted` are committed database changes. The last business key is the
largest activity ID in the last committed batch. Status deliberately excludes
credentials, connection strings, Raw payloads, and environment values. Error
text is length-limited and redacts common password, token, secret,
authorisation, and credential-in-URL forms.

## Heartbeats and staleness

The default heartbeat interval is 60 seconds through
`logging.status_heartbeat_seconds`. Writes occur at natural phase/chunk and
batch boundaries, and a heartbeat is emitted when the interval has elapsed.
The status reader defaults to stale after 120 seconds:

```sh
docker compose run --rm cycling-platform \
  Rscript scripts/show_job_status.R silver-full
```

An optional second argument overrides the stale threshold in seconds:

```sh
docker compose run --rm cycling-platform \
  Rscript scripts/show_job_status.R silver-full 180
```

`Stale: yes` means a `RUNNING` heartbeat is too old. For native execution on
the same host, a missing recorded PID also marks the observation stale. A PID
inside an ephemeral Docker namespace is not checked from a separate container,
because it is not the physical host PID. Completed statuses are never stale.
The reader never converts stale status to `FAILED`.

Example output:

```text
Job: silver-full
Run ID: 20260801T150000Z-417-8a92f41067cd
Status: RUNNING
Host: cycling-prod
Phase: rebuild
Entity: activity_streams
Progress: 2,814 / 3,886 activities
Batch: 29 / 40
Completed batches: 28
Rows processed: 38,422,000
Rows written: 38,421,774
Rows deleted: 0
Last business key: 12345678901
Started: 2026-08-01 16:00:00 BST
Last heartbeat: 2026-08-01 20:43:58 BST
Elapsed: 4h 43m 58s
Stale: no
```

Missing or malformed files produce a clear message and non-zero exit status.

## Notifications and other observability

Manual Silver status files are always enabled. Manual completion/failure ntfy
notifications are not enabled by default, avoiding duplication and notification
fatigue. Daily automation retains its existing single final notification. An
explicit manual `--notify` option can be considered later if operator demand
justifies it.

Admin `transform_run` and `transform_run_batch` remain authoritative for ETL
run and batch metrics. The status JSON is a lightweight, filesystem-resident
operator view that remains readable when the initiating terminal disappears.
Terminal progress remains useful while attached but is not the durable source.

## Production verification

From the infrastructure Compose directory on `cycling-prod`:

```sh
docker compose run --rm cycling-platform Rscript run_silver.R full
```

From a second session:

```sh
docker compose run --rm cycling-platform \
  Rscript scripts/show_job_status.R silver-full

sudo ls -l /srv/cycling/logs/platform/status/
sudo python3 -m json.tool \
  /srv/cycling/logs/platform/status/silver-full-latest.json
```

After completion, confirm `SUCCESS`, a non-null `finished_at`, final summary
metrics, and the matching run-specific history file. To rehearse failure safely,
start a second full run while the first holds the platform lock; the second run
must exit non-zero and publish a separate `FAILED` lock-refusal record without
affecting the active run.
