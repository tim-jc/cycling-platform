# ADR-003: Versioned Schema Migrations

## Status

Accepted following the 2026 bare-metal disaster-recovery rehearsal.

## Context

Idempotent create scripts are appropriate for new objects but cannot reliably
reconcile populated historical schemas. Recovery demonstrated that a restored
database may need ordered transformations before current application code can
run safely.

## Decision

Schema changes requiring transformation are immutable SQL files under
`sql/migrations/`, named `NNN_description.sql`. Bootstrap discovers them in
fixed-width version order and records successful application in
`cycling_platform_admin.schema_migration`.

The ledger contains:

* `migration_version`;
* `migration_filename`;
* `migration_checksum`;
* `applied_at`.

Both filename and SHA-256 checksum must match an existing ledger row. Duplicate
versions and malformed filenames fail before migration SQL is executed. Applied
files must never be edited or renamed; a correction is a new migration.

MariaDB DDL auto-commits. A migration is inserted into the ledger only after
every statement in its file succeeds. Because an interrupted file can have
partially committed statements, every migration must be safely rerunnable.

## Verification

Migration success requires three pieces of evidence:

1. the expected immutable ledger row;
2. successful canonical/publication validation;
3. a successful full platform run.

For migration 001 the expected checksum is:

```text
d21cd9713ed4a9736626f41575d10fa762945a58400b40de80f36b4a5fe55224
```

## Consequences

Bootstrap remains repeatable and can reconcile restored databases. Migration
authors must account for locks, disk use, DDL auto-commit, and rerun safety.
Rollback normally uses a forward corrective migration or application rollback;
the ledger must never be falsified to conceal a failed migration.

