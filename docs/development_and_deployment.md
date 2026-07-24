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
git pull
docker compose build cycling-platform
```

Dependency-only changes can invalidate different Docker layers:

* `renv.lock` changes require the R dependency restore layer to rebuild;
* `Dockerfile` changes may alter Debian/system dependencies;
* ordinary application or SQL changes require the final application layer to
  rebuild.

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
Rscript platform.R backfill
Rscript run_silver.R repair
Rscript run_gold_activity_best_efforts.R backfill
Rscript run_gold_activity_achievements.R backfill
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
* Every shell command used at runtime must exist in the Docker image. `rsync`
  was a missing dependency found during container validation and is now
  installed by `Dockerfile`.
* Do not make macOS paths, Homebrew locations, or framework-specific `Rscript`
  paths production requirements.
* Native Mac success does not prove Linux/container portability.
* ARM64 parity reduces architecture surprises but does not replace image-level
  testing.

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
  compressed logical dumps, retries transient failures, and applies retention.
  It is active Mac host orchestration for off-host production backups.

The Docker image runs R entry points directly. Its default daily command does
not call `scripts/run_daily_platform.sh`. Production deep validation likewise
overrides the image command with `Rscript run_platform_validation.R`.

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
