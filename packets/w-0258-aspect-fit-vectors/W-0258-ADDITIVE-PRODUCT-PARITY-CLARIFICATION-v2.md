# W-0258 - additive product-parity clarification (v2) - 2026-11-01

ADDITIVE clarification against the PINNED product source:
GorVideoFit.swift sha256 213cc50476b7a181000fec4b8028b6c1b9602854d7e4ce54990ae2fb54bfa78a (16848 B).
Companion fixture table: W-0258-PRODUCT-PARITY-FIXTURES-v2.md.
v2 supersedes v1 (3ad55167...90c1): precision fix - the raw-origin exception
applies ONLY to the wrapper-level degenerate guard; positive sub-1 pt sizes
floor to zero in conversion and return the FLOORED origin (see Q2 below).

## Status and bounds
- Docs/fixtures ONLY. No product code change, no live/deploy change, no repo
  write, no publication by this artifact.
- AUTHORED by static derivation from the pinned source bytes. NOT executed:
  the original review harness and review bundle remain unrecovered, and this
  artifact claims no runtime re-execution. Any future runtime claim requires
  actual new evidence.
- The historical lab freeze (6098 B, sha256
  18206bb5edb18782aa26f4ad213ddf8bdda906bd7281657782df2b612b768ea8) is NOT
  rewritten. Its P12 case (negative dimension -> typed refusal) conflicts
  with product behavior; the conflict is recorded and kept visible, not
  resolved by editing history. The historical reference's scoped approval
  stays bounded to the reference itself and does not prove product behavior.

## Q1 - fractional inputs and origins (settled by the pinned contract)
- Conversion policy: floating-point call sites FLOOR EACH of the six inputs
  (video w/h, avail w/h, AND origins avail.x/avail.y) before the integer
  rule runs (source lines 161-163: Int64(x.rounded(.down))). This is an
  explicit floor, not Swift Int truncation: floor(-0.7) = -1.
- The integer domain guards magnitudes only (lines 114-118, 157-160):
  0 < size <= Int32.max, |origin| <= Int32.max. Origins carry NO positivity
  requirement: negative origins are in-domain and pass through integer
  addition exactly; no division ever applies to an origin.
- Centering is integer division (lines 137-141): cx = ax + (aw - cw) / 2.
  (aw - cw) >= 0 holds by construction, so Int64 truncating division equals
  floor on every reachable value; the floor-vs-truncation gap is unreachable.
  Origins are exact integers by construction on the non-degenerate path.
  Worked odd-delta case: video 101x50 in avail (0,0,2048,1170) -> stays
  101x50 (no upscale), x = (2048-101)/2 = 973, y = (1170-50)/2 = 560.
- Named nuance (documented, not a defect): the legacy float pipeline could
  retain a .5 origin on odd deltas; integer centering can therefore move an
  origin by 0.5 pt versus legacy. Sizes are unaffected. This is inside the
  declared conversion policy (<1 pt) of the fit-domain addendum.

## Q2 - degenerate classification (one conjunction; TWO guard levels)
The pinned product contract classifies degenerate inputs with ONE
conjunction - zero, negative and NaN sizes are the SAME class; there is no
zero-first precedence, and mixed zero+negative takes the same path. But the
conjunction is enforced at TWO levels, and the returned origin differs:

1. WRAPPER guard (lines 153-156): any size non-positive or NaN AS PASSED
   -> .ok empty rect at the RAW avail origin (line 155 returns the original
   Double avail.x/avail.y, UNfloored). Example: video 0x100, avail origin
   (5.5, 7.25) -> (5.5, 7.25, 0, 0).
2. CORE guard (lines 111-113): a POSITIVE but sub-1 pt size passes the
   wrapper (0.4 > 0), floors to 0 in conversion (lines 161-163), and fails
   the core's vw > 0 -> .ok empty rect at the FLOORED avail origin.
   Example: video 0.4x100, avail origin (5.5, 7.25) -> (5, 7, 0, 0).

So "floor each input" applies to the NON-degenerate path and to the
core-guard degenerate path; only the wrapper-guard degenerate path preserves
the origin exactly as passed, including fractions. Documented here per the
reconciliation; NOT fixed unasked.

## Typed surface versus observable behavior
- containFit() typed results: .ok(rect) | .unrepresentable(axis, scaled)
  | .outOfIntegerDomain.
- fit() (lines 165-173) maps BOTH refusal types to the same zero rect at the
  avail origin (the standing no-legal-set convention), identical to the
  degenerate empty rect. So for the negative-dimension class the lab/product
  difference (typed refusal vs empty) is confined to the typed surface and
  fixtures; production-observable geometry is the same no-set either way.
- Payload semantics: .unrepresentable carries a Double approximating the
  true scaled size. Example: video 100000x1 in 2048x1170 -> scaled payload
  0.02048, the nearest Double to the exact rational 64/3125. The comparison
  is SEMANTIC (equal within one Double rounding), never byte-exact rational.
  .outOfIntegerDomain is payloadless.

## Freeze comparison (their labels, corrected excerpts)
- P10 (video 0x100, avail origin (5,7) -> (5,7,0,0)): MATCHES product.
- P11 (zero avail side, origin preserved): MATCHES product.
- P12 (video -3x100 -> typed outOfIntegerDomain): CONFLICTS. Product:
  empty rect at the raw avail origin (wrapper-guard conjunction above).
  Recorded as a reference-versus-product conflict; product code unchanged;
  no original owner requirement for a negative-dimension refusal exists.
- P13 (size 2147483648 -> typed refusal): MATCHES as a class; the product
  enum case is payloadless.
- NaN: a gap on the lab side, not a contradiction. Product: NaN sizes fail
  the wrapper's > 0 check -> empty at the RAW avail origin (level 1).

## Coordination
This artifact is returned for the lab's independent review flow before any
coordinated publication; documents must not race. No repo or public write
authority is added by this exchange.
