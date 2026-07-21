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
Rscript run_gold_activity_achievements.R repair
Rscript run_gold_activity_achievements.R backfill
```

Initial deployment order:

```sh
Rscript bootstrap_platform.R
Rscript run_gold_activity_best_efforts.R backfill
Rscript run_gold_activity_achievements.R backfill
Rscript run_daily_platform.R scheduled
```

The explicit achievement backfill establishes historical record context with
`notification_eligible = 0`. The following daily platform run can then ingest
new activities, refresh Gold, queue only newly eligible recent achievements,
and deliver notifications without flooding historical records.

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
Rscript run_platform_notifications.R queue
Rscript run_platform_notifications.R deliver
Rscript run_platform_notifications.R queue_and_deliver
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

This design was implemented while production MariaDB was unavailable. Repository
DDL, transform code and tests were treated as source of truth.
