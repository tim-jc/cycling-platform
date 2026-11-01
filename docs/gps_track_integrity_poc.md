# GPS track-integrity POC

The activity track-integrity profiler measures one activity's ordered Silver
stream samples without deciding whether its route is suitable for Explorer
tiles, interpolation, or country allocation.

## Pure R interface

`profile_activity_track_integrity(samples, diagnostic_limit = 5)` accepts one
activity with these columns:

- `activity_id`
- `sample_index`
- `latitude`
- `longitude`
- `time_seconds`
- `distance_metres`

Input order is preserved. The profiler reports non-increasing indexes rather
than silently sorting them. Coordinates are valid when both values are finite,
latitude is within `[-90, 90]`, and longitude is within `[-180, 180]`.
`[0, 0]` is valid but reported separately as suspicious.

Consecutive valid coordinates use the Haversine formula and the IUGG mean Earth
radius of 6,371,008.8 metres. Implied speed is calculated only when elapsed time
is positive. Device-distance differences remain distinct from geographic
displacement; agreement is not assumed. The profiler reports geographic minus
device distance as a signed difference, its absolute value, and a guarded
relative discrepancy:

```text
absolute difference / max(abs(geographic distance), abs(device increment))
```

When both measurements are effectively zero (at most `1e-9` metres), relative
discrepancy is zero. Missing/invalid geographic displacement or missing device
distance produces `NA`, never infinity. A large discrepancy is diagnostic
evidence only: roads can make travelled distance legitimately exceed the direct
great-circle displacement between sparse observations.

The result contains a named activity summary and bounded diagnostics for the
largest gaps, speeds and displacements plus malformed time, distance, coordinate
and sample-index observations. It does not retain every derived segment.

## Explicit read-only database audit

From the repository root, deliberately supply one or more numeric activity IDs:

```sh
Rscript scripts/audits/audit_activity_track_integrity.R 123456789 987654321
```

The command accepts at most 50 IDs, uses parameterised values, retrieves only
the six required columns, and orders through the Silver
`(activity_id, sample_index)` primary key. It writes no files or database rows.
Reported memory values are R object sizes, not peak process RSS.

The audit is intentionally not scheduled and must not be invoked without an
authorised database connection.

## Limitations

The POC measures rather than classifies continuity. It does not determine:

- whether a segment is safe to interpolate;
- whether an activity qualifies for VeloViewer Explorer tiles;
- whether virtual GPS should count;
- whether tile visitation is point- or segment-based;
- whether GPS distance should replace device distance;
- whether a route crosses a country boundary.

Gap, jump and eligibility thresholds require review of observed distributions
and must become explicitly versioned policy before downstream use.

The fixed-population follow-on calibration procedure is documented in
`docs/gps_track_integrity_calibration.md`. It reuses this profiler without
changing the POC's default memory-light result.

## Raw-to-Silver positional alignment

Strava returns `latlng`, `time`, and `distance` as separate stream arrays. Raw
stores one JSON payload and `original_size` per activity and stream type. Silver
creates a row grid from `seq_len(max(original_size))` and reads every stream at
the corresponding R list position. A shorter stream produces `NA` after its last
element.

Silver `sample_index` is one-based while JSON arrays are zero-based. Therefore:

```text
Silver sample 7639 -> JSON array position 7638
Silver sample 7640 -> JSON array position 7639
```

The code guarantees this mechanical positional mapping. It does not independently
prove that Strava's separate arrays are semantically aligned; that remains a
source contract assumption supported by current completeness observations.

Long temporal gaps do not on their own establish corruption: a gap with no
movement can be a legitimate pause. Conversely, individually valid coordinates
can be erroneous locations and can create plausible-looking speeds. Geographic
versus device-distance disagreement is therefore reported alongside time and
displacement, without automatic classification.

Useful production cases for future regression investigation, without copying
their full tracks into fixtures, are:

- `20445541114`: confirmed stationary café stop;
- `3057187825`: visibly corrupted GPS with disproportionate geographic movement;
- `2705450947`: missing route geometry whose upstream origin remains to be traced.
