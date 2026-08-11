# Reference planned events

Reference planned events give coaching a machine-readable view of current
curated season intent. The semantic authority is
[`planned_events.md`](data-contracts/reference/planned_events.md).

## Objects and units

- `cycling_platform_reference.planned_events` contains one event or trip per
  stable `planned_event_id` and authored `event_key`.
- `cycling_platform_reference.planned_event_stages` contains zero or more
  optional planned riding units, keyed by `planned_event_id × stage_key`.
- planned distance and elevation use `DECIMAL(10,0)` exact whole metres.
- event and stage dates are exact local calendar dates, not timestamps.
- `end_date = NULL` means a one-day event ending on `start_date`.

Stages have no implicit order. Reference does not contain realised activities,
route links, training prescriptions or plan-versus-actual state.

## Authoring workflow

1. Copy `data/reference/planned_events/planned_event.yml.example` to
   `data/reference/planned_events/<event_key>.yml`.
2. Set the filename and immutable `event_key` to the same value.
3. Author required event values and any detail genuinely known.
4. Add stages only when a planned ride is useful to reason about separately.
5. Run the local parser/publication tests:

       Rscript -e 'testthat::test_file("tests/testthat/test-reference-planned-events.R")'

6. Review the Git diff and deploy through the normal infrastructure workflow.
7. Bootstrap the platform schema through deployment.
8. Publish and validate inside the application container:

       Rscript scripts/reference/publish_planned_events.R
       Rscript scripts/reference/validate_planned_events.R

The publisher parses and validates every top-level YAML file before opening one
transaction. It then publishes the complete discovered dataset atomically and
runs observational reconciliation after commit.

## Normal edits

- **New event:** add a new file with a new stable `event_key`.
- **Change dates, name, objective or context:** edit the existing file; do not
  change its key.
- **Add a stage:** add an entry with a stable `stage_key`.
- **Remove an obsolete stage:** remove that stage entry. Successful publication
  deletes that stage while retaining all other stages.
- **Cancel an event:** retain the file and set `is_cancelled: true`.
- **One-day event:** set `end_date: null`.

Deleting an entire YAML file does not delete the database event. This is an
intentional protection against accidental loss and retains past plans.

Blank optional text becomes `NULL`. Unknown dates and metrics remain `NULL`;
the loader does not invent zeros, false values or placeholder stages.

## Consumer access

Coaching may consume Reference directly. Upcoming/current non-cancelled events
use:

    SELECT
        planned_event_id,
        event_key,
        event_name,
        start_date,
        end_date,
        COALESCE(end_date, start_date) AS effective_end_date,
        event_type,
        coaching_intent,
        overall_objective,
        location,
        context,
        notes
    FROM cycling_platform_reference.planned_events
    WHERE is_cancelled = 0
      AND COALESCE(end_date, start_date) >= CURRENT_DATE
    ORDER BY start_date, planned_event_id;

Fetch optional stages separately using `planned_event_id`. Consumers must not
infer stage order from IDs, YAML order or response order.

## Deployment and verification

1. Deploy the platform revision. Deployment builds the image and runs
   `bootstrap_platform.R`, which creates the two Reference objects.
2. Run contract validation:

       Rscript scripts/contracts/validate.R

3. Add or review approved event YAML.
4. Publish and validate using the commands above.
5. Query upcoming events and stages using a read-only consumer connection.
6. Confirm Reference is included in the next logical off-host backup.

Initial object creation is owned by numbered `sql/reference/*_create_*.sql`
definitions, not a duplicate migration. Later alterations require an immutable
forward migration. MariaDB DDL auto-commits; after real curation, rollback
normally means rolling back application code while retaining the Reference
tables and data.
