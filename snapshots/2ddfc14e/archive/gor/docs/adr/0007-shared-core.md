# 0007: Shared core and facade

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
GorCore and GorAV products share one exact gorav revision; no copied types.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
No gorav->gor edge; GorAVBackend only facade importer; Q2 gates extraction.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
