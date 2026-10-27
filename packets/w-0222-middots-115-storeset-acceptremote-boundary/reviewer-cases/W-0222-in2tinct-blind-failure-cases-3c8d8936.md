# W-0222 in2tinct blind failure cases (frozen before any source read)

Commit pinned: 0a3e9915cef8fbae8225cb41a319a825d631d878
Read before writing: the GROUP-INBOX.md notice line for W-0222 and PROBLEM.md only.
NOT read: sync.js, the three excerpts, manifest.json, tests, any fix, any 1nstinct design.
Blindness declaration: PROBLEM.md itself names these things, so they are not blind: storeSet swallows failures (draft.js:27), storeSetChecked exists, the gated path (scopeForToken, readScopedState, mergeStates, writeScopedWithCustody, acceptRemote), F7 held-keys, 47 regressions, selective-quota-blackbox.mjs, and the reviewer case list (storage full, account switch residue, readback mismatch, revoke-denied frames, concurrent tab write). Function behavior beyond what PROBLEM.md says is unknown to me.
Status: all cases below are UNEXECUTED. Nothing was run. No product acceptance claim.

## A. Hard requirements (from PROBLEM.md "expected behaviour" / "must not change")
H1 Every persisted key has a declared class (sync-scoped vs device-local) in one place.
H2 A test over actual call sites enforces the declaration.
H3 A dropped write on a durable-relevant key surfaces a user note.
H4 Nothing state-bearing reaches acceptRemote without the durable-custody gate.
H5 An unscoped write is never readable under another profile's scope.
H6 F7 held-keys: failed flush returns held before any state write; no STATE overwrite on custody-write failure; no push on held save.
H7 Merge/overlay/admin-custody behavior and acceptRemote revision-advance conditions unchanged.
H8 The 47 regressions stay green.
Acceptance (a)-(d) in PROBLEM.md map to H2, H3, H5, H4.

## B. Reviewer proposals (my authoring, not contract). Tolerances are mine and adjustable.

Oracle style for all: a synthetic in-memory localStorage stub with scripted failures (throw QuotaExceededError on Nth setItem, throw on key X only, silently drop write, return stale value on getItem). Lab-local synthetic data only.

F1 Storage full mid-session
 Setup: stub allows N writes then throws on all/selected keys. Run a save sequence that touches one sync-scoped key and one plain-storeSet key.
 Oracle: (i) plain key failure on a durable-relevant key produces exactly one user-visible note, not zero, not one per retry loop; (ii) sync-scoped failure returns held, STATE unchanged byte for byte, no push call, known revision unchanged; (iii) after quota is freed, the next flush succeeds and the held keys are written (recovery, no manual step).
 Data-loss check: diff of stored keys before/after equals the successful writes only; no partial/torn value under any key.
 Tolerance: note text free; count of notes = 1 per failed key per flush attempt.

F2 Selective denial (one key denied, others fine)
 Oracle: result reports which key failed; other keys not rolled back unless contract says so (unknown, ask); acceptRemote not advanced if the denied key is state-bearing.

F3 Account switch with residue
 Setup: profile A writes sync-scoped and plain keys; switch to profile B (new token) without clearing storage; B reads.
 Oracle: B reads none of A's sync-scoped values; for plain keys, B sees them only if declared device-local; any plain key that is state-bearing and readable by B is a failure (H5). Also switch back to A: A's state intact.
 Residue variants: A's write in flight when switch happens; A's key left under unscoped name; token revoked then re-issued same account.

F4 Readback mismatch
 Setup: setItem succeeds but getItem returns old value, truncated value, or different JSON (stub lies).
 Oracle: custody gate treats mismatch as not durable: held, no acceptRemote advance, no push. Plain storeSet has no readback today per PROBLEM.md; for durable-relevant keys expect either readback or a surfaced note (proposal). Check null vs missing vs empty string distinction.

F5 Revoke-denied frames
 Setup: remote frame arrives while the token is revoked or scope unresolved (cachedScope stale vs scopeForToken null).
 Oracle: frame is not merged into any scope, not persisted, revision not advanced, no note spam; once scope valid again a later frame applies normally.

F6 Concurrent tab write during applyRemote
 Setup: between the read (readScopedState) and the write (writeScopedWithCustody), a second tab writes the same key (stub fires a storage event or mutates the key via hook).
 Oracle: no lost update: final value equals merge of both writes or the apply aborts as held; acceptRemote advances only when the persisted value equals what was merged (readback), never on a value the other tab overwrote. Also test other tab writing a plain key and tab closing mid-apply.

F7 Ordering and crash
 Kill after custody write but before acceptRemote: on restart, state is durable and revision not advanced; re-apply is idempotent (same final bytes). Kill after acceptRemote cannot be possible without prior durable write.

F8 Classification enforcement test (H1/H2)
 Oracle: static scan of the real call sites (storeSet, storeSetChecked, writeScopedWithCustody) yields a key set; each key appears in the single declaration; adding a new undeclared key makes the test fail (mutation check: insert one call with a fresh key literal, expect red). Include dynamic keys (template strings, concatenation) - scan must fail closed or flag them, not skip silently. Include keys via aliases of storeSet.

F9 Regression guard (H6-H8)
 Run the 47 consuming regressions plus node test/selective-quota-blackbox.mjs before and after; the pass set must be identical. Not executable by me without repo access; owner/solver must report the run.

F10 Surfacing quality (H3)
 Oracle: note appears for durable-relevant key only; device-local keys (e.g. cosmetic) do not spam; note not lost if the UI is not mounted yet; no secret/key content in the note text.

## C. Executed vs not
Executed: none. Unexecuted: F1-F10. Items needing repo access (F8 scan, F9) are for solver/owner to run; I will not claim results for them.

## D. Open questions for later source review (not answered yet)
Q1 Are plain-storeSet keys wt-index-w, wt-invert (named in PROBLEM.md) state-bearing or device-local? Packet does not say.
Q2 Does the contract want rollback of already-written keys on partial failure?
