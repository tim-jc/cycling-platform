# Canonical activity identity foundation

Status: Awaiting Acceptance  
Date: 2026-11-17

## Contract

Cycling Platform owns a source-independent `activity_key`. It is an opaque,
immutable, auto-allocated `BIGINT`; its numeric value conveys no provider,
time, or ordering semantics. `cycling_platform_silver.activity_identity` has
one row per canonical real-world activity. A resolved source record is linked
by `cycling_platform_silver.activity_source_map`, whose stable source identity
is `(source_id, source_activity_id)`.

`source_activity_id` uses exact binary comparison so future provider IDs that
differ only by case cannot be merged accidentally. Applications supply and
display the provider's original UTF-8 identifier; the database key preserves
its bytes rather than applying a platform text collation.

`activity_id` remains the Strava source identifier and the primary/foreign key
used by all existing Silver, Gold, Admin, Analytics, Coastal and GPS evidence
contracts. This foundation does not alter those columns or joins. New permanent
geographic products may use `activity_key` only after their source activity is
resolved through the mapping table.

## Initial backfill

The initial backfill is deliberately restricted to published Silver Strava
activities. Raw-only or failed/partial activities have not yet passed the
canonical Silver publication boundary and receive no identity in this slice.
Every existing Silver activity maps its `(source_id, CAST(activity_id AS CHAR))`
to one newly allocated key unless that mapping already exists.

The backfill:

- resolves `source_id` through existing Silver lineage and verifies that its
  governed source name is `strava`;
- preserves all existing mappings and keys;
- serializes executions with a MariaDB advisory lock;
- allocates each identity and mapping in one transaction;
- commits bounded units so an interruption can be resumed safely;
- verifies that no published Silver activity remains unmapped; and
- never modifies Raw, existing Silver activities, Gold, Admin history, or
  consumer keys.

State-changing backfill first acquires the existing platform-wide execution
lock and then its identity-specific lock. This ordering prevents overlap with
daily, repair, hygiene, or backfill publication and serializes identity
backfills without introducing a reverse lock order. Locks are released in
reverse order and every release result is verified. If execution and cleanup
both fail, the execution error remains primary and cleanup failure is reported
as an additional warning. Closing the database connection remains the final
server-side lock cleanup mechanism.

Preview (read only):

```sh
Rscript scripts/operations/backfill_canonical_activity_identity.R preview
```

Apply after migration 020, through an owner-controlled environment:

```sh
Rscript scripts/operations/backfill_canonical_activity_identity.R apply
```

Read-only integrity diagnostics:

```sh
Rscript scripts/operations/diagnose_canonical_activity_identity.R
```

The report distinguishes unmapped published activities, identities without a
source mapping, historical mappings whose activity is not currently published,
multiple Strava records mapped to one key, and mapping provenance outside the
foundation allocation policy. Historical mappings are expected retained
evidence; the other non-zero categories are integrity violations. Diagnostics
never repair, delete, or reassign identity.

## Immutability enforcement

Database triggers reject updates and deletes against both identity tables.
Consequently ordinary application DML cannot change an `activity_key`, reassign
or rename an established source mapping, or delete established identity. This
does not affect transaction rollback: an identity insert whose mapping insert
fails is rolled back normally before it becomes established.

The account applying migration 020 must hold MariaDB's `TRIGGER` privilege on
`cycling_platform_silver`; this must be confirmed before deployment because the
platform repository does not govern production grants. A privileged database
administrator can replace or drop the triggers deliberately during governed
recovery. That is the explicit administrative boundary, not an ordinary
correction interface. Backup and restore must retain triggers. Future correction,
merge, split, or reconciliation requires a separate audited design and migration;
it must not bypass these objects informally.

## Deliberate boundary

This slice does not allocate identities during normal Strava ingestion. After
the accepted backfill, a later Silver activity can therefore remain unmapped
until this command is rerun. Deployment must not advertise continuous identity
coverage until the next bounded allocator integration is implemented. Automatic
cross-source matching, merge/split operations, source preference, stream/lap
selection and canonical equipment identity are separate decisions.

Ambiguous source matches are not inserted into the resolved mapping table.
Future candidate/review state must remain separate so uncertainty cannot be
mistaken for canonical identity.

The owner-run initial backfill must use the governed command above; it now
refuses to overlap any process holding the platform execution lock. Preview and
diagnostics acquire no advisory locks and perform no persistent writes.

## Acceptance checks

Acceptance requires: one mapping per published Silver activity; unique source
identities; every mapping resolving to an identity and registered source;
stable keys across a second backfill; zero changes to existing `activity_id`
values; and unchanged existing consumer queries. Production counts and scale
remain unverified until an authorised deployment and read-only acceptance run.

MariaDB 11.8 exact-version integration remains a mandatory pre-deployment gate
when that disposable runtime is available; local development verification used
MariaDB 13.0.2 and must not be treated as equivalent production-version proof.
