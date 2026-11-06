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

The original v1 calibration run wrote four local CSVs:

1. `gps_track_calibration_v1_manifest.csv` — the exact input population;
2. `activity_summary.csv` — metadata, integrity counts, all requested
   distributions, processing state, and per-activity query/profile timings;
3. `segment_distribution_summary.csv` — one activity/metric row with valid and
   missing counts plus min/mean/p50/p90/p95/p99/max;
4. `diagnostic_segments.csv` — bounded inspectable examples.

The subsequent Phase 0B extension added `local_context_diagnostics.csv` to the
runner's output contract. It contains at most 30 candidate observations per
activity with adjacent and bridge evidence. This additive capability does not
make the immutable original four-file snapshot incomplete. Do not regenerate or
overwrite the original evidence to add the later report.

Diagnostics retain approximately three examples per activity/category and are
also capped at 30 rows per category report-wide. Exact known reference segment
identities are always retained; a missing reference pair is emitted explicitly
as `REFERENCE_SEGMENT_MISSING`. The “disagreement within activity p95 speed”
category is an exploratory within-activity ranking, not a universal plausible
speed or corruption threshold. Zero device-distance increments with geographic
movement are kept separately.

Endpoint coordinates are personal location data. Keep the manifest and generated
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

## Phase 0B local-context evidence

Candidate observations are drawn from the existing bounded segment diagnostics
and the longest repeated-coordinate runs. The report retains at most 30 unique
observations per activity. It measures, without classifying:

- previous-to-current and current-to-next Haversine displacement;
- the direct previous-to-next Haversine bridge (useful evidence for an isolated
  excursion followed by a return);
- elapsed time, device-distance increment, and implied geographic speed for
  both adjacent segments;
- inbound/outbound initial bearings and the absolute direction change, only
  when both adjacent displacements are non-zero and coordinates are valid;
- repeated-coordinate run length and elapsed duration.

First and last observations have missing unavailable neighbours. Invalid or
missing endpoints yield missing geometry, and non-positive elapsed time never
produces an implied speed. The bridge does not replace the observed path: it is
local diagnostic evidence only. Geometry cannot prove whether a coordinate was
interpolated, extrapolated, or generated by a device.

## Pooled population calibration

The population runner uses the same eligibility and fixed source cutoff as the
45-activity manifest, but processes every eligible activity (or a deterministic
pilot subset) one at a time. It retains only one activity's samples and segments
plus aggregate counters. It does not retain population-level coordinate rows.

Segments are pooled rather than averaging per-activity percentiles and are
stratified by:

- sport family (`CYCLING`, `RUNNING`, `WALKING_HIKING`, `WATER`, `WINTER`,
  `OTHER`, or `UNKNOWN`);
- activity recording density (`LOW`, `MIDDLE`, `HIGH`), assigned as deterministic
  equal-count rank thirds of samples per elapsed hour;
- observed segment elapsed-time band, including separate `MISSING`, `INVALID`,
  and non-positive bands.

For each of the seven existing segment measures, the output records the exact
segment denominator and separate finite, missing, and non-finite counts. Finite
values are accumulated into fixed-bin exact histograms. Counts are exact for the
processed population, but quantiles inferred from them are only located within
the published bin bounds; open-ended extreme bins provide no finite error bound.
The bin edges are diagnostic resolution, **not qualification thresholds**.

The four population reports are:

- `population_segment_histogram.csv` — exact bin counts by stratum/metric;
- `population_stratum_summary.csv` — denominators and evidence availability;
- `population_activity_execution.csv` — per-activity status and timings;
- `population_failures.csv` — explicit incomplete work.

Run a bounded pilot first:

```sh
Rscript scripts/audits/run_gps_track_population_calibration.R \
  "$HOME/Documents/Cycling/audits/gps-track-population-pilot" 100
```

The command reports a simple linear full-population runtime estimate. Review
activity failures, throughput, the largest activity, and local output size before
requesting approval for the full pass. After approval, omit the limit:

