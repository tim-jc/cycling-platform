# GPS qualification scientific methodology

Status: G3B.2B owner-accepted and closed, 20 November 2026

This document defines the scientific method for future GPS diagnostic and
qualification research. It defines no algorithm, parameter, threshold, physical
schema or production policy. Its evidence baseline is the owner-accepted
`gps-qualification-stage2ca-scientific-reconciliation-v2-2026-11-20` package.

## Scientific position

The platform has no routine independent absolute positional reference. GPS
qualification is therefore an inference problem. Five dimensions remain
separate: positional credibility, temporal continuity, measurement consistency,
kinematic plausibility and contextual credibility. Measurements are reproducible
facts derived from recorded evidence; diagnostics are interpretations of those
measurements; qualification is an explicit inference about credibility. Multiple
diagnostics may coexist or contradict one another. No opaque composite quality
score is authorised.

The terms **geographic distance** and **reported distance** retain their accepted
meanings. Reported distance is not assumed independent or authoritative.
Agreement establishes consistency, not positional accuracy; disagreement
establishes inconsistency, not necessarily positional error.

## Pillar 1 — detection

Anomalous movement and inaccurate position are different phenomena:

| Position | Movement | Empirical example |
|---|---|---|
| Credible | Ordinary | Activity `48062184`, 2343→2344 clean movement control |
| Credible | Anomalous | Activity `989877988`, 211→212: accepted endpoints and segment despite 15.3997 m geographic movement with no reported-distance increase |
| Inaccurate | Locally ordinary | Activity `31690375`, samples 87–108: sustained northward displacement with plausible local direction and distance consistency |
| Inaccurate | Anomalous | Activity `31856627`, 5392→5393: disturbed episode containing 134.528 m movement in three seconds |

The absence of adverse diagnostics cannot establish accuracy. Candidate
diagnostics are grouped initially as temporal, kinematic, measurement-consistency,
sequence, and longitudinal/episode diagnostics. This taxonomy is a research aid,
not an implementation boundary.

## Pillar 2 — delimitation

Detection and boundary identification are separate problems. The evidence shows
numerically unremarkable geographic onset and recovery (`31856627` around 5357
and 5415), numerical recovery before geographic recovery (`3057187825` and
`1128729284`), persistent accumulated discrepancy after recovery (`989877988`),
and sustained positional displacement without material distance disagreement
(`31690375`, 87–108).

A **diagnostic episode** is a bounded pattern of diagnostic evidence, not
necessarily a positional disturbance. It may record family/type, contributing
observations and segments, onset and termination, duration, magnitude,
persistence, intermittency, internal structure, accumulation/reconciliation,
relationships to other episodes and boundary uncertainty. Episodes may overlap
or disagree. Onset or termination may be unknown. Missing evidence may interrupt
an episode without proving its end, and an episode may remain unresolved when an
activity terminates. An unobserved gap is not a continuously observed disturbance.

Cumulative signed distance discrepancy remains a distinct research area. Active
accumulation must be distinguished from persistence of an earlier discrepancy.
Kingston (`15562928333`, 1459–1472) accumulated −44.457 m before a +45.942 m
reconciliation event. By contrast, credible activity `44605096` has an isolated
8.122 m step whose cumulative effect persists, clean activity `48062184`
accumulates small divergence, and underground disturbances may recover
geographically without resetting accumulated discrepancy. No rolling window,
reset tolerance or episode threshold is selected here.

## Pillar 3 — specificity

Diagnostics must be tested against legitimate alternatives: stationary
behaviour, duplicate records, junctions and hairpins, activity interruptions,
steady straight-road movement, source-specific distance behaviour and persistent
effects of an earlier isolated inconsistency. Confirmed examples include the
geographically correct duplicate initial observations in `31722499`, credible
stationary/near-stationary endpoints around `48062184` 5857→5858, and the clean
movement controls. A possible group stop is plausible context, not confirmed
history.

Absolute diagnostics compare measurements with defensible physical or structural
expectations. Contextual diagnostics compare them with surrounding evidence.
Neither dominates. Surrounding evidence may itself be unreliable: Kingston's
uniform displaced sequence and Cannon Street's sustained displacement establish
locally coherent but geographically wrong baselines.

