# Add an API Endpoint

This is the reusable onboarding runbook for API-backed platform entities.
Strava gear is the worked example.

## Discovery

1. State the business need, platform owner, and expected consumers.
2. Inspect repository DDL, shared clients, auth helpers, retry/rate-limit
   behaviour, run logging, transforms, validation, orchestration, and tests.
3. Read the provider's official API reference. Record the endpoint sequence,
   required OAuth scope, response grain, pagination, rate limits, mutable or
   immutable behaviour, snapshot completeness, and historical availability.
4. Identify omissions explicitly. Do not infer undocumented source semantics.

Gear example:

* `GET /athlete` discovers current `bikes` and `shoes`; it is not paginated and
  requires `profile:read_all` for the detailed athlete representation.
* `GET /gear/{id}` returns one `DetailedGear`: ID, resource state, primary
  status, name, distance, brand, model, bike-only frame type, and description.
* There is no list-all-gear endpoint. Distinct activity gear IDs supplement the
  current collection, with one detailed lookup per deduplicated unresolved ID.
  Resolved historical IDs are retained without daily re-fetching; 403/404 IDs
  become eligible for another attempt after 30 days.
* Every request uses the shared Strava bearer-token, timeout, retry, proactive
  throttling, and rate-limit-header implementation. Gear is tiny, but its
  individual lookups still count against normal API limits.
* `/athlete` is current state. Individual lookup availability for retired gear
  is provider-controlled; 403 and 404 outcomes are retained as unresolved.

Official sources:

* <https://developers.strava.com/docs/reference/#api-Athletes-getLoggedInAthlete>
* <https://developers.strava.com/docs/reference/#api-Gears-getGearById>
* <https://developers.strava.com/docs/authentication/>
* <https://developers.strava.com/docs/rate-limits/>

## Data Design

Define before coding:

- Raw grain and business key;
- whether identical observations are retained or deduplicated;
- full-payload preservation and promoted fields;
- snapshot/history and disappearance semantics;
- Silver grain, key, lineage, null handling, and transform version;
- downstream join and unresolved-ID contract.

Gear Raw is one row per `gear_id × payload_hash`. An identical payload is
deduplicated and its `last_observed_at` and successful run membership are
advanced; a changed payload adds history. The complete JSON is authoritative.
The business key avoids timestamp-only duplication while preserving rename,
primary, distance, and metadata changes.

Gear Silver is one resolved row per `gear_id`. Controlled types are `bike`,
`shoes`, and `unknown`. The latest completely successful gear entity run is the
current-snapshot boundary. Missing gear becomes historical only after that
boundary; a failed run changes no Silver publication. Historical 403/404
attempts are stored separately so opaque activity references remain auditable.

The Strava gear ID is a source identifier. It may later map to a bike-library
ID, but components, maintenance, documents, photos, and wear do not belong in
this endpoint.

## Implementation

1. Add additive, idempotent DDL and indexes. Bootstrap must run create scripts,
   never derived transform SQL.
2. Add a focused client around the existing shared request/auth helper.
3. Parse responses into typed rows, preserving JSON and optional nulls.
4. Define explicit handling for empty, malformed, unauthorised, forbidden,
   not-found, rate-limited, retryable, and partial responses.
5. Put Raw writes and successful-snapshot completion in one transaction.
6. Log the entity through `etl_run_entity` and reusable endpoint metrics through
   `api_endpoint_run`.
7. Implement a deterministic Silver transform with explicit full/repair
   semantics and transform-run logging.
8. Add a manual audit query and a consumer-facing join contract.
9. Integrate only after dependency order and failure policy are understood.

Gear runs after activities so newly observed activity IDs are included, and
before streams/details/laps. Silver rebuilds activities, then gear, then
streams. Daily publication checks run only after both canonical entities exist.

## Quality

Use fixtures and database-independent functions wherever possible. Cover:

- normal, empty, mixed-type, nullable, and malformed responses;
- authentication/scope and retry/rate-limit failures;
- historical lookup, forbidden/not-found, and partial failure;
- initial, identical, changed, new, disappeared, and failed Raw loads;
- transaction rollback and payload-history preservation;
- latest-observation selection, lineage, type mapping, historical retention,
  rename propagation, and rebuild idempotency;
- known, null, unresolved, and retired activity joins without row multiplication;
- publication checks, reconciliation counts, and a manual review query.

For gear, `report_gear_resolution()` reports each distinct non-null activity
gear ID, resolution status, attached activity count, and earliest/latest dates.
The publication warning exposes unresolved IDs. Ride-summary display is:

- resolved: canonical gear name;
- null ID: `Not recorded`;
- unresolved non-null ID: `Unknown gear (<gear_id>)`.

## Deployment

### Authentication Impact

Compare the endpoint's official scope requirement with the canonical scope
definition and the scopes already granted. If existing scopes are sufficient,
do not re-authorise. If the set expands, update the canonical definition and
tests, then follow [Strava Authentication](../strava_authentication.md).
Refresh-token exchange cannot add a scope.

### Pre-deployment

1. Create a feature branch and record provider/architecture decisions.
2. Add DDL, client, parser, loader, fixtures, tests, transforms, publication
   checks, observability, automation, and docs.
3. Review the complete diff and remove temporary diagnostics.
4. Run targeted tests, the full suite, smoke check, `renv::status()`, and
   `git diff --check`.
5. Build and smoke-test the Docker image on the ARM64 Mac where practical.
6. Push reviewed code.
7. On `cycling-prod`, confirm the intended branch, clean worktree, and upstream
   state before a fast-forward-only pull:

   ```sh
   git -C /home/tim/cycling-platform status --short
   git -C /home/tim/cycling-platform fetch origin
   git -C /home/tim/cycling-platform status -sb
   git -C /home/tim/cycling-platform pull --ff-only
   ```