```sh
Rscript scripts/audits/run_gps_track_population_calibration.R \
  "$HOME/Documents/Cycling/audits/gps-track-population-full"
```

Both commands are read-only. A failed activity is retained in the execution and
failure CSVs and makes the command exit nonzero. The stratified 45-activity sample
remains the manual-review set; it must not be used as a prevalence estimate.

## Reference windows and manual labels

Generate the governed starting request file once, then locate the blank current-
source windows by review rather than inventing coordinates or sample indexes:

```sh
Rscript scripts/audits/generate_gps_track_reference_window_requests.R \
  "$HOME/Documents/Cycling/audits/gps-reference-window-requests.csv"

Rscript scripts/audits/run_gps_track_reference_windows.R \
  "$HOME/Documents/Cycling/audits/gps-reference-window-requests.csv" \
  "$HOME/Documents/Cycling/audits/gps-reference-window-results"
```

The original registry-based extractor emits bounded Silver observation context,
segment rows, extraction status, and `manual_label_template.csv`. Observation
and segment rows are separate label grains. Every row begins `UNREVIEWED`; the
only permitted manual values are `ACCEPTED`, `UNCERTAIN`, `REJECTED`, and
`UNREVIEWED`. Provenance, reviewer, review time, and rationale are retained. A
deterministic SHA-256 split assigns whole activities to `CALIBRATION` or
`HOLDOUT`, preventing segments from one activity leaking between partitions.

Later investigations produced supplemental governed windows that verify Raw
`time`, `latlng`, and `distance` arrays positionally against Silver observations
before emitting review evidence. Reviewed-label snapshots merge the applicable
original and supplemental evidence while retaining source provenance and
evidence keys. A historical `WINDOW_NOT_LOCATED` status in the original
registry extraction records that run's outcome; it does not contradict a
subsequently completed supplemental investigation.

### Raw/Silver investigation commands

Three parameterised, read-only commands support new investigations. All output
directories must be outside the repository. They may be new or empty, but the
commands refuse to replace any intended output file and check all collisions
before writing.

Inspect duplicate or non-increasing timestamps, retaining Raw array positions
and the positional Silver comparison:

```sh
Rscript scripts/audits/extract_gps_duplicate_timestamps.R \
  31709557 \
  "$HOME/Documents/Cycling/audits/activity-31709557-duplicate-timestamps-new"
```

The optional third argument changes the number of surrounding observations from
the default of five.

Locate the maximum-displacement and maximum-implied-speed segments with bounded
context and Raw/Silver verification:

```sh
Rscript scripts/audits/extract_gps_extreme_segments.R \
  15562928333 \
  "$HOME/Documents/Cycling/audits/activity-15562928333-extremes-new"
```

This command also accepts an optional context-observation count as its third
argument. It uses neutral `LARGEST_DISPLACEMENT` and `HIGHEST_IMPLIED_SPEED`
case keys by default. To reproduce the original Reading and Kingston evidence
keys exactly, supply both explicit keys after the context value:

```sh
Rscript scripts/audits/extract_gps_extreme_segments.R \
  15562928333 \
  "$HOME/Documents/Cycling/audits/activity-15562928333-extremes-new" \
  5 READING_LARGEST_DISPLACEMENT KINGSTON_HIGHEST_IMPLIED_SPEED
```

Explicit governed windows use a request CSV with these columns:

- `activity_id`;
- unique `case_key` containing letters, digits, underscores, or hyphens;
- `window_from_sample_index` and `window_to_sample_index`;
- optional `focus_from_sample_index` and `focus_to_sample_index`, supplied
  together;
- optional consecutive `focus_segment_from_sample_index` and
  `focus_segment_to_sample_index`, supplied together;
- non-empty `evidence_note`.

Run the request with:

