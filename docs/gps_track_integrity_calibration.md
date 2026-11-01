# GPS track-integrity population calibration

This bounded, read-only calibration extends the single-activity GPS integrity
POC to a fixed population. It measures observed distributions; it does not set
corruption, interpolation, Explorer-tile, or country-allocation policy.

## Governed sample definition

Version `gps-track-calibration-v1` has a fixed source cutoff of
`2026-10-29 23:59:59 UTC` and a target of 45 unique activities. The population
must have a Raw `latlng` stream with positive `original_size`, a non-manual
Silver activity, and evidence consistent with a genuine outdoor recording.
Explicit virtual/simulated sport types, a true source `trainer` flag, and known
Zwift/TrainerRoad context are excluded. Missing manual, sport, date, or other
required provenance is classified as unknown and cannot enter the confirmed
population silently.

This is deliberately conservative, but not a universal source-provenance
classifier. Source systems do not provide a single authoritative “real-world
GPS” flag. Any newly identified synthetic-route provenance must be added to a
new, reviewed sample-definition version rather than mutating an existing local
manifest.

The sample consists of:

- three known reference activities;
- two activities from each of 15 rank-quantile chronology/distance cells,
  selecting contrasting sampling-density bands where possible;
- six remaining sampling extremes;
- four activities favouring underrepresented outdoor sport types;
- two activities with the largest elapsed-minus-moving time;
- a deterministic SHA-256-ranked fill when a cohort is short.

Rank quantiles use a stable activity-ID tie break, so tied dates or distances
remain deterministic. If fewer than 45 eligible activities exist, every
eligible activity is selected and the shortfall is explicit in the manifest.

## Generate the authoritative local manifest

The metadata query joins Silver activity metadata to the three indexed Raw
stream rows (`latlng`, `time`, and `distance`). It uses `original_size` and
does not read Raw JSON stream arrays or scan the Silver sample table.

Choose a local path outside the repository:

```sh
Rscript scripts/audits/generate_gps_track_calibration_manifest.R \
  "$HOME/Documents/Cycling/audits/gps_track_calibration_v1_manifest.csv"
```

The generator refuses to overwrite an existing file. That CSV is the
authoritative population for repeat runs; do not silently regenerate it.
It records the version, cutoff, selection timestamp, eligible population size,
cohort/reason, quantile bands, deterministic rank, activity metadata, Raw
stream sizes, and sampling-density measures.

## Run sequential profiling

```sh
Rscript scripts/audits/run_gps_track_calibration.R \
  "$HOME/Documents/Cycling/audits/gps_track_calibration_v1_manifest.csv" \
  "$HOME/Documents/Cycling/audits/gps-track-calibration-v1-results"
```

The runner validates the manifest before connecting. It prints `EXPLAIN` plans
for an ordinary manifest activity and the largest Raw GPS stream, then queries
exactly one activity at a time through the Silver
`(activity_id, sample_index)` primary key. Derived segment data is released
before the next activity. No database writes occur.

Four local CSVs are written:

1. `gps_track_calibration_v1_manifest.csv` — the exact input population;
2. `activity_summary.csv` — metadata, integrity counts, all requested
   distributions, processing state, and per-activity query/profile timings;
3. `segment_distribution_summary.csv` — one activity/metric row with valid and
   missing counts plus min/mean/p50/p90/p95/p99/max;
4. `diagnostic_segments.csv` — bounded inspectable examples.

Diagnostics retain approximately three examples per activity/category and are
also capped at 30 rows per category report-wide. Exact known reference segment
identities are always retained; a missing reference pair is emitted explicitly
as `REFERENCE_SEGMENT_MISSING`. The “disagreement within activity p95 speed”
category is an exploratory within-activity ranking, not a universal plausible
speed or corruption threshold. Zero device-distance increments with geographic
movement are kept separately.

Endpoint coordinates are personal location data. Keep the manifest and all four
reports outside version control, and do not paste coordinate-bearing diagnostics
into tickets or committed test fixtures.

If any activity cannot be queried or profiled, the partial CSVs retain an
explicit `FAILED` activity row and the command exits nonzero. Such output must
not be presented as a complete population calibration. Console telemetry reports
activities succeeded/failed, total sample rows, total runtime, the maximum track
size, and the two read-only query plans; per-activity query/profile durations are
retained in `activity_summary.csv`.

## Interpretation and limitations

This sample is stratified and deliberately enriched with known faults and
extremes. It is not a prevalence sample. Counts from it must not be described as
the percentage of all platform activities that are corrupt.

The output supports later review of candidate policies, but this phase defines
no definitive thresholds. In particular:

- a time gap may be a legitimate stop;
- direct Haversine displacement can disagree with travelled device distance;
- activity-relative percentiles are diagnostic ordering tools only;
- individually valid coordinates can still be wrong;
- missing Raw `latlng` activities are excluded from this population rather than
  being treated as valid tracks.

The scripts are unscheduled, read-only research tools. They make no Raw,
Silver, Gold, Admin, schema, validation, notification, or operational changes.
