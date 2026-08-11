# Reference data contracts

Reference contains reusable, deliberately curated platform knowledge that does
not originate as an external observation.

Current managed contracts:

- [`planned_events.md`](planned_events.md): curated planned-event domain and
  event object.
- [`planned_event_stages.md`](planned_event_stages.md): optional separately
  useful planned riding units.

Supporting design record:

- [`planned_events-physical-design.md`](planned_events-physical-design.md):
  reviewed v1 physical decisions that informed implementation.

Repository-owned Reference YAML is published at platform deployment through
`Rscript scripts/reference/publish_reference_data.R`. It is deliberately not
part of scheduled ingestion. The aggregate entry point is platform-owned and
explicitly sequences each Reference dataset publisher.

Every future object requires DDL under `sql/reference/`, JSON metadata under
`metadata/reference/`, and a semantic contract in this directory. Its contract
must explain:

- who or what curates the object;
- the authoritative provenance of its values;
- whether records are effective-dated;
- how changes, corrections and approvals are versioned or audited;
- whether knowledge was imported, manually maintained or platform-generated;
- how context-independent consumers should interpret it.

Reference must not become Raw replacement, miscellaneous configuration,
application-local hidden data, unrelated constants, or consumer-specific Gold
output. Ad hoc production SQL is not an acceptable normal curation mechanism;
future objects need a reviewed, reproducible loader or seed process.

No universal audit or effective-date columns are imposed. Each object contract
must justify the mechanics appropriate to its semantics.
