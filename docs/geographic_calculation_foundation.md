# Geographic calculation foundation (G3A)

Status: Accepted  
Implemented: 2026-11-17  
Formally accepted: 2026-11-17

## Boundary

G3A is a pure, deterministic R calculation foundation. It has no database,
pipeline, persistence, scheduling, production qualification, Explorer, maximum
square, cluster, heatmap, country or Ride Finder integration. Qualification is
supplied as evidence; the calculation does not infer it.

The owner formally accepted G3A, including its bounded acceptance remediation,
on 17 November 2026. Acceptance does not promote any provisional numeric
convention to empirically verified external compatibility and does not authorise
G3B or production integration.

Cycling Platform owns the calculations and future governed products. Explorer is
a read-only presentation consumer. Tests are pinned to Explorer commit
`f93beddc07a0d2b6378a596cc1b2a9ac7f4b55ca`, fixture format 1. Explorer files
were inspected and not modified.

Pinned fixture SHA-256 values are:

- `tile_geometry.json`: `f11fd577cbcdd938ed325c120d1c7e416e2ff1b0a78aae56e61147519cf187b6`;
- `tile_evidence.json`: `4627340c8c6466933a0b9c167e664dfc12ab9c59e2f12ccd622b49bd6a6bd87f`; and
- `history.json`: `3c4c2f6625ccb4b2163414de3ae0d1ff2d346cda5332dcc39f41762eea25b485`.

## Zoom-14 tile geometry

`R/geography/explorer_tile_geometry.R` implements the 16,384 by 16,384 zoom-14
Web Mercator grid without materialising it.

- identifiers are canonical `z/x/y` text, for example `14/8192/8192`;
- x increases eastward and y increases southward;
- coordinates are ordered longitude, latitude;
- the forward equations are `(longitude + 180) / 360 * 2^14` and
  `(1 - asinh(tan(latitude)) / pi) / 2 * 2^14`;
- tile ownership is half open: west and north edges are included, east and
  south edges belong to the adjacent tile;
- +180 degrees aliases the -180-degree seam; values outside `[-180, 180]` are
  rejected rather than wrapped;
- supported latitude is
  `(-85.0511287798066, +85.0511287798066]`; the southern edge is excluded;
- projected values within `1e-9` tile units of an integer are snapped before
  flooring to make decimal inverse-edge fixtures deterministic;
- missing, nonnumeric, non-finite and out-of-range coordinates fail explicitly;
- bounds are west/south/east/north and centres are projected tile centres, not
  arithmetic averages of latitude edges.

The grid mathematics is independently established. The seam, southern-limit,
half-open and snap choices are **provisional Platform conventions** inherited
from accepted Explorer Slice 2 fixtures. They are not empirical VeloViewer
compatibility evidence. Web Mercator tiles are not constant physical one-square-
kilometre areas.

Snapping deliberately differs from strict mathematical half-open geometry in a
very narrow directional strip. At zoom 14, `1e-9` tile units is approximately
`2.20e-11` longitude degrees (about 2.4 micrometres at the equator). Points just
west or north of a boundary inside that tolerance snap onto the boundary and are
therefore owned by its east or south tile. This deterministic convention exists
only to handle binary64 representations of authored inverse edges; it is not a
GPS acceptance buffer and requires future external verification.

## Observation input contract

`calculate_activity_tile_evidence()` accepts a data frame with:

| Field | G3A meaning |
| --- | --- |
| `activity_key` | Positive signed-BIGINT identity supplied as `integer64`, R integer, or canonical decimal text. R doubles are rejected. |
| `stream_representation_id` | Synthetic/current representation identity supplied by the caller. Platform has not yet established a durable production representation key. |
| `sample_index` | Original non-negative index in the supplied representation. It is not renumbered. |
| `longitude`, `latitude` | Full-resolution observation coordinates when present. |
| `qualification_status` | Supplied `ACCEPTED`, `UNCERTAIN` or `REJECTED` observation decision. |
| `full_resolution_eligible` | Explicit caller assertion; reduced representations cannot qualify. |
| `observed_at_utc` | Explicit UTC instant or missing. Missing chronology stays unknown. |
| `qualification_policy_version` | Supplied policy lineage; no policy is inferred. |
| `source_lineage` | Supplied source evidence reference. |
| `representation_lineage` | Supplied representation provenance. |

One calculation cannot mix representation, policy or lineage values for one
activity. Replacement is the unit of change. Duplicate representation/sample
keys are malformed input.

Current Silver `activity_streams.sample_index` is generated one-based, while
Explorer Slice 2 fixtures use zero-based synthetic indexes. G3A deliberately
accepts non-negative supplied indexes and preserves them verbatim. A future
production adapter must bind the index to a durable representation identity; it
must not treat fixture indexes as the current Silver business key by accident.

Silver exposes elapsed `time_seconds`, not an authoritative observation UTC
timestamp. G3A therefore accepts explicit chronology but never manufactures it
from activity ingestion time or assumes that elapsed time is sufficient.

## Evidence policy and outcomes