## Pillar 4 — qualification

Observation and segment qualification are independent. Credible endpoints do
not prove connecting geometry, and a rejected segment does not reject either
endpoint. Activities `15562928333` 10420→10421 and `31856627` 6239→6240 provide
explicit examples.

Outcomes are categorical:

- **ACCEPTED** — sufficient supporting evidence under the applicable policy.
- **UNCERTAIN** — evidence is insufficient, incomplete or contradictory.
- **REJECTED** — sufficient adverse evidence supports unreliability.
- **UNREVIEWED** — no qualification assessment; not an outcome equivalent to
  `UNCERTAIN`.

Conservative inference prefers false negatives to false-positive tile visits,
but absence of an anomaly is not automatic acceptance and absence of affirmative
evidence is not automatic rejection. The burden of evidence remains a calibration
question.

Explorer visitation remains sample-only: an eligible, accepted, full-resolution
observation inside a tile is required. Uncertain/rejected observations,
connecting geometry, interpolation and corner clipping do not qualify a tile.
Accepted stationary observations may qualify it. Qualification policy remains
separate from tile geometry and aggregation.

## Pillar 5 — continuous empirical validation

An initial deployed policy is a versioned baseline, not a final solution.

Reactive validation compares Platform outcomes with VeloViewer to locate disputed
tiles, activities, full-resolution observations, diagnostics, decisions and policy
versions. VeloViewer is a comparator, not truth. Differences are classified as:
correct exclusion, credible evidence withheld, inaccurate evidence accepted,
intentional method difference, geometry/aggregation defect, source or
representation difference, or unresolved.

Prospective tile-hunting validation records intended tiles before a ride, actual
completed visits afterward, qualified outcomes, missing/unexpected tiles and the
supporting evidence. Intent and recollection are imperfect. A missing tile can
reflect route deviation, sampling absence, positional error, appropriate
conservatism, incorrect withholding, a platform defect or unresolved evidence.

Periodic positive-visitation audits examine accepted evidence and unexpected new
tiles so validation does not drift toward permissiveness. Once evidence informs
policy development it leaves the independent evaluation pool. Policy refinement
must preserve reviewed evidence, reproduce current behaviour, test candidate
changes against development and regression evidence, assess favourable and
adverse effects, obtain owner approval, version the replacement and regenerate
affected products. Per-tile exceptions are prohibited.

Independent diagnostic evaluation and independent qualification-policy
evaluation are separate gates. Freezing and evaluating a diagnostic consumes
independent evidence for that diagnostic; it must not exhaust or contaminate the
evidence reserved for later evaluation of a policy that combines diagnostics and
applies an inference burden. Evidence partitioning must be approved before any
existing holdout is exposed.

## Architectural implications

- **Explainability:** decisions retain supporting measurements, diagnostics and
  reasons.
- **Traceability:** included and withheld geographic evidence is traceable to
  observations, qualification and policy version.
- **Versioning:** source representation, measurements, diagnostics,
  qualification policy and geographic calculation have identities.
- **Reproducibility:** outcomes can be regenerated from source evidence and
  versioned methods.
- **Invalidation:** source correction/cropping and policy changes invalidate and
  regenerate affected activity and lifetime products.
- **Ownership:** Cycling Platform owns evidence, diagnostics, qualification and
  canonical geography. Explorer presents and investigates governed results; it
  does not own qualification logic.

These are conceptual requirements only. Physical persistence and APIs remain
future design work.

## Unresolved methodological questions

1. What evidence burden is sufficient for acceptance at observation and segment
   grain?
2. Which diagnostic parameters generalise across sports, devices, recording
   densities and environments?
3. How should partially observed and overlapping diagnostic episodes be compared?
4. How can contextual methods avoid normalising a sustained displaced baseline?
5. What independent prospective evidence is feasible without treating owner
   recollection or VeloViewer as ground truth?
6. How should policy-development, regression and independent-validation evidence
   be partitioned over time?
7. Which source/representation lineage is required before production
   reproducibility and invalidation are possible?
