# 0003: State and injected clients

Status: 190f v3 direction; migration not complete.

## Context
The monolithic app and tooling need checked boundaries without update deadlocks.

## Decision
Pure State/Action/reducer; MainActor view model; initializer clients.

## Consequences
Characterize, move-only, then behavior-neutral. Owner/native gates unchanged.

## Acceptance test
Test state, stale events and fake clients without AppKit.

## Revisit when
The architect amends the block or an evidenced constraint needs a new ADR.
