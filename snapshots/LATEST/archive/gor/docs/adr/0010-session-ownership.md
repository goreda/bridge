# 0010: Session presenter and timebase ownership

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
gorav owns clock/generation/seek/pipeline; adapter lifetime/admission; gor UI.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
No presenter-internal host access; facade actor + MainActor attach; Q2 prototype.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
