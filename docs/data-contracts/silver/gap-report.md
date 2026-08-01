# Silver data-contract gap report

Date: 2026-07-31  
Scope: current persistent Silver objects only  
Contracts: `activities`, `activity_streams`, `gear`

## Executive assessment

The Silver implementation has strong mechanical grains, keys, lineage fields,
rebuild paths and cross-layer validation. Its principal catalogue gap is not
structural metadata; it is agreement about what the objects mean, how far their
canonical claims extend beyond Strava, and which embedded classifications are
owned platform policy.

The draft contracts therefore avoid converting implementation behaviour into
unreviewed semantic truth.

## Semantic gaps

### Cross-object

* “Canonical” is not bounded consistently. All three objects have source-neutral
  names but are currently Strava-derived.
* Accountable semantic ownership is not named separately from repository/code
  ownership.
* Source identifiers (`activity_id`, `gear_id`, `athlete_id`) are used as
  platform keys without a documented multi-source identity strategy.
* Compatibility expectations for consumers are absent: there is no stated
  policy for column removal, vocabulary changes, semantic versioning or notice.
* SQL `DATETIME` fields do not carry timezone information; UTC/local meanings
  are conventional rather than enforced by type.

### Activities

* The business definition of an activity is unstated.
* `sport_type` and `activity_type` are currently identical, with no separate
  meaning for the latter.
* Power provenance and record eligibility are material business rules, but the
  classification vocabularies, policy owner and scope are not contractual.
* The distinction between source facts, platform interpretations, convenience
  conversions and ingestion-completeness flags is not explicit at object level.
* Mutable Strava attributes are republished as current values; historical-value
  expectations are undocumented.

### Activity streams

* The shared positional sample grain assumes arrays align by index. The source
  guarantee and accepted failure modes are not documented.
* Time, distance, movement, smoothing, altitude and coordinate semantics remain
  source concepts without platform definitions.
* Missing values cannot currently distinguish an unavailable stream, a short
  array, a failed request, a non-applicable metric or a true source null.
* Precision policy is unstated where numeric payload values are cast to integer.

### Gear

* “Current” means membership in the latest successful source collection, not an
  agreed lifecycle status.
* “Historical” is the inverse of current membership, not an SCD/history claim.
* Only resolved objects exist in Silver, making `resolution_status='RESOLVED'`
  invariant and leaving unresolved semantics outside the entity.
* Future mapping to bike-library identity, temporal naming and lifecycle
  ownership are unresolved.

## Documentation gaps

* No named data steward or semantic approver for any Silver object.
* No accepted business glossary for power status/type/rule/reason values.
* No declared source-service-level expectation defining when Raw completeness
  flags can be trusted.
* No contract for consumers outside this repository, including expected joins,
  allowed filters and fallback presentation.
* No coordinate privacy or sensitive-location handling statement.
* No explicit unit/precision/rounding catalogue beyond column names and code.
* No agreed null taxonomy separating unknown, unavailable, not applicable and
  not ingested.
* No freshness or publication-latency expectation for Silver objects.
* No formal schema/semantic compatibility policy for contract versions.

## Architectural opportunities

These are opportunities for semantic clarity, not style-only changes.

1. **Complete contract ownership and semantic review.** The governance states
   now exist; assign an accountable semantic owner and resolve or explicitly
   accept the structured TODOs before lifecycle promotion.
2. **Define canonical scope explicitly.** Decide whether current Silver objects
   are canonical Strava projections or source-neutral platform entities. Avoid
   premature renaming; first agree the abstraction boundary.
3. **Create governed vocabularies.** Power classification fields and gear types
   need enumerated meanings, owners, change rules and consumer compatibility
   expectations.
4. **Separate event truth from processing evidence conceptually.** Existing
   lineage fields are useful, but contracts should label them as operational
   metadata so consumers do not treat them as business event attributes.
5. **Establish time semantics once.** A reusable platform convention should
   cover UTC storage, local wall time, source timezone, daylight-saving
   ambiguity and processing timestamps.
6. **Define identity evolution.** Document how source IDs map to future athlete,
   activity and bike-library identifiers before a second source is onboarded.
7. **Formalise stream alignment.** Confirm Strava positional guarantees and add
   a declared quality expectation for unequal arrays before treating the wide
   row as semantically canonical.
8. **Catalogue external consumer expectations.** Record which consumers require
   stable current names, historical names, power eligibility, GPS, or unit
   convenience fields.
9. **Use generated metadata as a review trigger.** The validator now flags DDL
   drift while keeping human semantic text deliberately non-generated; future
   CI can run the same repository-only command.

## Suggested human review order

1. Agree object purpose, owner and canonical scope.
2. Agree activity and stream grain semantics, especially time and positional
   alignment.
3. Approve power and gear controlled vocabularies.
4. Confirm consumer and compatibility commitments.
5. Convert agreed quality expectations into contract tests in a separate task.
