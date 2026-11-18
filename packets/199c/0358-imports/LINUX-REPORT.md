# Independent Swift6.0.3 validation

All invocations in this packet were executed independently on Linux. No existing receipt objects were used as acceptance. Exact argv, compile output and runtime output are in per-call logs; reproduction scripts included. Current host input manifest c5f851ab verified. Host source-only patches applied once, returned full tests from evidence materialized; alternative test patches not stacked.

## A14

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 |  |
| baseline | -O | 0 | 0 | 1 |  |
| fixed | -Onone | 0 | 0 | 0 |  |
| fixed | -O | 0 | 0 | 0 |  |
| mutant | -Onone | 0 | 0 | 1 |  |
| mutant | -O | 0 | 0 | 1 |  |

## A15

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 |  |
| baseline | -O | 0 | 0 | 1 |  |
| fixed | -Onone | 0 | 0 | 0 |  |
| fixed | -O | 0 | 0 | 0 |  |
| mutant | -Onone | 0 | 0 | 1 |  |
| mutant | -O | 0 | 0 | 1 |  |

## A18

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 |  |
| baseline | -O | 0 | 0 | 1 |  |
| fixed | -Onone | 0 | 0 | 0 |  |
| fixed | -O | 0 | 0 | 0 |  |
| mutant | -Onone | 0 | 0 | 1 |  |
| mutant | -O | 0 | 0 | 1 |  |

## A19

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 |  |
| baseline | -O | 0 | 0 | 1 |  |
| fixed | -Onone | 0 | 0 | 0 |  |
| fixed | -O | 0 | 0 | 0 |  |
| mutant | -Onone | 0 | 0 | 1 |  |
| mutant | -O | 0 | 0 | 1 |  |

## A20

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 |  |
| baseline | -O | 0 | 0 | 1 |  |
| fixed | -Onone | 0 | 0 | 0 |  |
| fixed | -O | 0 | 0 | 0 |  |
| mutant | -Onone | 0 | 0 | 1 |  |
| mutant | -O | 0 | 0 | 1 |  |

## 198z01

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 | provider-regression_semantic_exit=1  |
| baseline | -O | 0 | 0 | 1 | provider-regression_semantic_exit=1  |
| fixed | -Onone | 0 | 0 | 0 | provider-regression_semantic_exit=0  |
| fixed | -O | 0 | 0 | 0 | provider-regression_semantic_exit=0  |
| mutant | -Onone | 0 | 0 | 1 | provider-regression_semantic_exit=1  |
| mutant | -O | 0 | 0 | 1 | provider-regression_semantic_exit=1  |

## 198z02

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 | legacy_semantic_exit=0  |
| baseline | -O | 0 | 0 | 1 | legacy_semantic_exit=0  |
| fixed | -Onone | 0 | 0 | 0 | legacy_semantic_exit=0  |
| fixed | -O | 0 | 0 | 0 | legacy_semantic_exit=0  |
| mutant | -Onone | 0 | 0 | 1 | legacy_semantic_exit=0  |
| mutant | -O | 0 | 0 | 1 | legacy_semantic_exit=0  |

## 198z03

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 1 | NOT_RUN | legacy_semantic_exit=1  |
| baseline | -O | 0 | 1 | NOT_RUN | legacy_semantic_exit=1  |
| fixed | -Onone | 0 | 0 | 0 | legacy_semantic_exit=1  |
| fixed | -O | 0 | 0 | 0 | legacy_semantic_exit=1  |
| mutant | -Onone | 0 | 0 | 1 | legacy_semantic_exit=1  |
| mutant | -O | 0 | 0 | 1 | legacy_semantic_exit=1  |

## B11

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 |  |
| baseline | -O | 0 | 0 | 1 |  |
| fixed | -Onone | 0 | 0 | 0 |  |
| fixed | -O | 0 | 0 | 0 |  |
| mutant | -Onone | 0 | 0 | 1 |  |
| mutant | -O | 0 | 0 | 1 |  |

## B12

| Condition | Optimization | Production compile | Returned test compile | Semantic exit | Other regression |
|---|---|---:|---:|---:|---|
| baseline | -Onone | 0 | 0 | 1 |  |
| baseline | -O | 0 | 0 | 1 |  |
| fixed | -Onone | 0 | 0 | 0 |  |
| fixed | -O | 0 | 0 | 0 |  |
| mutant | -Onone | 0 | 0 | 1 |  |
| mutant | -O | 0 | 0 | 1 |  |

## Scope and findings beyond lab execution

- Host A rows each have explicit -Onone and -O baseline RED, fixed GREEN, production-regression mutant RED. All30 compiles succeed. Mutants:14 overflow midpoint restored;15 unrepresentable metric accepted;18 endpoint guard bypass;19 target guard bypass;20 equal-clock rejection regression.
- A20 trace is newly authored and deterministic, not the missing lab trace.800 finite samples (400 per box/radian mode) with equal timestamps; output bitPatterns, band bitPatterns and reflected private state identical baseline/fix in both optimizations. SHA256 de44f759d3e9a9e4554eefba1c20b0024b6f745ed1a358cee348eeb6f8073c93. This is an executed preservation sample, not all finite extremes.
-198z01 actual full15-source adapter compiled per condition/mode against actual prebuilt Core/NativeProbe/Playback/Subtitles/CAtomics dependencies and real locked FFmpeg7.1 static libraries. No fake CFFmpeg or transport used. Returned vectors and prior provider-linked regression pass fixed; both catch baseline and mutant. Dependencies were existing debug production builds, not rebuilt optimized. Owned adapter was explicitly compiled each mode. This is provider-linked module evidence, not a fresh whole-package acceptance.
-198z02/03 compile all12 actual subtitle sources each condition/mode. Returned outputs repeat identically across2 processes.02 format-framing mutant fails.03 context-bypass mutant fails.
-198z03 original content-only stale replacement regression stays RED before AND after (2 failures each mode). New API not host-wired; selectionReceipt remains OPEN. Baseline module compiles, but new-API returned test fails compile because new API is absent; original regression supplies baseline semantic RED. Do not flatten baseline compile distinction.
- B11/B12 actual production diffs parse/apply cleanly on exact cf3 baseline sources; no receipt-object substitution. Both independently tested baseline/fixed/mutant in both modes. B11 extended baseline has9 failures vs lab starter5; B12 baseline5. B11 finite-anchor guard mutant and B12 finite-bounds mutant fail.
- Initial provider attempt to make a shared library failed because locked FFmpeg static libraries are not PIC; final method emits actual module/object then links a real executable. This is a link-layout correction, not a fake-provider fallback.
- Full host/native/UI/renderer acceptance NOT_RUN. No refs changed.
