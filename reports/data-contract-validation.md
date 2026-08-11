# Data contract validation

- Validation timestamp: 2026-08-11 18:55:08 BST
- Overall result: **PASSED**
- Managed Silver objects: 4
- Managed Gold objects: 2
- Managed Reference objects: 2
- Missing contracts: 0
- Missing metadata: 0
- Schema mismatches: 0
- Broken references: 0
- Open blocking TODOs: 8
- Open non-blocking TODOs: 4
- Accepted limitations: 2

## Objects by lifecycle status

- implemented: 7
- semantically_reviewed: 1

## Open blocking TODOs

- `SILVER-ACTIVITIES-004` (blocking, implementation_alignment): Align has_streams with existence of at least one usable row in silver.activity_streams rather than Raw availability or ingestion state.
- `SILVER-ACTIVITIES-005` (blocking, source_research): Determine and document whether Strava type, sport_type, or a governed combination is authoritative for cycling classification.
- `SILVER-ACTIVITIES-006` (blocking, implementation_alignment): Implement or map the agreed Silver-owned is_cycling_activity classification after source-field research is resolved.
- `SILVER-ACTIVITIES-007` (blocking, implementation_alignment): Verify and align a certified has_valid_power field or mapping: genuine device measurement, watts stream present, and not estimated, while preserving published power values.
- `SILVER-ACTIVITY_STREAMS-001` (blocking): Confirm positional alignment when Strava stream arrays differ in length.
- `SILVER-GEAR-001` (blocking): Confirm the identity boundary between Strava gear and a future bike-library entity.
- `GOLD-ACTIVITY_ACHIEVEMENTS-001` (blocking): Confirm the owner-approved meaning of each achievement type and scope.
- `GOLD-ACTIVITY_BEST_EFFORTS-001` (blocking): Confirm duration-effort semantics for irregular or gapped samples.

## Open non-blocking TODOs

- `SILVER-ACTIVITIES-009` (non_blocking, implementation_alignment): Review historical array-shaped Raw extraction for external_id and device_name before changing power source classification evidence.
- `SILVER-ACTIVITY_STREAMS-002` (non_blocking): Document missing-stream, missing-sample and source-null distinctions.
- `SILVER-GEAR-002` (non_blocking): Confirm consumer semantics for historical-only gear and source disappearance.
- `GOLD-ACTIVITY_ACHIEVEMENTS-002` (non_blocking): Document equal-value and historical-recalculation treatment.

## Accepted limitations

- `SILVER-ACTIVITY_LAPS-002` (non_blocking, implementation_alignment): Raw ingestion cannot yet prove complete source snapshots, so source disappearance is not retired automatically.
- `SILVER-ACTIVITY_LAPS-003` (future, quality_rule): No blocking tolerance is defined for differences between summed laps and parent activity summaries.

## Failures

- None

## Warnings

- None
