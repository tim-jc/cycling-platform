# G3B.3 candidate diagnostic research plan

Status: owner-approved research direction; G3B.3 not commenced

## Research governance

G3B.3 consists of seven separately authorised and accepted increments. Approval
of this plan does not authorise any increment. Each increment requires a bounded
commission, declared evidence inputs, explicit deliverables and acceptance
criteria, an owner review gate, and a separate closure decision before the next
increment starts.

The work develops measurements and diagnostics before any qualification policy.
It uses synthetic fixtures and calibration evidence, preserves the existing
holdout, records parameters without selecting production thresholds, and creates
no automatic qualification or production integration.

Every diagnostic evaluation uses a common framework:

1. successful detection of supported target phenomena;
2. missed detection in reviewed target cases;
3. legitimate behaviour incorrectly flagged;
4. sensitivity to candidate parameters and descriptive scales; and
5. missing, malformed, degenerate or unavailable evidence.

Outcomes must be reported per case and cannot be collapsed into one quality
score. Detection performance and boundary performance are evaluated separately.

## G3B.3A — Measurement consolidation

**Objective.** Inventory and assess existing Platform measurement capabilities
before adding code. Consolidate, reuse and verify existing time, coordinate,
distance, speed, bearing, repetition, bridge and contextual measurements. Add a
new implementation only for a demonstrated semantic or coverage gap.

**Deliverables.** Capability inventory with source locations and semantics;
duplication/gap analysis; canonical research measurement vocabulary; synthetic
edge fixtures; reproduction of all 54 accepted quantitative findings; bounded
recommendations for any missing measurements.

**Acceptance criteria.** Every candidate measurement is classified as reusable,
reusable with correction, missing or unsuitable; numeric/missing/degenerate
semantics are explicit; existing calculations are verified rather than silently
replaced; no diagnostic or classification output is introduced.

**Owner gate.** Owner accepts the inventory, consolidation decisions and any
proposed additions before G3B.3B.

## G3B.3B — Independent diagnostics

**Objective.** Develop temporal, repetition, implied-movement, bearing and
distance-consistency diagnostics independently using the common evaluation
framework.

**Deliverables.** Independently callable diagnostic algorithms; versioned
evidence outputs; per-candidate evaluation reports covering detections, misses,
legitimate flags, sensitivity and missing evidence; counterexample register.

**Acceptance criteria.** Each diagnostic is explainable and independently
testable; evaluation includes ordinary, stationary and disturbed controls;
failures and contradictory signals remain visible; no combined rule, threshold
policy or automatic qualification is created.

**Owner gate.** Owner reviews empirical behaviour and separately accepts each
candidate retained for subsequent research.

## G3B.3C — Cumulative discrepancy research

**Objective.** Evaluate rolling-window, event-driven excursion and near-zero-reset
approaches as three independent candidates. Measure accumulation, peak, rate,
duration, persistence and reconciliation without choosing a production method.

**Deliverables.** Three independently reproducible implementations or research
prototypes; shared case/evaluation harness; parameter-sensitivity results;
interactive owner-review material for Kingston, clean movement, isolated credible
steps, underground disturbances and non-reconciling examples.

**Acceptance criteria.** No approach is treated as default; active accumulation
is distinguished from persistence; each approach reports detection, misses,
legitimate flags, sensitivity and missing evidence; interactive findings are
preserved with provenance; no reset tolerance, window or qualification threshold
is selected.

**Owner gate.** Owner reviews the empirical comparisons and decides which, if
any, proceed as research diagnostics.

## G3B.3D — Multi-scale contextual analysis

**Objective.** Investigate contextual behaviour using both observation-count and
elapsed-time windows. Immediate scope is retrospective whole-activity analysis;
future real-time/streaming use is a distinct, deferred problem.

**Deliverables.** Explicit count-window and time-window semantics; retrospective
context calculations; parameter-sensitivity comparisons; boundary and missing-
context behaviour; tests showing how sustained displacement can form a misleading
local baseline.

**Acceptance criteria.** Window bases are never conflated; irregular sampling and
partial windows remain explicit; reordered-input determinism and activity-boundary
behaviour are verified; legitimate stationary/ordinary controls and missed
disturbances are reported; no real-time design or contextual score is introduced.

**Owner gate.** Owner accepts the retrospective evidence and determines whether
any real-time investigation is warranted later.

## G3B.3E — Diagnostic episode modelling

**Objective.** Model overlapping diagnostic episodes without claiming that they
are positional-disturbance intervals.

**Deliverables.** In-memory conceptual/experimental episode contract; examples of
known and unknown onset, known and unknown termination, missing-evidence
interruptions, intermittent evidence, overlapping episodes and unresolved
episodes at activity termination; boundary evaluation separate from detection.

**Acceptance criteria.** Unknown boundaries remain unknown; gaps do not become
continuous observed disturbance; terminal unresolved episodes remain open rather
than receiving fabricated termination; accepted episode examples reconstruct;
diagnostic and geographic boundaries may disagree explicitly.

**Owner gate.** Owner accepts episode semantics before cross-diagnostic synthesis.

## G3B.3F — Cross-diagnostic synthesis

**Objective.** Describe co-occurrence, sequence, lag, contradiction and
independence among versioned diagnostics without creating a qualification engine.

**Deliverables.** Traceable case matrices; relationship/lag descriptions;
supporting and adverse examples; sensitivity to missing diagnostics; hypotheses
for later qualification-policy research.

**Acceptance criteria.** Source diagnostics remain independently inspectable;
correlation is not presented as causation; contradictory evidence remains visible;
no composite score, automated classification or policy threshold is produced.

**Owner gate.** Owner decides whether evidence is mature enough to design a
separate qualification-policy research programme.

## G3B.3G — Independent evaluation, subject to evidence partitioning

**Objective.** Evaluate frozen diagnostics on evidence not used to develop or
tune them while preserving enough independent evidence for a later qualification
policy evaluation.

**Prerequisite.** Before any holdout is exposed, approve a durable partitioning
plan distinguishing diagnostic-development evidence, independent diagnostic-
evaluation evidence, future qualification-policy development evidence and future
independent qualification-policy evaluation evidence.

**Deliverables.** Approved evidence partition; frozen algorithm/parameter
identities; independent diagnostic evaluation report covering detections, misses,
legitimate flags and missing evidence; contamination register; reserved evidence
statement for later policy assessment.

**Acceptance criteria.** The existing holdout is not inspected before separate
authorisation and partition approval; diagnostic evaluation is not represented as
qualification-policy evaluation; all failures and uncertainty are reported; any
example used for refinement is marked no longer independent.

**Owner gate.** Owner separately authorises exposure, accepts the diagnostic
evaluation, and decides whether qualification-policy research may begin.

## Cross-cutting dependencies

Production use still requires durable stream representation and sample identity,
authoritative chronology, full-resolution eligibility, diagnostic and policy
versioning, reproducible evidence persistence, and source/policy invalidation.
These do not block pure research but prevent production qualification claims.

Each increment should deliver synthetic fixtures, calibration-only evidence,
version identities, counterexamples, parameter records and an owner review. No
production integration or subsequent increment is implicit.
