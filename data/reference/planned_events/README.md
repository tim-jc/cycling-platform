# Planned-event authoring

Each top-level YAML file in this directory is one curated event. The filename
without its extension must equal its immutable event key. The normal publisher
reads and validates the complete directory before starting one database
transaction.

Copy [planned_event.yml.example](planned_event.yml.example) when creating an
event. The example suffix prevents the template from being published.

Rules:

- event key, event name, start date, event type, coaching intent and explicit
  cancellation are required;
- coaching intent is either prepare_for or plan_around;
- a null end date means the event is one day and ends on its start date;
- optional stages require a stable stage key, but every other stage field is
  optional;
- distance and elevation are exact whole metres;
- blank optional text becomes database NULL; unknown metrics remain NULL;
- stages have no implicit ordering;
- removing a stage from an event file removes that published stage;
- deleting an entire event file does not delete its database event;
- cancel an event by retaining its file and setting cancellation to true.

Publish and validate after platform bootstrap:

    Rscript scripts/reference/publish_planned_events.R
    Rscript scripts/reference/validate_planned_events.R

Review the Git diff before deployment. Do not curate production through ad hoc
SQL.
