# GPS diagnostic candidate catalogue

Status: G3B.2B owner-accepted research design; no algorithm or threshold authorised

Each candidate is independently testable. Outputs are measurements or diagnostic
evidence, never automatic qualification.

All candidates use one evaluation framework: successful detection, missed
detection, legitimate behaviour incorrectly flagged, parameter sensitivity and
missing/degenerate evidence. Results remain case-level and diagnostic-specific.

| Candidate | Purpose and grain | Required inputs and semantics | Supporting evidence | Counterexamples and limitations | Proposed G3B.3 deliverable |
|---|---|---|---|---|---|
| Temporal discontinuity | Measure gaps, non-increasing time and repeated timestamps at segment/run/episode grain | Original sample order and elapsed/absolute chronology; preserve zero, missing and decreasing values | Long gaps in `48062184`, `31856627`, `1128729284`; duplicates in `31722499` | Stops, workday interruption and duplicate records can be legitimate; a gap does not observe the intervening path | Pure measurement functions, degenerate-input fixtures and descriptive distributions |
| Implied movement | Describe geographic displacement per elapsed time at segment and contextual-window grain | Full-resolution coordinates and positive elapsed time; undefined for non-positive time | Extreme `31856627` 5392→5393 | Ordinary displaced tracks can have plausible speed; stationary jitter can create misleading speed | Segment calculation plus contextual comparisons, without a universal limit |
| Bearing behaviour | Measure initial bearing, changes and reversals at segment/sequence grain | Valid non-zero geometry; circular angular arithmetic | Office and car-park disturbances; Kingston uniformity | Hairpins, junctions and real turns; undefined for stationary segments; onset 5357→5358 is numerically ordinary | Circular-measurement library and labelled case reports |
| Geographic/reported-distance consistency | Measure signed, absolute and relative discrepancy at segment/window grain | Geographic distance and source-reported cumulative distance, with provenance | Kingston divergence/reconciliation; underground cases | Reported distance is not independent; accepted `44605096` has a large isolated step | Exact measurement contract and source/device-stratified descriptive analysis |
| Cumulative discrepancy excursion | Characterise accumulation, peaks, persistence and reconciliation at episode/window grain | Ordered segment discrepancies and explicit missing/gap handling | Kingston −44.457/+45.942 m | Clean gradual accumulation, persistent steps and disturbances without reconciliation | Compare rolling, event-driven and reset representations without selecting parameters |
| Coordinate/time repetition | Describe identical-position/time runs at run/sequence grain | Exact original coordinates, timestamps and sample identity | `31722499` and `31709557` benign repetitions | Duplicate source records and genuine stationary recording are observationally different but may look alike | Run extractor preserving mechanism as unknown |
| Movement uniformity | Detect unusually low variation in displacement, speed or bearing at window/episode grain | Ordered finite measurements and declared scale | Kingston 1459–1471; uniform post-duplicate movement in `31722499` | Straight roads and steady riding are legitimate; a displaced sequence can define a false normal baseline | Multi-scale variation measures evaluated against controls |
| Local contextual coherence | Compare a focus observation/segment with neighbours at observation/segment grain | Adjacent and bridge evidence, missing-neighbour semantics | Existing Stage 1 prototype and isolated excursions | Neighbours may also be unreliable; first/last samples have incomplete context | Reproducible local features and explicit missingness tests |
| Multi-scale context | Compare local, medium and episode-scale behaviour retrospectively | Ordered evidence, observation-count and elapsed-time windows, no inferred timestamps | Sustained acquisition/reacquisition episodes | Scale selection can leak thresholds and blur separate episodes; real-time use has different evidence availability | Parameterised retrospective count/time windows evaluated only on calibration evidence |
| Diagnostic episode delineation | Represent bounded diagnostic patterns and boundary uncertainty | Versioned diagnostic outputs, chronology and sample lineage | Cannon Street, Kingston, office onset/recovery | Diagnostic and geographic boundaries differ; onset/termination can be unknown; gaps interrupt evidence; terminal episodes can remain unresolved | Episode data contract and comparison framework, not an automated disturbance classifier |
| Cross-diagnostic relationships | Identify co-occurrence, lag, contradiction and independence | Independently produced diagnostic events with version identity | Numerical recovery before geographic recovery; anomalies outside disturbance | Correlation does not establish causation; combining signals can overfit | Case-based relationship matrix and prospective hypotheses |

## Evaluation and dependencies

| Candidate | Missing/degenerate input treatment | Evaluation method | Dependencies |
|---|---|---|---|
| Temporal discontinuity | Preserve missing time; classify zero/decreasing differences explicitly; do not invent duration | Synthetic order/duplicate/gap cases plus descriptive comparison across reviewed controls and disturbances | Original sample identity and authoritative chronology |
| Implied movement | Undefined for non-positive/missing time or invalid endpoints | Reproduce reviewed extremes and ordinary/stationary controls; inspect parameter sensitivity later | Geographic displacement and temporal measurement |
| Bearing behaviour | Undefined for zero-length/invalid geometry; use circular differences | Junction/hairpin controls versus reviewed reversals, uniform runs and onset/recovery cases | Ordered valid coordinates and movement measurement |
| Distance consistency | Preserve missing/reset/decreasing cumulative values rather than repairing them | Reproduce accepted quantitative claims; stratify future descriptions by source/device where known | Geographic distance, reported-distance provenance and sample alignment |
| Cumulative discrepancy | Break or explicitly bridge only under a declared missing/gap convention | Compare representations on Kingston, clean controls, isolated steps and non-reconciling disturbances | Ordered segment discrepancy and temporal continuity |
| Coordinate/time repetition | Preserve each original sample and count exact runs | Synthetic repeated/mixed cases and reviewed benign duplicate examples | Durable original sample identity |
| Movement uniformity | Require a declared finite window; report insufficient sample count | Compare variation measures across straight-road controls and displaced uniform sequences | Speed, displacement and circular-bearing measurements |
| Local contextual coherence | Mark unavailable neighbours and activity boundaries explicitly | Isolated excursion, boundary, stationary and sustained-disturbance cases | Adjacent/bridge measurements and original ordering |
| Multi-scale context | Report incomplete count/time windows without shrinking them silently | Calibration-only retrospective sensitivity study across observation-count and elapsed-time scales | Local measurements and declared scale parameters; real-time use deferred |
| Episode delineation | Preserve unknown onset/termination, missing-evidence interruptions, intermittency and unresolved terminal episodes | Compare diagnostic episodes with owner milestones while scoring detection and boundaries separately | Versioned diagnostic outputs and chronology |
| Cross-diagnostic relationships | Retain missing diagnostics and contradictory evidence independently | Case matrices, lag/co-occurrence descriptions and later prospective validation | Independently versioned diagnostic families and episode identity |

Missing or malformed inputs remain explicit. No diagnostic silently repairs,
interpolates or map-matches evidence. Parameter exploration must preserve the
calibration/holdout split and separate development examples from later independent
validation evidence.
