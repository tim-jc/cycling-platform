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

1. Create a feature branch.
2. Inspect the API contract and repository schemas.
3. Add DDL, client, parser, loader, fixtures, tests, transform, checks, and docs.
4. Run local tests and lint/smoke checks without requiring live MariaDB.
5. Build and test the Docker image on the ARM64 Mac.
6. Push reviewed code; pull it on `cycling-prod`.
7. Rebuild the application image—pulling source alone is not deployment.
8. Apply DDL with an ephemeral job:

   ```sh
   docker compose run --rm cycling-platform Rscript bootstrap_platform.R
   ```

9. Run the endpoint manually with notifications suppressed where supported,
   inspect Raw rows and Admin logs, then run Silver and the resolution audit.
10. Run publication/deep validation, enable scheduled integration, and monitor
    the first scheduled run and API request counts.

For gear, the manual sequence is:

```sh
docker compose run --rm cycling-platform \
  Rscript platform.R manual --no-notification
docker compose run --rm cycling-platform Rscript run_silver.R repair
docker compose run --rm cycling-platform \
  Rscript -e 'source("bootstrap.R"); con <- get_connection(); print(report_gear_resolution(con)); DBI::dbDisconnect(con)'
docker compose run --rm cycling-platform Rscript run_platform_validation.R
```

Rollback is application-first: restore the previous image and disable the new
orchestration call if necessary. Additive Raw/Admin tables may remain. Do not
drop Raw observations. Because a failed gear run blocks new Silver publication,
the previous canonical table remains available. Record any production
intervention in the deployment issue; never make undocumented schema edits.

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
- [ ] Native and container checks passed
- [ ] Image rebuilt and DDL applied on production
- [ ] Manual first run inspected before scheduling
- [ ] First scheduled run monitored
- [ ] Rollback procedure and known limitations recorded
