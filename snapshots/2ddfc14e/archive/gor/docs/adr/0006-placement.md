# 0006: One placement rule

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
Swift/scripts ceiling800; non-seam files >=80 or allowed-small reason.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
New violation or baseline increase fails CI;150 is guidance only.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
