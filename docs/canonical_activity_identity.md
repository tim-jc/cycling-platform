# Canonical activity identity foundation

Status: Continuous allocation Awaiting Acceptance
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

## Publication allocation

Silver activity publication is the continuous allocation boundary. The staged
delete/reinsert and identity resolution execute in one database transaction.
An existing `(source_id, source_activity_id)` mapping always wins. A newly
published Strava activity without a mapping receives an identity and mapping
with `SOURCE_ALLOCATION` provenance. Publication cannot commit without mapping
coverage; allocation or later publication failure rolls back the activity and
new identity state together. A failed refresh therefore restores any previously
committed Silver row.

All scheduled, hygiene, historical-backfill, targeted-repair and manual Silver
paths call the same `rebuild_silver_activities()` publication boundary. The
platform-wide execution lock prevents supported workflows overlapping, while
the source-map primary key and transaction remain the correctness guarantee.
Neither identity table is dropped or truncated by ordinary Silver rebuilds.
Routine publication does not create or replace the immutability triggers.
Bootstrap and forward migrations own those schema objects. Before changing any
Silver activity, publication validates the exact four-trigger contract and
fails closed with governed-recovery guidance if it is missing or malformed.

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
authorized `STRAVA_BACKFILL` or `SOURCE_ALLOCATION` policy. Historical mappings are expected retained
evidence; the other non-zero categories are integrity violations. Diagnostics
never repair, delete, or reassign identity.

## Immutability enforcement

Database triggers reject updates and deletes against both identity tables.
Consequently ordinary application DML cannot change an `activity_key`, reassign
or rename an established source mapping, or delete established identity. This
does not affect transaction rollback: an identity insert whose mapping insert
fails is rolled back normally before it becomes established.

The account applying migration 020, fresh bootstrap, or a governed trigger
recovery must hold MariaDB's `TRIGGER` privilege on
`cycling_platform_silver`; the routine transform account does not need trigger
creation privilege solely for publication. Restore accounts must be able to
recreate triggers, and dump accounts must include their definitions. These
privileges must be confirmed before deployment because the platform repository
does not govern production grants. A privileged database administrator can
replace or drop the triggers deliberately during governed recovery. That is the
explicit administrative boundary, not an ordinary correction interface.
Backup and restore must retain triggers. Future correction, merge, split, or
reconciliation requires a separate audited design and migration; it must not
bypass these objects informally.

## Deliberate boundary

Continuous allocation applies only when a Strava activity crosses the canonical
Silver publication boundary. Raw-only or failed activities receive no identity.
Automatic cross-source matching, merge/split operations, source preference,
stream/lap selection and canonical equipment identity are separate decisions.

Ambiguous source matches are not inserted into the resolved mapping table.
Future candidate/review state must remain separate so uncertainty cannot be
mistaken for canonical identity.

The owner-run historical backfill must use the governed command above; it
refuses to overlap any process holding the platform execution lock. Preview and
diagnostics acquire no advisory locks and perform no persistent writes.

## Acceptance checks

Acceptance requires: one mapping per published Silver activity; unique source
identities; every mapping resolving to an identity and registered source;
stable keys across a second backfill; zero changes to existing `activity_id`
values; and unchanged existing consumer queries. Owner-reported production
acceptance of the foundation recorded 3,963 published activities and mappings,
100% coverage, zero pending allocations, and five healthy diagnostics. This
repository did not independently inspect production.

Following continuous-allocation deployment, acceptance additionally requires a
newly published activity to receive `SOURCE_ALLOCATION` identity in the same
transaction, followed by healthy publication validation and diagnostics.

MariaDB 11.8 exact-version integration remains a mandatory pre-deployment gate
when that disposable runtime is available; local development verification used
MariaDB 13.0.2 and must not be treated as equivalent production-version proof.
The local 4,003-activity publication measurement recorded 0.078 seconds for the
same rebuild with identity resolution replaced by a no-op and 1.113 seconds
with normal per-activity identity resolution (1.035 seconds measured overhead).
This is disposable synthetic evidence, not a production capacity claim. A
future set-based resolver may reduce round trips if production scale or timing
justifies it; correctness does not depend on that optimisation.
