# Gold contract: activity_achievements

Status: implemented; semantic review in progress. Mechanical schema: [`metadata/gold/activity_achievements.json`](../../../metadata/gold/activity_achievements.json).

## Purpose

Publish versioned, explainable achievements derived from canonical activities and best efforts.

## Business definition

An activity metric result that satisfies one configured achievement definition within a comparison scope and period. Owner approval of individual definitions remains open.

## Grain

One row per activity, achievement definition and comparison scope/period, represented by the declared business key.

## Canonical claim

Canonical platform achievement output for its calculation version and documented scope, subject to semantic review of definitions and tie handling.

## Primary key and uniqueness

`activity_achievement_key` is primary; a composite business-key uniqueness constraint is documented mechanically in JSON.

## Source and lineage

Silver activities and Gold best efforts. Implementation paths are recorded in JSON.

## Date and timezone semantics

Comparison periods and previous-best dates are calendar dates; processing timestamps record calculation/publication timing. Period timezone interpretation requires the upstream activity date contract.

## Transformations and business rules

Eligible values are compared within configured scopes, ranked, described, versioned and marked for notification eligibility.

Power achievements require eligible measured power according to the parent
activity's canonical classification. Any future lap-derived achievement must
inherit the same decision and must not use a lap source flag as an eligibility
shortcut. Cadence, heart-rate, distance, duration and elevation achievements
are unaffected by power provenance.

## Data quality expectations

Both declared keys are unique, required comparison fields are populated, and current activity references resolve upstream.

## Known limitations

Historical results may change after versioned recalculation or source corrections. Tie and boundary semantics need explicit review.

## Consumers

Achievement notification processing and downstream analytics.

## Human review TODOs

- `GOLD-ACTIVITY_ACHIEVEMENTS-001` (blocking): approve achievement meanings and scopes.
- `GOLD-ACTIVITY_ACHIEVEMENTS-002` (non-blocking): document tie and recalculation policy.

The JSON entries are authoritative for TODO status and resolution.

## Architectural notes

Notification eligibility is an output attribute; delivery state remains an operational concern outside this object.
Evaluation completeness is owned by Admin in
`activity_achievement_evaluation_state`. A missing sparse achievement fact is not
evidence that an activity has never been evaluated. Activities producing zero
facts have a `CURRENT` state row with `achievement_count = 0` after initialization.
Historical material input changes invalidate the inclusive closure from the
earliest affected `start_date_local` before reevaluation. Pure latest appends
evaluate only the appended activities. This deliberately broad dependency model
preserves all-time and calendar-year correctness without metric-specific rules.
Global version/classification changes and non-authoritative deletions still
require explicit repair or rebuild.

## Generated metadata

See [`metadata/gold/activity_achievements.json`](../../../metadata/gold/activity_achievements.json).
