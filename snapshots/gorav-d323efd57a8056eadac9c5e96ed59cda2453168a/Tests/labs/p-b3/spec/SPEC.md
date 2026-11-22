# P-B3 SPEC: HDR10 PQ/BT.2020 to SDR BT.709 tone mapping

Packet: P-B3 (E3/E4, lab-b). Clean-room public contract. This document defines
the exact transfer functions, matrix, tone curve, and output encoding BEFORE
the shader; the Swift scalar reference, the Metal shader, and the fixtures all
implement exactly this pipeline. No monitor HDR validation is claimed anywhere
in this packet; reference images are generated numeric artifacts.

## 1. Input and output contract

```swift
public struct RGB: Equatable, Sendable { public let r: Double; public let g: Double; public let b: Double }
public protocol HDRReference {
    func map(pq2020: RGB, sourcePeakNits: Double, targetPeakNits: Double) throws -> RGB
}
```

- Input `pq2020`: ST 2084 (PQ) encoded RGB, each channel in [0, 1], BT.2020
  primaries (HDR10 signal). Components must be finite and in [0, 1].
- `sourcePeakNits`, `targetPeakNits`: finite, > 0.
- Output: BT.709-6 OETF encoded RGB, each channel in [0, 1], for a display
  with peak `targetPeakNits`.
- Errors: `nonFiniteInput`, `inputOutOfRange`, `invalidPeak` (named throws, no
  silent clamping of out-of-contract inputs).
- Metal equivalent: `toneMapPQ2020toBT709(float3 pq2020, float sourcePeakNits,
  float targetPeakNits) -> float3` in `Shaders/tone_map.metal`, same inputs
  and output encoding in single precision.

## 2. Pipeline (per pixel, order fixed)

1. **ST 2084 decode.** Each encoded channel N in [0,1] to absolute luminance
   L (nits), BT.2020 linear RGB:
   `L = 10000 * ( max(N^(1/m2) - c1, 0) / (c2 - c3 * N^(1/m2)) )^(1/m1)`
2. **Luminance.** `Y = 0.2627*Lr + 0.6780*Lg + 0.0593*Lb` (BT.2020 luma
   coefficients; sum is exactly 1.0, so neutral inputs give Y = channel value).
3. **Normalize to source peak.** `yn = Y / sourcePeakNits`.
4. **Tone curve.** Reinhard (2002) global photographic operator:
   `yt = yn / (1 + yn)`. Properties relied on by the asserts: yt(0) = 0
   (black maps black), strictly monotonic, bounded by 1. This is a published,
   labelled curve (section 6), not an unlabelled artistic choice.
5. **Rescale to target peak and preserve chroma proportionally.**
   `Lt = yt * targetPeakNits`; `s = Y > 0 ? Lt / Y : 0`; `Lm = L * s`.
   Scaling all three channels by one scalar keeps neutral inputs neutral.
6. **Gamut matrix.** BT.2020 linear to BT.709 linear:
   `C709 = M_2020_TO_709 * Lm` (matrix derivation in section 4).
7. **Normalize and clip.** `v = clamp(C709 / targetPeakNits, 0, 1)`. Hard
   clipping of out-of-gamut components is the documented behaviour of the
   ITU-R BT.2407-0 "simple conversion" (section 2 of that report).
8. **BT.709-6 OETF encode.**
   `out = 4.5*v` for `v < 0.018`, else `1.099 * v^0.45 - 0.099`.

## 3. Published constants used

ST 2084 / ITU-R BT.2100-2 Table 4:
- m1 = 2610/16384 = 0.1593017578125
- m2 = 2523/4096 * 128 = 78.84375
- c1 = 3424/4096 = 0.8359375
- c2 = 2413/4096 * 32 = 18.8515625
- c3 = 2392/4096 * 32 = 18.6875
- reference peak: 10000 nits

BT.2020 primaries (ITU-R BT.2020-2): R(0.708, 0.292) G(0.170, 0.797)
B(0.131, 0.046), white D65 (0.3127, 0.3290).
BT.709 primaries (ITU-R BT.709-6): R(0.640, 0.330) G(0.300, 0.600)
B(0.150, 0.060), white D65 (0.3127, 0.3290).
BT.2020 luma coefficients (ITU-R BT.2100-2): 0.2627, 0.6780, 0.0593.
BT.709 OETF (ITU-R BT.709-6): threshold 0.018, slope 4.5, power 0.45,
offset pair 1.099/0.099.

