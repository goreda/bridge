# 0009: Script home and tests

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
Stable build.sh entry; tools/build libs move only after D2 characterization.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
Ubuntu syntax/runner/secret tests; report gate cannot strand update.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