A tile qualifies only from an `ACCEPTED`, full-resolution observation whose
coordinate resolves to that tile. Segments, interpolation, corner clipping,
uncertain/rejected samples and reduced representations never qualify a tile.
Accepted stationary or repeated observations may establish presence.

Observation diagnostics preserve four independent characteristics:

- `coordinate_status`: `VALID`, `MISSING` or `MALFORMED`;
- the supplied `qualification_status` unchanged;
- the supplied `full_resolution_eligible` flag; and
- the derived `tile_evidence_eligible` flag.

The single explanatory `evidence_outcome` additionally uses:

- `QUALIFYING`;
- `NON_QUALIFYING_STATUS`;
- `NON_FULL_RESOLUTION`;
- `MISSING_COORDINATE`; and
- `MALFORMED_COORDINATE`.

Coordinate status is evaluated regardless of qualification or resolution. Thus a
malformed rejected observation remains both `MALFORMED` and `REJECTED`; neither
fact conceals the other. Malformed table structure, keys, lineage or timestamps
fail the calculation. Invalid coordinate observations are retained in diagnostic
outcomes but excluded from positive evidence. Empty/GPS-less input produces an
explicit empty result.
That result means no qualifying evidence was supplied, not proof of physical
absence.

## Activity and lifetime aggregation

Activity evidence has one row per `(activity_key, tile_id)`. It records count,
ordered original sample-index references, first/last known supplied observation
times, chronology completeness, representation, qualification and lineage.
Repeated observations do not duplicate the relationship. Results are sorted and
independent of input row order.

Lifetime visitation has one row per `tile_id` for one explicitly coherent
qualification policy. It records distinct canonical
activity count, exact contributing activity keys, first/last known visit and
activity where supported, chronology completeness, the one policy version, and
contributing representation identities. Mixed policy input fails rather than
being combined or silently partitioned. Unknown times are not replaced with publication or
ingestion time. Known extrema remain queryable when some contributors are
unknown, while `chronology_complete = FALSE` prevents consumers claiming a
globally proven first or last visit.

Known chronology ties use the canonical activity key as deterministic secondary
order: smallest key for first, largest key for last. The key has no temporal
meaning; it only prevents input row order choosing the result.

`replace_activity_tile_evidence()` removes the current evidence for one stable
canonical activity and optionally inserts its complete replacement. Withdrawal
inserts nothing. Synthetic tests cover backfill, new publication, republication,
representation/policy/timestamp correction, sole-evidence removal, withdrawal
and reordered processing. Replacement aggregation equals reconstruction from the
same current evidence. G3A is not an incremental invalidation engine.

An ordinary single-activity representation or timestamp correction retains the
current population qualification policy and can be aggregated immediately. A
qualification-policy transition is a whole-population operation: partially
replaced evidence is intentionally rejected by lifetime aggregation until every
contributing activity has been recalculated under the new policy. Separate policy
products must be calculated through separate explicit calls.

## Explorer Slice 2 conformance

| Fixture family | G3A result | Boundary |
| --- | --- | --- |
| `tile_geometry.json` | Passed all coordinate-to-tile resolved expectations; independent bounds/centre assertions passed | Provisional seam/limit/snap cases are not empirical VeloViewer evidence |
| `tile_evidence.json` | Passed all 9 cases | Segment/corner intersection flags themselves are outside G3A; their required non-visitation result passed |
| `history.json` | Passed applicable visited-tile counts and first/last activity chronology | Maximum-square and cluster fields are not applicable to G3A; unresolved cluster fields remain unresolved |

The mandatory segment-only case produces endpoint tiles `14/8191/8192` and
`14/8193/8192`; target `14/8192/8192` is absent.

Fixture conformance tests read the pinned sibling Explorer checkout. A different
location can be supplied through `EXPLORER_REPOSITORY`; if the checkout is absent,
only those cross-repository conformance cases skip while independent Platform
geometry/evidence tests continue to run. No Explorer code is imported at runtime.
Before executing conformance cases, tests verify the exact Explorer revision,
fixture SHA-256 values and format version. A missing checkout is reported as a
skip, not successful conformance; a present but divergent checkout fails.

## Future interfaces and unresolved dependencies

G3B or a later governed slice must decide:

- durable canonical stream/representation identity;
- authoritative source-faithful sample evidence key and index base;
- how full-resolution eligibility is established and governed;
- authoritative absolute observation chronology, including missing time;
- qualification policy/version publication and replacement;
- persistent sample-reference representation rather than G3A's explanatory CSV;
- Gold physical schemas, indexes, invalidation and rebuild mechanics;
- reference-geography ownership and versioning; and
- storage/runtime scale using production-derived counts.

No permanent geographic product should use Strava `activity_id`. It must resolve
and persist the immutable Platform `activity_key`.

## Downstream Explorer handoff

G3A establishes deterministic zoom-14 tile geometry, sample-only accepted
observation evidence, one activity/tile relationship, lifetime distinct-activity
visitation, explicit unknown chronology, and replacement-equals-reconstruction
semantics. Explorer may design against those meanings and canonical `activity_key`.
It must not yet assume a physical table/API, production qualification policy,
durable representation/sample key, empirical VeloViewer edge equivalence,
maximum-square/cluster output, or incremental publication mechanism.
