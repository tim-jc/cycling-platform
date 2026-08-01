# Silver activities semantic review 001

Date: 2026-08-01  
Object: `cycling_platform_silver.activities`  
Outcome: semantics agreed; implementation alignment required before certification

## Decisions made

- Silver admits every activity returned by the connected Strava account; analytical significance is downstream.
- The platform is intentionally single-user and Strava `activity_id` is the canonical primary key.
- Silver publishes the latest state known within configured routine, hygiene, and historical refresh windows; revisions replace prior representations.
- Manual activities are valid and may lack streams/sensors. Absence must not be used to infer manual status.
- `has_streams` means at least one usable stream in `silver.activity_streams`; expected completeness is validation state.
- UTC instant, local wall-clock timestamp, local activity date, and Strava-associated timezone have distinct agreed meanings.
- Published measurements are preserved separately from derived measurements.
- Valid analytical power requires device measurement, a watts stream, and non-estimated provenance; published power remains preserved regardless of eligibility.
- Silver owns reusable cycling classification; Gold owns training/significance classifications.
- `gear_id` remains Strava source identity; richer equipment identity belongs in a separate canonical object.
- NULL, false, and zero retain distinct meanings.
- Validation observes, reports, and recommends but does not silently modify canonical data.

## Contract changes

The purpose, business definition, grain, canonical scope, freshness, date/time, streams, measurements, power, classifications, gear, missing values, validation philosophy, limitations, consumers, and out-of-scope sections were updated. The object lifecycle is now `semantically_reviewed`, with semantic status `agreed`.

## Architectural principles extracted

The review produced seven shared principles now recorded in `docs/platform_principles.md`: Published vs Derived; Contract vs Implementation; Guaranteed vs Expected vs Observed; Preserve Uncertainty; Silver Admission Test; Semantic Normalisation vs Gold Denormalisation; and Interpretation → Observation → Correction.

## Implementation investigations

- Verify and align `is_manual`; it appears unpopulated and is not certified.
- Align `has_streams` to usable rows in Silver streams rather than Raw observation/completeness.
- Implement or map Silver-owned `is_cycling_activity` after source research.
- Implement or map `has_valid_power` to the agreed eligibility meaning while retaining published power.

These are contract-to-code alignment investigations. No transformation or schema change was made by this review.

## Source research

Determine whether Strava `type`, `sport_type`, or a governed combination is the correct source evidence for `is_cycling_activity`.

## Future enhancements

Confirmed source deletions should eventually remove the activity from Silver. A single missing source observation is not confirmation and does not currently delete data.
