# Activity Achievements

`gold.activity_achievements` records reusable achievement facts produced by
cycling activities. It replaces the retired scraper's direct notification logic
with governed Gold facts plus an Admin notification outbox.

## Ownership

* Gold records what achievement happened.
* Admin records whether a notification has been queued, sent, failed or should
  retry.
* Notification runners render and deliver messages.
* `cycling-analytics` may display achievement history, but does not own
  achievement detection.

## Gold Object

Table:

```text
cycling_platform_gold.activity_achievements
```

Grain:

```text
activity_id x achievement_type x metric_name x duration_seconds
x comparison_scope x comparison_period_start x comparison_period_end
```

Business key:

* `activity_id`
* `achievement_type`
* `metric_name`
* `duration_seconds`
* `comparison_scope`
* `comparison_period_start`
* `comparison_period_end`

The physical primary key is deterministic:

```text
activity_achievement_key
```

For activity-level achievements, `duration_seconds = 0`. For all-time
achievements, period dates use sentinel values `1000-01-01` and `9999-12-31`
so the MariaDB uniqueness rule remains enforceable.

## Implemented Achievements

Version 1 implements:

* all-time best watts effort for configured durations;
* calendar-year best watts effort for configured durations;
* all-time and calendar-year longest distance;
* all-time and calendar-year longest moving duration;
* all-time and calendar-year highest elevation gain.

Power effort achievements consume `gold.activity_best_efforts` where
`metric_name = 'watts'`. They do not recalculate rolling stream windows.

Activity-level achievements consume canonical fields from `silver.activities`:

* `distance_metres`
* `moving_time_seconds`
* `elevation_gain_metres`

## Comparison Policy

Comparison scopes are explicit:

* `all_time`
* `calendar_year`

Calendar-year achievements use the activity's own calendar year.

Tie policy:

* an achievement requires a strictly greater stored metric value;
* equal values do not create a new achievement;
* rounding is presentation-only.

For all-time achievements, `previous_best_value`, `previous_best_activity_id`
and `previous_best_date` store the previous all-time best where one existed.
All-time notification text omits recency phrasing.

For calendar-year achievements, recency is looked up against all earlier
activities, not only earlier activities in the same calendar year. The stored
`days_since_previous_best` is the number of whole calendar days since the most
recent earlier equal-or-better comparable result. If no such result exists, the
recency fields are `NULL`.

## Backfill Safety

Historical backfill populates Gold history only. It does not queue
notifications by default.

Notification eligibility is set only for `daily` achievement transforms.
Backfill and repair modes leave `notification_eligible = 0`.

Manual commands:

```sh
Rscript scripts/gold/run_activity_achievements.R repair
Rscript scripts/gold/run_activity_achievements.R backfill
```

Initial deployment order:

```sh
Rscript bootstrap_platform.R
Rscript scripts/gold/run_activity_best_efforts.R backfill
Rscript scripts/gold/run_activity_achievements.R backfill
Rscript run_daily_platform.R scheduled
```

The explicit achievement backfill establishes historical record context with
`notification_eligible = 0`. The following daily platform run can then ingest
new activities, refresh Gold, queue only newly eligible recent achievements,
and deliver notifications without flooding historical records.

## Durable Evaluation State

`cycling_platform_gold.activity_achievements` remains a sparse fact table: an
activity with no record achievement has no Gold fact row. Transform completeness
is recorded separately in
`cycling_platform_admin.activity_achievement_evaluation_state`, at one row per
activity and achievement calculation version.

`CURRENT` means facts and the stored zero-or-positive `achievement_count` were
committed together for the recorded semantic input signature. `INVALIDATED`
means the state must not be used as evidence of current evaluation. State has no
foreign key to current Silver because future deletion recovery may need to retain
technical evidence after a source entity disappears.

The input signature contains the activity local date, achievement-relevant
metric/type/duration/value rows, the achievement calculation version and the
best-effort calculation version. It excludes transform timestamps, run timestamps
and other volatile metadata.

DAILY uses state-driven candidate selection only after an explicit backfill has
created complete `CURRENT` state for every Silver activity. Before initialization,
DAILY retains conservative selection and does not infer or create state from
sparse fact presence. A no-change trusted daily context then selects only missing,
invalidated or fact-count-inconsistent state; normally this is zero activities.

DAILY distinguishes three dependency paths. No relevant change selects no work.
A pure insertion after the current `(start_date_local, activity_id)` history
boundary evaluates only the appended activity. A historical insertion or material
summary, best-effort, date, or enumerated power-eligibility change invalidates
every state row from the earliest affected local date and reevaluates that
inclusive date-forward closure. All same-date activities are included, preserving
the existing activity-ID tie-break.

The input signature proves only that one activity's own inputs are current; it
does not encode prior historical context. Durable closure invalidation provides
that dependency guarantee. The whole closure is marked `INVALIDATED` before the
first evaluation batch, and each successful fact/state transaction restores its
activities to `CURRENT`. REPAIR resumes from the earliest missing, invalidated,
signature-stale, source-version-stale, or fact-count-inconsistent activity.

Calculation-version changes require explicit backfill rather than an implicit
expensive DAILY rebuild. Global classification changes and non-authoritative
deletion/exclusion events require explicit REPAIR/REBUILD. REPAIR cannot initialize
an entirely empty state table: initial state still requires explicit backfill.

Audit candidate selection without publishing changes:

```sh
Rscript scripts/gold/audit_activity_achievement_evaluation_state.R
```

