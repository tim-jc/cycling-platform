# Development and Deployment

## Environments

### Mac Development

The Apple Silicon Mac is the primary development machine.

Native macOS R remains useful for:

* interactive exploration and debugging;
* SQL development against remote MariaDB on `cycling-prod`;
* focused ingestion or transform runs;
* fast smoke and regression tests.

R package versions are controlled by `renv.lock`. Restore the project library
with:

```sh
Rscript -e 'renv::restore()'
```

Native execution is convenient but does not exercise Debian packages, Linux
paths, container filesystem permissions, the image entry point, or missing
shell utilities. It is therefore not sufficient as the only pre-deployment
test.

### Local Docker Portability Check

The `Dockerfile` is the authoritative application runtime definition. It pins
the R base image, restores `renv.lock`, and installs required system and shell
dependencies. Build and test this image locally before deployment where
practical.

Both the development Mac and production Raspberry Pi are ARM64, so a local
Docker build provides strong CPU-architecture parity as well as Linux runtime
coverage.

The exact Compose file and environment wiring are host/infrastructure concerns
and are not currently stored in this repository. At minimum, validate that the
image builds and can run the smoke check with the intended environment:

```sh
docker build -t cycling-platform:local .
docker run --rm cycling-platform:local \
  Rscript --vanilla tests/smoke_check.R
```

Database/API integration checks require the same environment variables and
network reachability used by production. Do not copy secrets into the image.

### Production

Production runs on:

* host: Raspberry Pi 5;
* hostname: `cycling-prod`;
* OS: Raspberry Pi OS Lite / Debian;
* architecture: ARM64;
* database: MariaDB 11.8 under Docker Compose.

MariaDB is a continuously running Compose service. `cycling-platform` is an
ephemeral job container, not a daemon or long-running service.

