# 0001: Two-package architecture

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
Separate Linux GorKit from macOS app; GorCore is supplied by gorav.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
A2 edges compile in separate packages; Q2/Q3 gate M2.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