Preview a proposed historical closure without changing data:

```sh
Rscript scripts/gold/audit_activity_achievement_invalidation.R 2025-06-14
```

Durable historical invalidation reasons are controlled operational values:
`HISTORICAL_ACTIVITY_CHANGE`, `HISTORICAL_INSERT`, `BEST_EFFORT_CHANGE`,
`POWER_ELIGIBILITY_CHANGE`, `DATE_CHANGE`, and `REPAIR`. The legacy
`explicit_backfill` value remains valid for full rebuild recovery state.

Phase 3 date-forward invalidation is implemented. No-change runs remain empty,
pure latest appends evaluate only the appended activities, and historical
changes invalidate the inclusive closure from the earliest affected local date.
The read-only closure and evaluation-state audits remain the supported way to
inspect this behaviour. An explicit full backfill remains the semantic oracle;
comparisons must have zero semantic differences. Do not manufacture or mutate a
production activity for testing.

This reports the old conservative candidate count alongside state-driven repair
debt. Canonical deletion/exclusion propagation remains unresolved; orphan facts
cause an actionable REPAIR failure rather than silent deletion.

For a retained before/after full-rebuild equivalence check, capture the semantic
Gold fields to a local snapshot, run the explicit backfill, then compare against
the snapshot:

```sh
Rscript scripts/gold/audit_activity_achievement_evaluation_state.R \
  snapshot /tmp/activity-achievements-before.rds
Rscript scripts/gold/run_activity_achievements.R backfill
Rscript scripts/gold/audit_activity_achievement_evaluation_state.R \
  compare /tmp/activity-achievements-before.rds
```

The comparison excludes operational timestamps, notification state and run
lineage. It exits non-zero if a business key exists on only one side or any
semantic value differs. Use a persistent host-mounted path instead of `/tmp`
when snapshot and comparison run in separate ephemeral containers.

### Evaluation-state initialization

After deploying and bootstrapping the additive Admin table, capture the audit
signature, run the explicit historical rebuild, then audit again:

```sh
Rscript scripts/gold/audit_activity_achievement_evaluation_state.R
Rscript scripts/gold/run_activity_achievements.R backfill
Rscript scripts/gold/audit_activity_achievement_evaluation_state.R
```

The sparse fact semantic signature printed before and after must match. The
post-backfill audit must report one `CURRENT` state per Silver activity, zero
`INVALIDATED` rows and zero state-driven candidates. The conservative candidate
count may remain large because it deliberately exposes the retired sparse-fact
selection defect.

Database reconciliation queries:

```sql
SELECT COUNT(*) AS silver_activities
FROM cycling_platform_silver.activities;

SELECT evaluation_status, calculation_version, COUNT(*) AS state_rows,
       SUM(achievement_count) AS recorded_facts
FROM cycling_platform_admin.activity_achievement_evaluation_state
GROUP BY evaluation_status, calculation_version;

SELECT COUNT(*) AS sparse_facts
FROM cycling_platform_gold.activity_achievements
WHERE calculation_version = 'activity_achievements_v1';

SELECT COUNT(*) AS fact_count_mismatches
FROM cycling_platform_admin.activity_achievement_evaluation_state state
LEFT JOIN (
  SELECT activity_id, calculation_version, COUNT(*) AS fact_count
  FROM cycling_platform_gold.activity_achievements
  GROUP BY activity_id, calculation_version
) facts
  ON facts.activity_id = state.activity_id
 AND facts.calculation_version = state.calculation_version
WHERE state.calculation_version = 'activity_achievements_v1'
  AND state.evaluation_status = 'CURRENT'
  AND state.achievement_count <> COALESCE(facts.fact_count, 0);
```

## Notification Outbox

Table:

```text
cycling_platform_admin.notification_outbox
```

The outbox grain is one notification bundle per activity/channel/message
payload. Each bundle contains all newly eligible achievements for that activity.
The stable outbox `source_key` is derived from the sorted achievement keys in
the bundle.

Uniqueness rule:

```text
event_type x source_object x source_key x channel
```

Statuses:

* `PENDING`
* `SENDING`
* `SENT`
* `RETRY`
* `FAILED`

Delivery failures increment `attempt_count`, preserve `error_message`, and set
`next_attempt_at` until the configured maximum attempts is reached.

Manual notification runner:

```sh
Rscript scripts/operations/run_notifications.R queue
Rscript scripts/operations/run_notifications.R deliver
Rscript scripts/operations/run_notifications.R queue_and_deliver
```

Daily automation runs queue and delivery after Gold publication checks. A
delivery failure does not roll back Gold facts, but the daily automation status
is failed so the issue is visible and retryable.

## Legacy Behaviour Reviewed

The retired scraper calculated peak efforts for cadence, heart rate, watts,
velocity and distance, then sent ntfy messages for records. It also sent a
separate FTP-style notification based on 20-minute power.

The platform implementation keeps the useful behaviour, grouped achievement
notifications, but moves detection into Gold and delivery state into Admin.
FTP-related notifications are deferred until Gold training-load objects exist.

## Deferred

* top-three historical ranks;
* cadence and heart-rate achievement notifications;
* speed achievements;
* monthly records;
* route-specific achievements;
* FTP change notifications;
* downstream display in `cycling-analytics`.

## Assumptions

The implemented DDL, transform code, tests, and successful production runs are
the source of truth. Historical implementation notes should not be interpreted
as current deployment constraints.
