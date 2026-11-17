# Canonical activity identity continuous allocation 001

Date: 2026-11-17  
Status: Awaiting Acceptance

## Implemented milestone

- Silver activity refresh and required identity resolution share one bounded
  transaction;
- established mappings are reused and new Strava publications use governed
  `SOURCE_ALLOCATION` provenance;
- allocation or publication failure cannot commit an unmapped activity or
  orphan identity;
- publication validation now governs mapping completeness;
- foundation diagnostics recognize historical and continuous allocation; and
- identity operation commands explicitly close their database connection on
  success, failure and lock contention.

## Publication coverage

Scheduled daily, hygiene, annual backfill, targeted repair and manual Silver
full/repair execution all converge on `rebuild_silver_activities()`. Supported
entry points already acquire the platform execution lock. Identity correctness
additionally rests on the database transaction, immutable mapping primary key,
foreign keys and immutability triggers rather than advisory locking alone.

## Owner-reported foundation baseline

The owner reports 3,963 published Silver activities and mappings, 100% identity
coverage, zero pending allocations, healthy diagnostics, and an idempotent
second backfill after migration 020. This record does not claim independent
production verification.

## Remaining acceptance gates

- exact-version disposable MariaDB 11.8 integration;
- confirmation of migration and restore-account `TRIGGER` privileges;
- backup/restore evidence that all immutability triggers survive; and
- owner-controlled deployment followed by new-activity allocation, publication
  validation, diagnostics and a subsequent scheduled-run acceptance check.

No consumer key migration, cross-source matching, identity correction, G3A
geographic calculation or operational notification delivery is included.

## Acceptance remediation evidence

The real integration harness now invokes `rebuild_silver_activities()` with the
version-controlled `sql/silver/020_transform_activities.sql`. It verifies first
publication, refresh with stable identity, rollback after Silver insertion
failure, rollback after mapping failure, rollback after successful allocation
but before commit, and successful recovery on a later invocation.

Routine transformation no longer recreates identity triggers. Bootstrap and
forward migration remain their owners; publication checks the exact trigger
contract before activity mutation and fails closed if governed recovery is
required.

On disposable MariaDB 13.0.2, a synthetic 4,003-activity rebuild measured
0.078 seconds with identity resolution replaced by a no-op and 1.113 seconds
with normal resolution (1.035 seconds overhead). This is local comparative
evidence only. The exact-version MariaDB 11.8 gate remains open.

A real schema/data dump was produced with triggers enabled. Restore testing on
the local disposable server was blocked by that server's `--skip-grant-tables`
anonymous account: the dump correctly contained triggers but necessarily
encoded an invalid empty definer. This is a harness limitation, not evidence of
production restore compatibility. A governed named-account dump/restore must
still prove identity rows, mappings and all four trigger definitions survive
and remain enforcing before acceptance.
