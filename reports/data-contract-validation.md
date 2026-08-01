# Data contract validation

- Validation timestamp: 2026-08-01 08:52:16 BST
- Overall result: **PASSED**
- Managed Silver objects: 3
- Managed Gold objects: 2
- Missing contracts: 0
- Missing metadata: 0
- Schema mismatches: 0
- Broken references: 0
- Open blocking TODOs: 5
- Open non-blocking TODOs: 5
- Accepted limitations: 0

## Objects by lifecycle status

- implemented: 5

## Open blocking TODOs

- `SILVER-ACTIVITIES-001` (blocking): Confirm the canonical treatment of manually entered and subsequently edited activities.
- `SILVER-ACTIVITY_STREAMS-001` (blocking): Confirm positional alignment when Strava stream arrays differ in length.
- `SILVER-GEAR-001` (blocking): Confirm the identity boundary between Strava gear and a future bike-library entity.
- `GOLD-ACTIVITY_ACHIEVEMENTS-001` (blocking): Confirm the owner-approved meaning of each achievement type and scope.
- `GOLD-ACTIVITY_BEST_EFFORTS-001` (blocking): Confirm duration-effort semantics for irregular or gapped samples.

## Open non-blocking TODOs

- `SILVER-ACTIVITIES-002` (non_blocking): Confirm the authority and DST treatment of local timestamps and timezone_name.
- `SILVER-ACTIVITY_STREAMS-002` (non_blocking): Document missing-stream, missing-sample and source-null distinctions.
- `SILVER-GEAR-002` (non_blocking): Confirm consumer semantics for historical-only gear and source disappearance.
- `GOLD-ACTIVITY_ACHIEVEMENTS-002` (non_blocking): Document equal-value and historical-recalculation treatment.
- `GOLD-ACTIVITY_BEST_EFFORTS-002` (non_blocking): Confirm the policy for record eligibility and excluded power sources.

## Accepted limitations

- None

## Failures

- None

## Warnings

- None

