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

## Freshness

Freshness has four separate meanings:

- **execution recency**: when an entity or phase last completed successfully;
- **source-data recency**: the newest source-domain timestamp known to Raw;
- **publication recency**: when a layer most recently passed its publication gate;
- **validation recency**: when publication or deep validation last succeeded.

They must not be substituted for one another. A successful endpoint with an
unchanged newest source timestamp is `UNCHANGED`, not failed or stale. A failed
latest endpoint remains visible even when previously acquired source data is
recent.

`source_freshness_observation` stores the one fact that cannot be reconstructed
reliably after Raw upserts: the newest source-domain timestamp known when each Raw
entity execution ended. The current value and its change from the preceding
observation are exposed by `v_source_freshness_latest`. It is recorded for both
successful and failed Raw runs when an entity execution exists.

`source_entity_observability_policy` owns entity requirement and execution
freshness thresholds. Required scheduled entities influence source and platform
health. Optional entities remain visible but ordinary low-frequency or absent
data does not make an entire source unhealthy. Strava child retrieval entities
are conditional and therefore do not age merely because no activity needed
repair. Google Health Exercise is optional; the remaining scheduled Google
Health entities are required.

Daily Raw, Silver and Gold publication use 30-hour WARNING and 48-hour CRITICAL
execution thresholds. Deep validation uses 48 and 72 hours. Publication means a
successful publication-check phase, not merely a transform write.

## Operational Debt and Health

The governed health vocabulary is:

- `HEALTHY`: the condition is present and within contract;
- `UNKNOWN`: there is not yet enough trustworthy evidence;
- `INFO`: a deliberate non-actionable or optional condition;
- `WARNING`: attention is warranted but usable publication/recovery remains;
- `CRITICAL`: current correctness, execution or recovery needs action.

Roll-up precedence is `CRITICAL` → `WARNING` → `INFO` → `UNKNOWN` → `HEALTHY`.
Missing evidence is not automatically critical. A required never-observed entity
is UNKNOWN; an optional never-observed entity is INFO.

### Validation outcome contract

Validation execution and validation assessment are separate governed facts:

- `validation_run.run_status` describes execution lifecycle: `RUNNING`, `SUCCESS`,
  `FAILED`, or `TIMED_OUT`.
- `validation_run.validation_outcome` describes the completed assessment:
  `PASSED`, `PASSED_WITH_WARNINGS`, `FAILED`, or `TIMED_OUT`.
- `validation_run_check.check_status` and `severity` retain individual check
  evidence. A failed `INFO` check is observational and does not by itself degrade
  the governed outcome; a failed `WARNING` check yields
  `PASSED_WITH_WARNINGS`; failed `CRITICAL` or legacy `ERROR` checks yield
  `FAILED`.
- `v_validation_history.health_status` is the stable consumer mapping:
  `PASSED` → `HEALTHY`, `PASSED_WITH_WARNINGS` → `WARNING`, and `FAILED` or
  `TIMED_OUT` → `CRITICAL`. Incomplete, malformed, or unsupported evidence is
  `UNKNOWN`, never optimistically healthy.

Older deployed databases predate persisted validation summaries. Migration 016
adds the already-canonical summary columns without rewriting historical rows.
For a historical successful execution whose persisted outcome is null,
`v_validation_history` derives the same outcome from its durable per-check
evidence. It refuses to infer an outcome from incomplete or malformed evidence.
New executions persist the governed outcome directly.

Historical execution rows remain immutable: a past `FAILED` execution stays
failed even after later recovery. Current health instead consumes the latest
governed validation outcome per scope through `v_operational_debt_latest`. This
prevents an informational historical finding from becoming a false critical
condition while ensuring real warnings, failures, timeouts, and unknown current
state remain visible. Grafana and other read consumers must use these Admin views
rather than independently reclassifying checks.

For current health, "latest" means the latest **terminal assessment**, not the
latest execution that started. Terminal validation states are `SUCCESS`, `FAILED`,
and `TIMED_OUT`. They are ordered independently within each `validation_scope` by
`completed_at DESC, validation_run_id DESC`. A newer `RUNNING` execution therefore
does not establish recovery from the preceding completed failure or warning. A
later completed `PASSED` assessment does establish recovery.