Notification execution context uses
`CYCLING_PLATFORM_EXECUTION_HOST` when Compose propagates it. Without that
deployment value, Docker's OS nodename and `HOSTNAME` normally resolve to the
ephemeral container ID, as they do not expose the physical host automatically.
Native runs fall back to their OS nodename. The application deliberately
contains no production host-name constant. See [Platform
Automation](platform_automation.md#notification-execution-context).

Normal production execution:

```sh
docker compose run --rm cycling-platform
```

The image default command is:

```sh
Rscript run_daily_platform.R scheduled
```

Deep validation runs independently:

```sh
docker compose run --rm cycling-platform \
  Rscript run_platform_validation.R
```

This separation prevents a long deep audit from hiding or blocking an otherwise
successful daily publication.

## Recommended Workflow

1. Develop and explore on the Mac using native R where convenient.
2. Keep application code, SQL, non-secret configuration, `Dockerfile`, and
   `renv.lock` under Git.
3. Run native smoke/regression tests.
4. Build and test the Docker image on the Mac where practical.
5. Push reviewed changes from the Mac.
6. Pull changes on `cycling-prod`.
7. Rebuild the `cycling-platform` image.
8. Run the relevant smoke, validation, or manual operational command.
9. Allow scheduled production jobs to run only on `cycling-prod`.

Application code is baked into the Docker image by `COPY . .`. A `git pull` on
`cycling-prod` changes the checkout but not an already-built image. Always
rebuild after changes to application code, SQL, configuration copied into the
image, `renv.lock`, or `Dockerfile`:

```sh
git status --short
git fetch origin
git status -sb
git pull --ff-only
docker compose build cycling-platform
docker compose images cycling-platform
```

Before pulling, `git status -sb` should show the intended production branch,
no unexplained local changes, and whether it is behind its upstream. Stop if
the production checkout is dirty or has diverged; do not hide that state with a
reset. The infrastructure deployment wrapper currently performs the
fast-forward-only pull, build, and image listing, but the operator must still
confirm branch and worktree state before invoking it.

Dependency-only changes can invalidate different Docker layers:

* `renv.lock` changes require the R dependency restore layer to rebuild;
* `Dockerfile` changes may alter Debian/system dependencies;
* ordinary application or SQL changes require the final application layer to
  rebuild.

After building, use a non-ingesting image check before any controlled
production write:

```sh
docker compose run --rm cycling-platform \
  Rscript --vanilla tests/smoke_check.R
```

If the new endpoint changed DDL, apply the additive idempotent bootstrap before
the endpoint's manual ingestion. Then follow the controlled and scheduled
acceptance process in [Add an API
Endpoint](runbooks/add-api-endpoint.md#controlled-production-validation).

Bootstrap also applies ordered migrations from `sql/migrations/`. Never edit a
migration after it has been applied; add a new numbered migration. The
migration ledger verifies checksums so accidental history changes are visible.

Verify the ledger after bootstrap:

```sql
SELECT
    migration_version,
    migration_filename,
    migration_checksum,
    applied_at
FROM cycling_platform_admin.schema_migration
ORDER BY migration_version;
```

Migration 001 must report `001_enforce_canonical_collation.sql` with checksum
`d21cd9713ed4a9736626f41575d10fa762945a58400b40de80f36b4a5fe55224`.
Deployment evidence is complete only when the ledger is correct, publication
validation passes, and a full platform run succeeds.

Rollback normally means checking out the previously accepted application
revision through the normal Git workflow, rebuilding that image, and verifying
its identity and smoke check. Do not drop additive Raw/Admin tables or delete
source observations merely to roll application code back. If new orchestration
is unsafe, prevent the scheduled call through the infrastructure-owned
scheduler while preserving the prior published Silver data.

## Production Scheduling

Production ingestion and deep-validation scheduling is moving from Mac cron to
cron on `cycling-prod`. Cron should invoke Compose jobs from the production
Compose project directory.

Conceptual entries:

```cron
0 2 * * * cd /path/to/compose-project && docker compose run --rm cycling-platform
30 3 * * * cd /path/to/compose-project && docker compose run --rm cycling-platform Rscript run_platform_validation.R
```

The actual checkout/Compose path and cron user are deployment-specific and are
not defined in this repository. Confirm that the cron user can access Docker,
the Compose environment/secrets, and the MariaDB network.

Do not schedule the same production capability on both the Mac and
`cycling-prod`; overlapping runs are avoidable operational risk even where
application locks exist.

Backups are the exception to production-job colocation. The backup job remains
on the Mac so logical dumps are stored off-host from the Pi.

## Configuration and Secrets

### Native Mac

Create an ignored project `.Renviron` from `.Renviron.example`. Required groups:

* MariaDB host, port, user, and password;
* Strava client ID, client secret, and refresh token;
* Google Health client ID, client secret, and refresh token;
* `NTFY_TOPIC`.

The Mac connects remotely to MariaDB on `cycling-prod`. No local MariaDB system
database is required. Application connections select one of the five platform
databases, normally `cycling_platform_admin` for control/cross-schema work.

### Docker / Compose

Production Compose must make the same variable names available to each
ephemeral job container. The repository `.Renviron` is excluded by
`.dockerignore`; it is not baked into the image.

Strava can rotate its refresh token, and the application writes the new value
to the path resolved by `CYCLING_PLATFORM_RENVIRON_PATH`,
`R_ENVIRON_USER`, or the project `.Renviron`. Production must therefore provide
a writable persistent credential file/mount or another host-side persistence
mechanism. A file created only in the ephemeral container is lost on `--rm`.
The exact Compose mount/environment arrangement is not present in this
repository and must be verified on `cycling-prod`.

Do not:

* commit `.Renviron`;
* put secret values in `Dockerfile`, Compose files committed to a public
  repository, or `config/platform.yml`;
* use `MARIADB_DATABASE=cycling` as an architectural shortcut.

Startup distinguishes configuration absence from credential rejection:

* missing MariaDB or OAuth variables produce an `incomplete configuration`
  error naming only the missing variable names;
* invalid/revoked credentials produce a connection or token-refresh failure
  after configuration has passed presence checks;
* diagnostics may report credential presence, file path, modification time, or
  token length, but never secret values or token prefixes.

During recovery, first verify that the expected persistent runtime `.Renviron`
is mounted and selected by `CYCLING_PLATFORM_RENVIRON_PATH` / `R_ENVIRON_USER`.
Do not respond to a missing-variable error by rotating credentials; restore the
runtime configuration path first.

The application uses five databases and the production user needs only the
required privileges on those databases:

* `cycling_platform_admin`
* `cycling_platform_raw`
* `cycling_platform_stage`
* `cycling_platform_silver`
* `cycling_platform_gold`

It must not depend on access to the MariaDB `mysql` system database.

## Initialising a Brand-New Database

A scheduled incremental run is not a bootstrap. On a new MariaDB instance, run
the initial-load workflow deliberately:

```sh
Rscript bootstrap_platform.R
Rscript run_raw_ingestion.R backfill
Rscript run_silver.R repair
Rscript scripts/gold/run_activity_best_efforts.R backfill
Rscript scripts/gold/run_activity_achievements.R backfill
Rscript run_daily_platform.R scheduled
```

In production, execute each command as an ephemeral Compose job:

```sh
docker compose run --rm cycling-platform Rscript bootstrap_platform.R
```

Repeat with each subsequent command. Bootstrap creates the five databases,
tables, and seed metadata; it does not perform historical ingestion or derived
layer population. Backfill modes are deliberately excluded from unattended
daily automation.

The bootstrap connection enters through `cycling_platform_admin`. Therefore a
brand-new server requires that the deployment/provisioning process create that
database and grant the application user access before application bootstrap can
connect. The repository does not currently define that infrastructure-level
provisioning step.

## Portability and Compatibility

Migration from native Mac-era execution and MariaDB 10.5 to containerised
MariaDB 11.8 production exposed several durable rules:

* Avoid reserved words as unquoted SQL identifiers. `ROW_NUMBER` became
  reserved after MariaDB 10.7; aliases now use descriptive names such as
  `entity_recency_rank`.
* Do not connect through the MariaDB `mysql` system database. Use the database
  the operation owns, normally `cycling_platform_admin` for control or
  fully-qualified cross-database queries.
* Do not inherit server character-set or collation defaults. Platform databases
  and tables explicitly use `utf8mb4` / `utf8mb4_general_ci`; MariaDB version
  upgrades can change the server default.
* Every shell command used at runtime must exist in the Docker image. `rsync`
  was a missing dependency found during container validation and is now
  installed by `Dockerfile`.
* Do not make macOS paths, Homebrew locations, or framework-specific `Rscript`
  paths production requirements.
* Native Mac success does not prove Linux/container portability.
* ARM64 parity reduces architecture surprises but does not replace image-level
  testing.

### Collation migration during deployment

The first bootstrap containing
`001_enforce_canonical_collation.sql` converts existing databases and tables to
the canonical collation. Run it in a maintenance window before scheduled work:

```sh
docker compose run --rm cycling-platform Rscript bootstrap_platform.R
docker compose run --rm cycling-platform \
  Rscript run_platform_validation.R --publication
```

`ALTER TABLE ... CONVERT TO CHARACTER SET` can rebuild tables, acquire metadata
locks, and require temporary disk space, especially for activity streams. Keep
a verified backup, check free space, and stop competing platform jobs. MariaDB
DDL auto-commits, so a failure can leave an incomplete but safely rerunnable
conversion. The migration is recorded only after every statement succeeds.

## Operational Wrappers

The repository currently has two execution layers: direct R entry points and
native-host shell wrappers.

`scripts/run_daily_platform.sh`

: Resolves native `Rscript`, copies the repository and `.Renviron` into a
  temporary runtime directory with `rsync`, manages locks/log retention, runs
  `run_daily_platform.R`, and copies rotated credentials back. It is retained
  for native Mac/manual compatibility and is not the primary production Compose
  entry point.

`scripts/run_platform_validation.sh`

: Provides the same temporary-copy, lock, logging, and credential handling for
  deep validation. It is retained for native Mac/manual compatibility and is
  not the primary production Compose entry point.

`scripts/backup_mariadb.sh`

: Loads backup configuration/secrets, checks TCP reachability, creates verified
  compressed logical dumps, retries transient failures, applies retention,
  writes the local latest-success artefact, and reconciles physical files with
  append-only Admin metadata. It is active Mac host orchestration for off-host
  production backups.

The Docker image runs R entry points directly. Its default daily command does
not call `scripts/run_daily_platform.sh`. Production deep validation likewise
overrides the image command with `Rscript run_platform_validation.R`.

## Repository Ownership Boundary

`cycling-platform` owns:

* OAuth and API behaviour;
* application entry points and image contents;
* Raw ingestion, Silver/Gold transforms, and publication validation;
* application tests, metrics, notifications, and data contracts.

`cycling-infrastructure` owns:

* host directory creation and machine recovery;
* the production Compose definition, environment injection, and bind mounts;
* service-account ownership and filesystem permissions;
* deployment, cron, host logs, and scheduling locks;
* database host lifecycle, restore orchestration, and off-host backup wiring.

Application docs may name the current production paths and service name, but
those are environment-specific deployment facts rather than library defaults.
If they change, update the infrastructure definition first and then reconcile
the application runbook.

## Production Container Troubleshooting

If a fix appears in the checkout but not in a one-off job, assume the image may
be stale until proven otherwise:

```sh
docker compose images cycling-platform
docker image inspect cycling-platform:dev \
  --format 'id={{.Id}} created={{.Created}}'
docker compose run --rm --entrypoint sh cycling-platform -c \
  'test -f scripts/strava/bootstrap_oauth.R && echo helper-present'
docker compose build cycling-platform
```

Inspect only non-secret source paths and metadata. `--entrypoint` is useful for
isolating image or wrapper behaviour, but is not a normal execution path.

Interactive one-off helpers need stdin attached. The supported Strava
bootstrap therefore uses `docker compose run --rm -i`; a shell pipe reaching a
container does not by itself prove that non-interactive R helper code reads
process stdin. See [Strava Authentication](strava_authentication.md) for the
minimal safe probe and recovery steps.

## Future Execution-Path Simplification

Do not refactor these paths casually; scheduling, credential rotation, locks,
logging, and notifications must remain reliable. A separate execution-path
audit should consider:

* whether temporary repository copies are still needed in container execution;
* whether lock ownership belongs in shell wrappers, Compose/cron, or R;
* how many supported entry points are genuinely required;
* whether native-host `Rscript` discovery can become development-only;
* where credential rotation should persist when containers are ephemeral;
* whether Compose configuration and production runbooks should move into a
  version-controlled infrastructure repository.