8. From `/home/tim/cycling-infrastructure/compose`, validate Compose, rebuild
   and identify the image, then run the non-ingesting smoke check. Pulling
   source alone is not deployment because the Dockerfile copies source into
   the image:

   ```sh
   docker compose config --quiet
   docker compose build cycling-platform
   docker compose images cycling-platform
   docker compose run --rm cycling-platform \
     Rscript --vanilla tests/smoke_check.R
   ```

9. If DDL changed, apply the additive idempotent bootstrap:

   ```sh
   docker compose run --rm cycling-platform Rscript bootstrap_platform.R
   ```

Host checkouts, Compose, mounts, permissions, scheduling, and deployment
wrappers belong to `cycling-infrastructure`; application commands and
acceptance semantics belong here.

### Controlled Production Validation

Do not treat one successful HTTP call as production acceptance.

1. Confirm required scopes and persistent credential visibility without
   printing values.
2. Run the new Raw path manually with notifications suppressed where supported.
3. Inspect Admin entity status, request metrics, row counts, failure messages,
   and representative Raw records.
4. Run the related Silver transform and record whether its CLI also rebuilds
   other entities.
5. Run publication checks and the endpoint audit/reconciliation query.
6. Verify representative resolved, null, changed, and unresolved cases.
7. Confirm logs and terminal capture contain no secrets or redirect URL.

For gear, the manual sequence is:

```sh
# PRODUCTION WRITE: incremental Raw ingestion for all configured sources.
docker compose run --rm cycling-platform \
  Rscript platform.R manual --no-notification

# PRODUCTION WRITE: repair mode runs every Silver transform, including gear.
docker compose run --rm cycling-platform Rscript run_silver.R repair

# Read-only data audit.
docker compose run --rm cycling-platform \
  Rscript -e 'source("bootstrap.R"); con <- get_connection(); print(report_gear_resolution(con)); DBI::dbDisconnect(con)'

# Records publication validation metadata and can send a notification.
docker compose run --rm cycling-platform \
  Rscript run_platform_validation.R --publication
```

There is no gear-only Raw or Silver CLI. These commands deliberately run the
normal Raw path and all Silver transforms. Gear's payload-hash key deduplicates
identical observations; Silver repair is deterministic, but both commands
write production data and operational metadata.

### Scheduled Acceptance and Completion

Allow the normal scheduled automation to execute. Record its run identifier
and relevant counts, then confirm the new Raw entity, Silver publication,
downstream phases, notifications, and overall run succeeded. Review request
volume and unresolved counts for plausibility.

For the completed gear rollout, scheduled run `#121` succeeded and Silver gear
published 15 records. This is an acceptance record, not a permanent expected
row-count assertion.

After acceptance, update contracts and inventory, record remaining debt, remove
temporary diagnostics, declare the rollout complete, and move follow-up work
into stabilisation.

Rollback is application-first: deploy the previously accepted revision and
rebuild its image; pause only the new infrastructure-owned scheduled path if
necessary. Additive Raw/Admin tables may remain. Do not drop Raw observations.
A failed gear run leaves the previous canonical publication available. Record
every production intervention; never make undocumented schema edits.

## Verification Commands

Run from the application repository root unless Compose is shown:

```sh
Rscript --vanilla -e 'testthat::test_file("tests/testthat/test-strava-oauth-bootstrap.R")'
Rscript --vanilla -e 'testthat::test_file("tests/testthat/test-strava-gear.R")'
Rscript --vanilla -e 'testthat::test_dir("tests/testthat")'
Rscript --vanilla tests/smoke_check.R
Rscript --vanilla -e 'renv::status()'
git diff --check
```

The first two are focused tests, the third is the complete suite, and the smoke
check is non-ingesting. `renv::status()` reports dependency-lock consistency.
There is no configured Markdown or link checker in this repository.

## Documentation

Update the endpoint inventory, Raw/Silver contract, automation order,
authentication scope, operational ownership, consumer impacts, known
limitations, and this runbook when a new reusable pattern emerges.

## Copyable Checklist

- [ ] Business owner and consumers recorded
- [ ] Official endpoint, scope, grain, pagination, limits, and history verified
- [ ] Repository conventions inspected
- [ ] Raw grain, key, payload, history, and disappearance rules documented
- [ ] Silver key, lineage, nulls, version, and downstream contract documented
- [ ] Shared auth/request/retry/logging helpers reused
- [ ] Additive idempotent DDL and indexes added
- [ ] Transaction, idempotency, repair, and failure policy tested
- [ ] Fixtures cover normal, empty, malformed, auth, limits, and historical cases
- [ ] Publication checks, reconciliation, and manual audit added
- [ ] Targeted and full tests passed
- [ ] Native and container smoke checks passed
- [ ] Required and granted scopes confirmed
- [ ] OAuth bootstrap completed only if required
- [ ] Rotated refresh token persisted and visible in a new container
- [ ] Production branch, worktree, and upstream state checked
- [ ] Image rebuilt and its identity inspected
- [ ] Additive DDL applied where required
- [ ] Manual Raw ingestion passed and Raw records were verified
- [ ] Manual Silver transform and publication checks passed
- [ ] Representative resolved, null, changed, and unresolved data verified
- [ ] Scheduled automation passed and run ID/counts were recorded
- [ ] Unrelated phases remained operational
- [ ] Logs and terminal capture contain no secrets
- [ ] Documentation updated and temporary diagnostics removed
- [ ] Technical debt recorded
- [ ] Rollback procedure and known limitations recorded
