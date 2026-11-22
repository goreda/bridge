# 0005: GorKit Linux tests

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
Build/test separate Packages/GorKit, never filter a mac executable package.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
Each migrated pure target has discovered tests; zero targets is SKIP.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
