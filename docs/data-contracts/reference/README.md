# Reference data contracts

Reference contains reusable, deliberately curated platform knowledge that does
not originate as an external observation. No Reference objects currently exist.

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
