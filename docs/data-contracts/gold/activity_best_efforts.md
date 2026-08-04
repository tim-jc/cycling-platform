# Gold contract: activity_best_efforts

Status: implemented; semantic review in progress. Mechanical schema: [`metadata/gold/activity_best_efforts.json`](../../../metadata/gold/activity_best_efforts.json).

## Purpose

Publish reusable duration-based peak activity efforts for analytical and achievement products.

## Business definition

The highest computed value for a configured metric and duration within one eligible activity. Sampling-gap semantics require review.

## Grain

One row per `activity_id`, `metric_name` and `duration_seconds`.

## Canonical claim

Canonical platform best-effort result for the recorded calculation version, not a timeless claim independent of algorithms or source revisions.

## Primary key and uniqueness

The grain columns form the primary key; generated JSON records exact constraints.

## Source and lineage

Silver activities and activity streams; code paths and confidence are recorded in JSON.

## Date and timezone semantics

Sample start/end fields are elapsed offsets and positions. `computed_at` is a processing timestamp.

## Transformations and business rules

Configured rolling-duration calculations select a peak and capture sample/location boundaries, eligibility, source classification and calculation version.

Watt efforts inherit canonical power provenance and record eligibility from the
parent Silver activity. Eligibility must not be inferred independently from a
stream or lap source flag. Virtual or estimated watt efforts may remain stored
for audit and alternative analysis, but are excluded from measured-power records
when governed parent eligibility is false. Non-power efforts are unaffected.

## Data quality expectations

The business key is unique; peak, boundary and version lineage fields are complete; activity identity resolves upstream.

## Known limitations

Results depend on sample density, gap treatment, eligibility rules and calculation version.

## Consumers

Gold achievements and downstream performance analytics.

## Human review TODOs

- `GOLD-ACTIVITY_BEST_EFFORTS-001` (blocking): confirm irregular/gapped sample semantics.
- `GOLD-ACTIVITY_BEST_EFFORTS-002` (resolved): watt record eligibility inherits
  the parent activity's governed canonical power classification.

The JSON entries are authoritative for TODO status and resolution.

## Architectural notes

Versioning is part of the product contract because recalculation can legitimately change results.

## Generated metadata

See [`metadata/gold/activity_best_efforts.json`](../../../metadata/gold/activity_best_efforts.json).
