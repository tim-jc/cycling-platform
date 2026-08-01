# Data contract governance

Cycling-platform separates three authorities:

- repository DDL (or an explicitly selected database) is authoritative for physical columns, types, nullability and constraints;
- JSON under `metadata/silver/` and `metadata/gold/` is authoritative for machine-readable lineage, quality and governance state;
- Markdown under `docs/data-contracts/` is authoritative for purpose, meaning, grain, canonical claims, assumptions and rationale.

The Markdown template is [`docs/data-contracts/contract-template.md`](data-contracts/contract-template.md). JSON follows `metadata/schema/data-contract.schema.json`. Refresh physical sections from DDL with `Rscript scripts/generate_data_contract_metadata.R` and review the resulting diff.

## Definition of done

A managed Silver or Gold object is not implementation-complete until its physical schema, machine-readable metadata and semantic contract exist and pass validation. An object may not be marked `certified` while it has unresolved blocking human-review TODOs.

Certification does not mean permanent truth. It means the object meets the platform's current documented semantic, schema and quality contract.

## Lifecycle and TODOs

- `draft`: proposed or incomplete; blocking TODOs are expected.
- `implemented`: the object exists and is governed, but semantic review may remain open.
- `semantically_reviewed`: accountable review has completed and review status is `reviewed`.
- `certified`: current schema, quality and semantics are approved; no blocking TODO remains open.
- `deprecated`: retained temporarily but not recommended for new consumers.

TODO severity is `blocking`, `non_blocking` or `future`; status is `open`, `resolved` or `accepted`. Categories are `semantic_decision`, `implementation_alignment`, `source_research`, `quality_rule`, `future_enhancement`, and `documentation`. `accepted` means an uncertainty or limitation is deliberately retained and explained. Resolved and accepted entries remain in metadata with their rationale. IDs are repository-wide and never reused.

Certification fails for any unresolved blocking item, including semantic and implementation-alignment findings, and for an object whose alignment status is not `aligned`. An accepted or open future enhancement does not block certification unless it is separately classified with blocking severity.

## Validate locally

Restore the `renv` environment, then run:

```sh
Rscript scripts/validate_data_contracts.R
```

Validation collects failures, exits non-zero on failure and writes `reports/data-contract-validation.md`. The normal path uses repository DDL and never contacts production. Live-database comparison is deliberately deferred until it can remain an explicit optional mode.

## Add or change an object

1. Add the idempotent DDL.
2. Add exactly one JSON document and one Markdown contract named for the object in the matching layer.
3. Record uncertainty as structured TODOs; do not invent definitions.
4. Refresh physical metadata from DDL and review the diff.
5. Run contract validation and tests.

Lifecycle promotion is a human governance decision. Resolve a TODO by retaining it, changing its status and recording the resolution; use `accepted` with rationale for an intentional limitation.

## Exclusions and standards

Managed objects are discovered from every `CREATE TABLE` or `CREATE VIEW` in `sql/silver/` and `sql/gold/`. Nothing is ignored by naming convention. A genuinely technical object requires an exact entry and rationale in `metadata/exclusions.json`. Supporting Markdown files are listed explicitly there so orphan checks remain deterministic.

The shared-column registry is intentionally small. Deviations are warnings because adoption is not yet sufficiently uniform to make them errors.

## Current implementation boundary

The validator checks JSON structure and enumerations directly while the committed JSON Schema remains the public format definition. This avoids adding `jsonvalidate`, which is not currently installed. It checks coverage, DDL alignment, mandatory headings, lifecycle/TODO consistency, paths, managed-object references and shared-column types. Sophisticated SQL lineage parsing, implementation hashes, prose assessment and live database drift are deferred.
