# Silver data contracts

Current managed contracts:

- [activities](activities.md)
- [activity laps](activity_laps.md)
- [activity streams](activity_streams.md)
- [gear](gear.md)
- [overall semantic gap report](gap-report.md)
- [migration note](migration-note.md)

Markdown is authoritative for semantics; corresponding JSON under `metadata/silver/` is authoritative for machine-readable lineage, quality, lifecycle and TODO state. Repository DDL is authoritative for physical schema. Proposed health objects are not included because they are not current persistent Silver objects.

Run the complete governance check from the repository root:

```sh
Rscript scripts/contracts/validate.R
```

See [data contract governance](../../data_contract_governance.md) for lifecycle definitions, exclusions and the object-onboarding workflow.
