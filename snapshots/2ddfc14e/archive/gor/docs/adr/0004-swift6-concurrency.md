# 0004: Per-target Swift6 and real-time contract

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
Swift6 complete checking per migrated target; actors at facades only.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
RT callbacks have no blocking/allocation/actor hops; ownership notes/tests.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
