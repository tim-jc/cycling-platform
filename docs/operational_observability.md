# Operational Observability

`cycling_platform_admin` is the durable authority for platform operational
telemetry. Logs retain diagnostic detail, ntfy remains exception-oriented, and
future dashboards must present these Admin semantics rather than redefine them.

## Execution and Timing

`pipeline_run` and `pipeline_phase_run` provide the top-level execution ledger.
Raw, Silver, Gold, and validation records retain explicit `pipeline_run_id`
lineage. Operational timestamps are written as UTC instants.

For the two Gold transforms, `transform_run.duration_seconds` is the authoritative
complete wall-clock duration. Nullable component fields record setup, discovery,
source preparation, processing, and finalisation. Small differences between the
total and component sum are expected from timer boundaries and bookkeeping. A
missing component means unmeasured, not zero.

Typed execution dimensions record discovery mode, candidate mode, invalidation
action/reason, and dependency start date. Their values are governed in
`R/admin/phase_1b_observability.R` and checked by platform validation.

## Workload Metrics

Stable transform facts remain typed columns. Evolving transform-specific counts
use `transform_run_metric`, uniquely keyed by transform run and metric name.

| Transform | Governed count metrics |
|---|---|
| `activity_best_efforts` | `upstream_affected_count`, `output_changed_activity_count`, `repair_candidate_count` |
| `activity_achievements` | `direct_affected_count`, `evaluation_debt_count`, `closure_activity_count`, `zero_achievement_evaluations`, `evaluation_state_rows_invalidated`, `evaluation_state_rows_current`, `remaining_invalidated_count` |

All use unit `COUNT` and must be non-negative. A new metric requires an explicit
catalogue and validation change; this is not an unrestricted key/value store.

Definitions are deliberately operational:

- `upstream_affected_count`: trusted Silver activities offered to best efforts.
- `output_changed_activity_count`: processed activities whose published best-effort
  facts changed.
- `repair_candidate_count`: candidates found by global REPAIR discovery.
- `direct_affected_count`: direct achievement inputs received before dependency
  closure.
- `evaluation_debt_count`: activities lacking trusted CURRENT evaluation state at
  discovery time.
- `closure_activity_count`: activities in an inclusive historical invalidation
  closure.
- `zero_achievement_evaluations`: evaluated activities producing no sparse facts.
- `evaluation_state_rows_invalidated`: state rows marked invalid before closure work.
- `evaluation_state_rows_current`: state rows made CURRENT by this execution.
- `remaining_invalidated_count`: invalidated state still outstanding at completion.

Existing `transform_run` columns remain authoritative for candidates planned,
activities completed, batches, expected rows, and rows inserted/updated/deleted.
The dimensions describe *how* work was selected: best-effort discovery is
`skipped`, `affected_set`, or `repair_scan`; achievement candidate modes distinguish
evaluation-state no-op, latest append, historical closure, repair, rebuild, and
safe fallback. Invalidation actions are `none`, `latest_append`, or
`historical_closure`; reasons use the existing controlled achievement vocabulary.

The `achievement_notifications` phase stores queued, attempted, sent, failed,
and deferred counts. This does not alter delivery semantics or make routine ntfy
messages verbose.

## Raw Source and Request Telemetry

`etl_run` remains the historical parent. Each `etl_run_entity` also carries its
explicit `source_id`; `api_endpoint_run.source_id` remains the endpoint-level
identity.

`api_request_attempt` records retry-aware evidence beneath an endpoint run:
request sequence/name, safe source reference, attempt number, outcome, retry
decision, HTTP status when available, sanitised failure class/summary, UTC
start/end, and duration. It stores no headers, payload, query string, credentials,
or tokens.

The first instrumented incident path is Strava gear discovery. It distinguishes
`GET /athlete` from `GET /gear/{id}` and records every attempt. HTTP 597 remains
terminal under the existing retry policy: Phase 1B makes that behaviour visible
but does not silently change it.

## Retention and Rollout Boundary

Structured operational history is retained indefinitely initially. Phase 1B does
not backfill older component timings, workloads, notification counts, source IDs,
or requests; null/absent pre-migration telemetry must not be interpreted as zero.

Dashboard views, Grafana, freshness/debt history, richer backup telemetry, and
historical reconstruction remain deferred.