A scope with execution history but only active executions has no completed
assessment and is `UNKNOWN`. When there is no validation history anywhere, the
existing aggregate behaviour remains `HEALTHY`; Slice 3C deliberately does not
introduce a global missing-history policy. The latest terminal record is not
skipped merely because its governed outcome is `UNKNOWN`: incomplete, malformed,
or unsupported terminal evidence remains visible as uncertainty rather than
falling back to an older healthy result.

Active execution is assessed separately. A validation left `RUNNING` for more
than six hours contributes to `stale_child_execution` without replacing the
latest terminal assessment. An earlier failed assessment and a stale retry may
therefore both be actionable at once. Historical rows reconciled administratively
record reconciliation time in `completed_at`; that timestamp does not claim to be
the original execution's actual completion time. Platform health inherits these
semantics from `v_operational_debt_latest` without recalculating them.

### Latest terminal daily pipeline

The `latest_daily_pipeline` debt condition is based on the daily execution whose
terminal result became known most recently. Terminal executions are `SUCCESS` or
`FAILED`; `RUNNING` is not evidence of recovery. The ordering is
`completed_at DESC, pipeline_run_id DESC`, so overlapping executions that finish
out of start order are governed by completion order and an exact timestamp tie is
resolved deterministically by the execution identifier.

A failed terminal execution remains current debt while a later retry is running.
It clears only when a terminal `SUCCESS` completes after it. Active execution is
otherwise neutral: a non-stale run is not made critical merely for running, while
the separate stale-execution conditions classify pipeline and child executions
left `RUNNING` for more than six hours as `CRITICAL`.

`v_operational_debt_latest` owns the current debt catalogue:

| Debt | Classification |
|---|---|
| Raw child PENDING | WARNING |
| Raw child FAILED | CRITICAL |
| Achievement evaluation INVALIDATED | CRITICAL |
| Notification PENDING | WARNING |
| Notification RETRY, FAILED, or SENDING for over one hour | CRITICAL |
| Latest daily pipeline failed | CRITICAL |
| Pipeline or child execution RUNNING for over six hours | CRITICAL |
| Latest validation outcome in a scope PASSED_WITH_WARNINGS | WARNING |
| Latest validation execution/outcome in a scope failed or timed out | CRITICAL |
| Latest validation execution/outcome in a scope is incomplete or untrusted | UNKNOWN |
| Google Health daily ingestion coverage UNRESOLVED | WARNING |
| Google Health daily ingestion coverage UNKNOWN | UNKNOWN |
| Backup health | Classification from the backup contract below |

This is current state, not a duplicated debt-event history. Existing execution,
validation, notification and backup histories show when most transitions occurred.
Automatic repair of stale RUNNING rows remains deferred; detection is deliberate.

### Google Health daily ingestion recovery

`v_google_health_daily_ingestion_failure_history` is the authoritative recovery
contract for failed resting-heart-rate, heart-rate-variability, and respiratory-rate
entity executions. Its grain is one historical failed `etl_run_entity`. The failed
execution and sanitised error remain immutable evidence; recovery is derived from
`etl_request_log` rather than written back to that history.

Request dates are inclusive start/exclusive end. A failed execution is `RECOVERED`
only when every distinct recorded request window is covered by later successful
requests for the same source and entity, and those requests belong to terminally
successful entity executions. Adjacent successful intervals may collectively cover
a failed interval. `recovery_completed_at_utc` is the point at which the last
required day first became demonstrably covered. Duplicate failed windows create one
coverage obligation. Missing or invalid failed-window telemetry is `UNKNOWN`, not
implicitly recovered; incomplete evidence is `UNRESOLVED`.

The implementation expands an individual failed DATE interval to its constituent
days. Scheduled daily-entity requests are one day and the normal refresh window is
small, so this remains bounded in normal operation. MariaDB's recursive-CTE limit is
therefore not approached by governed ingestion. An unusually large manually logged
single request interval above that database limit is a documented limitation and
must not be treated as recovered without inspecting the query result.

The deep validation check
`raw_google_health_daily_entities_recent_failures` consumes this view and warns on
`UNRESOLVED` and `UNKNOWN`; it no longer embeds its own recovery SQL or ages debt out
after 14 days. The same states feed `v_operational_debt_latest`, and therefore the
existing platform-health severity roll-up. Recovered incidents remain queryable in
history but do not degrade current health. This keeps recovery semantics in Admin
for validation and future Grafana consumers.

## Dashboard-facing Admin Views

Grafana and future operational MCP tools may consume these stable read models:

| View | Purpose |
|---|---|
| `v_platform_health_latest` | Single current platform roll-up |
| `v_pipeline_run_history` | Pipeline outcomes and durations |
| `v_pipeline_phase_history` | Seven-phase outcomes, durations and notification work |
| `v_transform_performance_history` | Transform timing, workload and governed Gold metrics |
| `v_source_freshness_latest` | Entity execution and source-data freshness |
| `v_source_health_latest` | Required-entity roll-up per external source |
| `v_publication_freshness_latest` | Raw/Silver/Gold/deep-validation recency, plus platform-owned Silver/Gold upstream-lag state |
| `v_operational_debt_latest` | Current actionable debt catalogue |
| `v_validation_history` | Validation execution history, governed outcomes and check counts, with conservative legacy derivation |
| `v_backup_health_latest` | Latest attempt, complete recovery point and reconciliation health |
| `v_backup_history` | Physical attempts linked to complete verified recovery points |
| `v_api_request_failure_history` | Sanitised failed/retried request evidence |
| `v_google_health_daily_ingestion_failure_history` | Historical failed daily-entity executions with authoritative request-window recovery state |

Helper views prefixed with the same domain names support these contracts but are
not intended as primary dashboard APIs.

### Operational view text collation

MariaDB can infer the connection collation for text produced solely from string
literals, particularly `CASE` and `UNION ALL` outputs. Operational view DDL must
apply `COLLATE utf8mb4_general_ci` explicitly to every generated textual output
at its originating expression. Text selected directly from canonical table or
view columns retains the source column collation. This prevents the compiled
view contract from depending on the session used to run bootstrap.

For string functions, collating only the final result is insufficient. MariaDB
must first reconcile the function operands. Every generated string operand and
literal delimiter must therefore be given an explicit compatible character set
and collation inside the function call. The recovery view uses
`CAST(... AS CHAR CHARACTER SET utf8mb4) COLLATE utf8mb4_general_ci` together
with an explicitly introduced and collated `_utf8mb4` delimiter for this reason.
This keeps view execution and `SHOW CREATE VIEW` independent of whether a client
negotiates MySQL's `utf8mb4_0900_ai_ci` or MariaDB's
`utf8mb4_uca1400_ai_ci`.

The transform history view exposes `has_phase_1b_metrics`. A new no-op Gold run
has explicit zero metrics and this flag set; a pre-Phase-1B run has null metrics
and the flag unset. Consumers must preserve that distinction.

## Backup Health

`backup_attempt` is a physical attempt. `backup_run` is only a complete verified
five-database recovery point. `v_backup_health_latest` separately exposes the
latest attempt, latest recovery point, recovery-point age and latest retention
reconciliation. A failed attempt after a usable recovery point is WARNING;
missing/incomplete reconciled files or a recovery point older than 48 hours are
CRITICAL; no recovery point is UNKNOWN. The existing 30/48-hour backup thresholds
remain authoritative.

Routine daily-platform and validation notifications consume
`v_backup_health_latest` directly. They present its governed overall status, the
latest physical attempt, the latest usable recovery point and reconciliation
evidence as distinct facts. They do not recalculate freshness thresholds or
reinterpret reconciliation counts. A governed `UNKNOWN` is shown as such; an
empty, malformed or failed view query is shown separately as `UNAVAILABLE`, never
as healthy.

This routine current-state summary is separate from the immediate Mac backup
failure notification. The latter remains an event alert emitted by the physical
backup workflow, while routine notifications report the latest governed Admin
state without creating another backup alert.

## Time and Duration Semantics

All operational timestamps are UTC instants; `_utc` view suffixes make this
explicit. Presentation clients may convert them to local time. Dynamic ages use
the database UTC session clock.

`transform_run.duration_seconds` remains the authoritative whole-second duration.
Phase 1B components retain subsecond precision, so their sum may exceed a
truncated zero-second total by less than one second. This is documented rather
than changing a mature column solely for arithmetic aesthetics.

## Retention and Rollout Boundary

Structured operational history is retained indefinitely initially. Phase 1B does
not backfill older component timings, workloads, notification counts, source IDs,
or requests; null/absent pre-migration telemetry must not be interpreted as zero.

Phase 1C begins source-freshness history only after deployment; no earlier state
is fabricated. Operational history remains retained indefinitely initially.
Grafana, its read-only account and provisioning, immutable notification-attempt
history, automatic stale-execution repair, richer backup detail and historical
telemetry reconstruction remain deferred.
