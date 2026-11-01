# v7 NO-UPSCALE CLARIFICATION - 2026-11-01

Status: clarification of the existing contract, grounded in this packet's original PROBLEM.md - not new policy, no change to v7's domain or arithmetic. Approved for publication (Ops routing, 2026-11-01 05:40 +03).

## The cap stands

PROBLEM.md (this packet) defines the contain-fit rule verbatim:

    - scale = min(1, aw / vw, ah / vh)   (never scale UP beyond natural size)
    - w = floor(vw * scale); h = floor(vh * scale)   (integer arithmetic, round DOWN on both axes)

SPEC-ADDENDUM-FIT-DOMAIN-v7.md specifies the valid domain, the typed .unrepresentable refusal, and the exact Int64 contract, but never restates the cap at 1. That omission is not a revocation:

1. Content smaller than the window on both axes is drawn at natural size (scale = 1 exactly, centered per the original rule). An implementation that scales small content UP is a failure - PROBLEM.md's reviewer protocol names "scale small content up" as an explicit blind failure case.
2. Effective rule: scale = min(1, aw/vw, ah/vh), evaluated under the v7 contract: integer/rational arithmetic, no materialized scale factor, floor on both axes, and a non-representable downscale stays a TYPED refusal (.unrepresentable), never a clamp.
3. v7's own "min-1 fallback floor" discussion is a different mechanism (clamping a sub-1pt fitted side up to 1pt, which distorts aspect) and is unaffected: it remains typed-refused unless a caller selects a declared policy with an explicit receipt.

Nothing else in v7 changes. Freeze v1 (G0537) is served by v7 plus this clarification.
