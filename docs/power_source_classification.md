# Power Source Classification

## Purpose

Some historical indoor TrainerRoad activities used roller-based virtual power,
but Strava reports them with `is_device_watts = 1`. Raw data remains unchanged;
the platform classifies analytical eligibility in Silver and Gold.

## Ownership

Admin owns the governed rule and overrides:

- `admin.power_source_classification`
- `admin.activity_power_overrides`

Silver owns the canonical activity-level interpretation:

- `power_source_type`
- `power_source_status`
- `is_measured_power`
- `is_power_record_eligible`
- `power_record_exclusion_reason`
- `power_classification_rule`
- `power_classification_method`
- `power_classification_version`
- `power_meter_cutover_at`

Gold owns record eligibility for calculated efforts:

- `gold.activity_best_efforts.is_record_eligible`
- `gold.activity_best_efforts.record_exclusion_reason`
- `gold.activity_best_efforts.source_classification`
- `gold.activity_best_efforts.power_classification_version`

## Cutover Rule

The inferred `power_meter_cutover_at` is the TrainerRoad measured-power cutoff:
the start timestamp of the earliest genuine outdoor activity where Strava
reports `is_device_watts = 1` on the TrainerRoad roller-bike gear ID:

- `b2708460`

The derivation method is:

```text
earliest_outdoor_device_watts_on_trainerroad_roller_bike
```

The current outdoor candidate definition uses available repository fields:

- `sport_type` in `Ride`, `GravelRide`, `MountainBikeRide`, `EBikeRide`,
  `Handcycle`
- not `VirtualRide`
- `gear_id` is `b2708460`
- usable power data is present
- raw payload `trainer` is not `true`
- a raw `latlng` stream exists, so indoor rides mislabelled as `Ride` cannot
  establish the outdoor power-meter cutoff
- activity name / `external_id` / `device_name` payload text does not match
  `trainerroad`

The cutoff uses the exact timestamp, not only the activity date.

Historical rationale: gear `b2708460` was predominantly used as the
TrainerRoad roller bike. The first genuine outdoor device-watts ride on this
gear is therefore the best available evidence that the roller setup had
acquired a real power meter. Genuine power recorded earlier on another bike
does not establish that TrainerRoad had stopped using virtual power.

Gear `b3311095` may contribute valid measured outdoor power before the
TrainerRoad cutoff. It is excluded only from cutoff derivation, not from
measured-power records.

The cutoff is used to classify historical TrainerRoad sessions. It is not a
claim that every power observation before the cutoff was virtual.

## TrainerRoad Identification

Current metadata does not promote explicit source application or upload-provider
fields. TrainerRoad identification therefore uses the strongest available
retained evidence:

1. payload `external_id` pattern where present
2. payload `device_name` pattern where present
3. activity name pattern

The classification method is stored as `activity_name_or_payload_pattern`.

## Classification Values

`power_source_type`:

- `measured`
- `virtual`
- `estimated`
- `unknown`
- `none`

`power_source_status`:

- `confirmed_measured`
- `confirmed_virtual`
- `inferred_measured`
- `inferred_virtual`
- `ambiguous`
- `unavailable`

Current rules infer, rather than confirm, measured and virtual cases.

## Precedence

1. Active `admin.activity_power_overrides`
2. No usable power -> `none` / not record eligible
3. Pre-cutover TrainerRoad with power -> `virtual` / not record eligible
4. Genuine outdoor device watts with GPS evidence -> `measured` / record
   eligible, even before the TrainerRoad roller-bike cutoff
5. Missing cutoff for other power records -> `unknown` / not record eligible
6. TrainerRoad at or after cutoff with device watts -> `measured` / record
   eligible
7. Device watts at or after cutoff -> `measured` / record eligible
8. Pre-cutover non-outdoor device watts -> `unknown` / not record eligible
9. Non-device watts with power -> `estimated` / not record eligible
10. Fallback -> `unknown` / not record eligible

## Gold Behaviour

Watt best-effort rows are retained even when excluded. They remain available for
audit and alternative analysis.

Measured-power records and power achievements must filter:

```sql
metric_name = 'watts'
AND is_record_eligible = 1
```

Cadence, heart-rate, distance, duration and elevation achievements are not
excluded by power-source classification.

## Rebuild Workflow

Use this order after changing rules or overrides:

```sh
Rscript run_silver.R repair
Rscript run_gold_activity_best_efforts.R repair
Rscript run_gold_activity_achievements.R repair
Rscript run_power_source_classification_audit.R
Rscript run_platform_validation.R
```

Use `backfill` modes only for intentional historical rebuilds. Historical
rebuilds should not queue achievement notifications by default.

## Audit

Generate a CSV audit file:

```sh
Rscript run_power_source_classification_audit.R power_source_audit.csv
```

The report highlights:

- selected TrainerRoad measured-power cutoff activity
- selected cutoff gear ID
- earliest outdoor device-watts activity on `b2708460`
- earliest outdoor device-watts activity on `b3311095`, shown for context but
  rejected as a TrainerRoad cutoff candidate
- earlier valid outdoor powered activities on other gear IDs
- pre-cutover TrainerRoad power activities
- first post-cutover TrainerRoad power activity
- missing-gear activities that might otherwise qualify
- ambiguous power activities
- excluded watt records and replacement eligible records

## Known Limitation

A genuine indoor power-meter activity completed before the first outdoor
device-watts ride may initially be classified as virtual or ambiguous. Correct
those edge cases with an auditable activity-specific override rather than
weakening the general rule.

Raw data is preserved unchanged. Classification changes analytical eligibility;
it does not rewrite source history.
