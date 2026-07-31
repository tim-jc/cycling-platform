# ADR-002: Canonical MariaDB Schema Standard

## Status

Accepted following the 2026 bare-metal disaster-recovery rehearsal.

## Context

A historical production backup contained tables using
`utf8mb4_general_ci`. When restored onto MariaDB 11, newly introduced gear
tables inherited the newer server default `utf8mb4_uca1400_ai_ci`. Joins on
`gear_id` then failed with an illegal mix of collations.

The platform must remain deterministic when a historical backup is restored on
a newer MariaDB release. Server defaults are installation details and cannot be
part of the application schema contract.

## Decision

Every platform database and persistent table explicitly uses:

* engine: `InnoDB`;
* character set: `utf8mb4`;
* collation: `utf8mb4_general_ci`.

The collation preserves established production comparison behaviour and is
available on both MariaDB 10.5 and MariaDB 11.x. Database, table, and dynamic
text-column DDL must not inherit server defaults.

MariaDB implements `JSON` using validated `LONGTEXT` with `utf8mb4_bin`.
Declared JSON payload columns are therefore explicit exceptions. They are not
platform relationship keys, and the canonical-schema validation permits only
the named JSON columns.

Loaders append only to existing, bootstrapped tables. They must not use
`dbWriteTable()` as an implicit persistent-table creation path.

## Enforcement

* explicit database and table DDL;
* migration `001_enforce_canonical_collation.sql`;
* publication check `platform_schema_collation_canonical`;
* static smoke and unit tests covering all creation paths;
* an append helper that refuses writes when the target table is absent.

## Consequences

MariaDB upgrades do not silently change platform comparison rules. Collation
conversions can rebuild large InnoDB tables and therefore require a maintenance
window, free disk space, and a verified backup.

