# G-M6 session-guard state machine (generic, ohal middots line)
Pure guard-decision state machine + tests, <2h. Models WHICH local data classes survive WHICH events; no product code.

## Interface
```js
guardStep(state, event)
// state: { presetsProtected: bool, unsyncedWriting: bool, draftsLocal: bool, scope: 'A'|'anon' }
// event: { kind: 'syncError'|'authInvalid401'|'explicitDeviceClear'|'remoteProfileWipe'|'ordinarySignOut' }
// -> { action: 'preserveAll'|'holdForReview', wiped: string[], preserved: string[] }
// invariants (the contract under test):
//  I1 syncError/authInvalid401/ordinarySignOut NEVER wipe anything (action preserveAll).
//  I2 explicitDeviceClear may wipe drafts/device-local cache but NEVER presetsProtected or unsyncedWriting.
//  I3 remoteProfileWipe targets server data; locally it behaves as ordinarySignOut (I1) and returns holdForReview.
//  I4 scope transitions never copy one scope's preserved classes into another scope's state.
```
## Synthetic fixture
fixtures/events.json: sequences of 1-5 events over initial states with/without each protected class; expected action/wiped/preserved per step.
## Must-pass tests
1-6. I1 for each non-clear event kind. 7. I2 explicit clear: wiped contains only allowed classes, preserved contains presetsProtected+unsyncedWriting when present. 8. I3 hold. 9-10. I4 cross-scope sequences. 11. Property: for 200 random event sequences, wiped never intersects protected classes.
Run: `node test/gm6-session-guard.test.mjs`.
## Bounds
Pure decision model; no DOM, no storage, no real auth; proves the model honors the invariants, not that any app calls it.
## Target
Integrator ports into the middots line branch (assigned on return).
