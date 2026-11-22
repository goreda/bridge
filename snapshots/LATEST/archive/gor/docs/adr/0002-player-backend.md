# 0002: PlayerBackend seam

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
New playback work uses PlayerBackend after e1; route stays mpv until p-switch.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
Unsupported commands refuse explicitly; no parallel backend path.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
