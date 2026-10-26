# Engine Skeleton - Minimum Rule Set + Parallel RE Plan (PROPOSED)

Status: **PROPOSED - awaiting owner approval.** Nothing here is owner-approved canon.
Prepared for the owner's decision via main, answering: "which rules unlock which module,
and how do skeleton construction and remaining RE run in parallel."

## 1. Framing - owner directives and proposals, provenance-separated

Repo rule: artifacts are English. The owner's own words are preserved verbatim,
clearly labeled [TR verbatim], each followed by our [EN] translation.

Owner's own directives (iMessage, 2026-10-09, verified owner-channel):

- [TR verbatim] "bu malzemeyi kullanarak sıfırdan bir engine inşaa edin"
  (phonemsg-01M4GDKPZWV0MJA82368M0BXC0, 16:28:30)
  [EN] "Build an engine from scratch USING this material."
- [TR verbatim] "inşanın kendisi onlardan çıkacak demedim"
  (phonemsg-01M4GDMEVM2KDJ1FM8T43A3J6V, 16:28:55)
  [EN] "I did not say the construction itself comes out of them." - the material
  is the tool used, NOT the engine's derivation source.
- [TR verbatim] "bu ekosistemin çıktısı, bir engine olacak. ve sis ekosistemin
  kümülatif bilgisini kullanarak vizyonu gerçekleştirecek biricik bir mimari ile
  o bahsettiğin boşluğu doldurmanın ötesine geçecek bir engine yapacaksın."
  (phonemsg-01M4GDPY3A0Q938442WBGT8PB0, 16:30:16)
  [EN] "The ecosystem's output will be an engine ... a unique architecture going
  beyond gap-filling."

The following are AGENT PROPOSALS (authored by the Instinct side, relayed to the
owner; owner silence is NOT owner direction - both await explicit approval):

- Two-source frame (proposal, relayed 16:27:00 as phonemsg-01M4GDGYT2ZB6W89TSW11GYRKS,
  answering the owner's question phonemsg-01M4GDGFE4NRYGKMX1786CMKBW, 16:26:44):
  the library (canon, Noordzij, drawing methodology) defines WHAT is good - the
  quality criterion; the tracer shows how a working machine mechanized such
  decisions. Mechanism inspiration from tracer, criteria from library.
- Parallel working frame (proposal, relayed 16:26:17 as
  phonemsg-01M4GDFMRZNBWVEC297011DZT3): core rules extracted -> skeleton may
  start; the rest is validated ON the engine.

Consequences (owner-directive-grounded): the engine is built FROM SCRATCH.
FontLab's autotrace is mechanism inspiration only - we do NOT copy it.

## 2. Minimum rule set: what unlocks which module

Evidence basis and limits: each rule listed below carries byte-bound
provenance in EXTRACTION-MANIFEST.md (binary sha256
23b6af9060285c8505d0530e8be0942e728186bb2ded8840eb03fd1b5211f36d; VA + exact
bytes per claim; semantic detail in FL-TRACE-RE.md). Known limits: the full
extraction manifest's semantics are not fully proven - 13/13 extraction targets
parse-present, but full binary-semantic coverage is still held, and the 32MB
disassembly dump remains outside the proven scope. Treat every rule as
RE-evidenced at its own VA/byte pin, not as part of a complete binary proof.

| # | Extracted rule (FL evidence) | Engine module it unlocks |
|---|------------------------------|--------------------------|
| R1 | Extrema placement: FL places extrema; types 41-44 collapse to type 4 on output (placement-only semantics) | **Point Placer**: where points go before any fitting |
| R2 | Corner decision gates: T2 collinearity + T3 depth gate corner acceptance; PARAM_A 2.0 (polygon mode) = every vertex is a corner CANDIDATE, gates still decide | **Point Classifier**: corner vs smooth, per candidate |
| R3 | PARAM_B is a dual threshold: sagitta + curvature acceptance | **Fit Gate**: accept/reject a fitted segment |
| R4 | Handle construction: endpoint-tangent direction + least-squares lengths (Schneider); mnk2 = tangent intersection, NOT LS | **Handle Builder**: tangent-constrained handle placement |
| R5 | Contour decomposition (Tracer::getContour mechanics, 0x101b88b90) | **Segmenter**: input -> ordered contour candidates |

With R1-R5 the skeleton can place points, classify them, fit segments, attach
handles, and be measured against canon criteria. That is the minimum closed loop:
input -> candidate points -> classification -> fit -> gate -> measurable output.

## 3. What is deliberately NOT in the minimum set

Remaining RE targets refine or correct, and are validated on the running engine
instead of blocking it: espPoint, extrEdge, multyEdge, cornerCorrection,
betweenLines, the [impl+0x100] sin consumer. Each enters the engine only after
either (a) byte-bound RE provenance, or (b) an engine-side validation result
against the canon test set.

## 4. Parallel plan

- **Track A - skeleton build** (would start after approval, from scratch, code in English):
  modules in the R1-R5 order above; each module ships with its gate.
- **Track B - RE continuation** (unchanged M1.5a list): feeds Track A as
  refinements, never as blockers.
- **Track C - criteria formalization**: library/canon (incl. owner's scripts and
  examples) into machine-checkable quality criteria the skeleton is measured
  against; ComponentRules proposal (4 fields + optics breaking-points) is part
  of this track, still awaiting owner decision.

Synchronization rule: no rule enters the engine without either byte-bound
provenance or an engine-side validation result. Every engine rule carries three
fields: criterion-source (library/script), mechanism-source (RE VA+bytes or
engine validation), status (PROPOSED / VALIDATED).

## 5. Decision requested from the owner

1. Approve R1-R5 as the skeleton's minimum closed loop (§2).
2. Approve the parallel frame (§4): skeleton starts on R1-R5; remaining rules
   validated on the engine, not ahead of it.
3. Confirm the traceability discipline (§4 sync rule) as the repo-wide standard
   for how material/tracer evidence enters engine code.