## 4. Matrix derivation (not a guessed matrix)

The packet asks for published primaries, and the 1e-6 neutrality assert
requires better than the 4-decimal published matrix (its row sums deviate by
1e-4). The matrix is therefore DERIVED at full double precision from the
published primaries above, using the standard construction:

- For each system: columns `Pi = (xi/yi, 1, (1-xi-yi)/yi)`; solve
  `P * s = W` for the white point W = (xw/yw, 1, (1-xw-yw)/yw); the RGB->XYZ
  matrix is `P * diag(s)`.
- `M_2020_TO_709 = inverse(RGB709->XYZ) * (RGB2020->XYZ)`.

Resulting constants (17 significant digits, identical in Swift, Metal, and
the Python generator):

```
 1.6604910021084338  -0.58764113878854973  -0.072849863319884856
-0.12455047452159063   1.1328998971259601  -0.0083494226043694872
-0.018150763354905213 -0.10057889800800743   1.1187296613629127
```

Cross-check: these agree with the published 4-decimal BT.2020 -> BT.709
matrix in ITU-R BT.2407-0 section 2.2 (1.6605, -0.5876, -0.0728 / -0.1246,
1.1329, -0.0083 / -0.0182, -0.1006, 1.1187). Row sums are 1 within 1e-15, so
neutral inputs map to neutral outputs within the required 1e-6. The
derivation code is `tools/generate_fixtures.py` (functions
`prim_to_rgb2xyz`, `inv3`, `matmul`) and prints the matrix and row sums on
every fixture run.

## 5. Fixtures (all generated, no external/licensed images)

Generator: `tools/generate_fixtures.py` (Python 3.10 stdlib only,
deterministic IEEE-754 double math, no clock/RNG/network). Run:
`python3 tools/generate_fixtures.py` — it regenerates the fixtures AND runs
the numeric asserts (exit 0 = pass), printing hashes.

- `fixtures/pq-gray-ramp.csv` — neutral ramp at 0, 0.1, 1, 10, 100, 400,
  1000 nits via inverse PQ; columns input_nits, pq_code, out_r, out_g, out_b
  (source peak 1000, target peak 100). Floats as %.17g.
- `fixtures/hdr-primary-patches.csv` — BT.2020 red/green/blue/white patches,
  linear (1000,0,0) etc. nits per channel PQ-encoded; columns patch,
  in_*_nits, pq_*, out_*; peak 1000, target 100.
- `fixtures/gray-ramp-reference.ppm` — 448x64 P6 PPM, seven 64x64 cells,
  8-bit = round(clamp(out)*255) of the oracle.
- `fixtures/color-patches-reference.ppm` — 256x64 P6 PPM, four 64x64 cells.
- Reference images are generated artifacts, not visual-validation proof.

## 6. Source URLs

- ST 2084 PQ constants: ITU-R BT.2100-2,
  https://www.itu.int/rec/R-REC-BT.2100-2-201807-I/en (Table 4); corroborated
  at https://kernel.org/doc/html/v4.10/media/uapi/v4l/pixfmt-008.html
- BT.2020 primaries: https://www.itu.int/rec/R-REC-BT.2020-2-201510-I/en
- BT.709 primaries and OETF: https://www.itu.int/rec/R-REC-BT.709-6-201506-I/en
- Matrix method and published 4-decimal cross-check:
  ITU-R BT.2407-0 section 2.2,
  https://www.itu.int/dms_pub/itu-r/opb/rep/R-REP-BT.2407-2017-PDF-E.pdf ;
  companion: ITU-R BT.2087-0,
  https://www.itu.int/rec/R-REC-BT.2087-0-201510-I/en
- Tone curve: E. Reinhard, M. Stark, P. Shirley, J. Ferwerda, "Photographic
  Tone Reproduction for Digital Images", ACM SIGGRAPH 2002,
  DOI 10.1145/566654.566575 (simple global operator L/(1+L)).

## 7. Known limits (stated, not hidden)

- Hard clipping of out-of-gamut BT.2020 colours (e.g. pure primaries) is the
  documented BT.2407-0 simple-conversion behaviour, not gamut mapping.
- Simple Reinhard maps source peak to half the target peak; the pipeline is
  specified for correctness/determinism, not picture-quality tuning.
- The Metal shader is float precision; parity tolerance vs the Double CPU
  reference is 1e-4 max absolute channel error.