```sh
Rscript scripts/audits/extract_gps_governed_reference_windows.R \
  "$HOME/Documents/Cycling/audits/kingston-window-request.csv" \
  "$HOME/Documents/Cycling/audits/supplemental-reference-windows-new"
```

Each request is written beneath the output directory using its `case_key`. The
Kingston request that reproduces the established window uses activity
`15562928333`, window `1448` through `1477`, focus observations `1453` through
`1472`, and focus segment `1471` to `1472`. Use a new output root; do not point
the command at the immutable 2026-11-06 evidence.

The earlier registry workflow remains the Silver-only cohort extractor. These
commands add Raw-array provenance and require exact Raw/Silver positional
agreement; they do not replace or rewrite the registry's historical status.

The registry marks activities `659466921` and `227124704` as
`HISTORICAL_EVIDENCE_REQUIRED`. Their current Strava-derived data is post-crop;
absence of the former continuation/tunnel anomaly is not profiler failure and
must not be replaced by a fabricated source-faithful fixture. Other cases with
unknown indexes remain `CURRENT_SOURCE_LOOKUP_REQUIRED` until a reviewer records
the bounded window.

## Qualification readiness

The readiness decision is `READY_WITH_CONDITIONS`, based on the completed
population audit and the governed reviewed-label snapshot dated 2026-11-06.
Its 48 reviewed decisions are selected calibration examples, not a
representative prevalence sample.

An offline, non-publishing qualification prototype may compare explainable
candidate classifications with the governed evidence. Numerical qualification
thresholds are not approved. No production qualification policy or Explorer
tile publication is authorised by this decision.

## Stage 1 offline qualification prototype

Stage 1 implements only deterministic structural semantics and the machinery
needed to represent contextual evidence. It classifies observations and
segments independently as `ACCEPTED`, `UNCERTAIN`, or `REJECTED`. An execution
or input-contract failure is never converted to geographic uncertainty.

The version-controlled experimental policy is returned by
`default_gps_qualification_policy()` in
`R/quality/gps_qualification_prototype.R`. Its deterministic rules reject
missing/out-of-range observations, unusable segment endpoints, and movement
over non-positive elapsed time. A stationary duplicate timestamp is retained as
supporting evidence and is not rejected. Contextual acceptance and all
numerical empirical rules remain disabled and carry unapproved `NA` candidate
parameters. Consequently, structurally valid entities without a deterministic
decision normally remain `UNCERTAIN` in this first baseline.

The policy fingerprint is a SHA-256 of its canonical, name-sorted structure.
Decision output also records a feature-contract version, evaluation run ID and
per-entity input signature. Reason rows distinguish determining acceptance,
uncertainty and rejection from supporting diagnostics.

The offline audit runner takes an evidence manifest, the immutable reviewed
label snapshot, and a new external output directory:

```sh
Rscript scripts/audits/run_gps_qualification_prototype.R \
  "$HOME/Documents/Cycling/audits/gps-qualification-input-manifest.csv" \
  "$HOME/Documents/Cycling/audits/gps-reference-window-results/manual_label_reviewed_2026-11-06.csv" \
  "$HOME/Documents/Cycling/audits/gps-qualification-stage1-new"
```

The input manifest contains one `observation_path,segment_path` pair per
governed evidence source. An optional `case_key` filters a multi-case source to
one governed case. Inputs and the label snapshot are hashed into the run
manifest. Output is refused inside the repository, inside an input/evidence
directory, or wherever any intended output filename already exists. The runner
does not connect to MariaDB or publish to Gold, Reference, Admin, Explorer tiles
or any governed evidence location.

Evaluation scores only reviewed rows, keeps `UNREVIEWED` rows in the coverage
report, separates observations from segments and CALIBRATION from HOLDOUT, and
reports the individual HOLDOUT cases. The three reviewed HOLDOUT rows do not
support a statistically reliable holdout-performance claim. Empirical rule
calibration and Explorer tile eligibility remain explicitly deferred.
