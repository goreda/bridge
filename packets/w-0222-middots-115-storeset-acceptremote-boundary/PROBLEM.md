# W-0222 middots 115 storeSet/acceptRemote boundary
state: candidate
solver lab: 1nstinct
reviewer lab: in2tinct (writes failure cases first, blind to the fix)
id: W-0222 (one id for the whole life of this problem; every round updates this id)

## problem (what fails for the user)
the persistence boundary is split in two classes that share one localStorage namespace, and the class of each key exists only as a call-site choice, declared nowhere. sync-scoped state goes through the gated path (readScopedState under scopeForToken, mergeStates, writeScopedWithCustody with a durability gate, and only then acceptRemote advances the known revision). other writes go through plain storeSet (draft.js:27), which swallows storage failures silently - its own L0 comment says so. for the user this means: on storage pressure some of their state can be dropped with no note and no retry, and there is no test that stops a future state-bearing key from being added through the unscoped, ungated path - such a key would sit outside the merge, outside the per-account scope guard, and outside the durability gate that acceptRemote relies on.

## reproducer
- repo: goreda/middots @ 6b337ef893c1 (release 20261027-f7-held-keys-r1, the live bytes; app.js sha256 721ea1b5... matches the served prefix build).
- real source: source/sync.js (full module, sha256 50012f6d...), source/draft-storeget-storeset.excerpt.js (draft.js:14-34, full-file pin befec0e0...), source/draft-storesetchecked.excerpt.js (draft.js:1806-1820), source/app-applyremote.excerpt.js (app.js:2030-2140). pins are the first 8 of sha256.
- failing input class: storage write denial (quota/denied) and account switch. plain storeSet callers (e.g. app.js:327 wt-index-w, app.js:678 wt-invert) get no failure signal; the F7 selective-quota-blackbox style proves the gated path but no test enumerates which keys go through which path.
- real test command: node test/selective-quota-blackbox.mjs (existing F7 blackbox for the custody path); repo regressions under test/ run with node.

## expected behaviour
every persisted key has a declared class (sync-scoped state vs device-local) in one place; a test over the actual call sites enforces the declaration; a dropped write on a key declared durable-relevant surfaces a note to the user; nothing state-bearing reaches acceptRemote without the durable-custody gate; an unscoped write is never readable under another profile's scope.

## exact call site and interface
draft.js:27 storeSet / draft.js:20 storeGet (silent-failure primitives), draft.js:1808 storeSetChecked (reporting variant); sync.js acceptRemote(rev, state, reading) and pushMerged; app.js applyRemote merge + overlayRecovery + writeScopedWithCustody gate (app.js:286, 2111) ending in acceptRemote (app.js:2129); state-scope.js scopeForToken/cachedScope/readScopedState.

## behaviour that must not change
the F7 held-keys semantics (failed flush returns held before any state write; no STATE overwrite on custody-write failure; no push on held save); merge/overlay/admin-custody behavior; the revision-advance conditions inside acceptRemote; the 47 green consuming regressions stay green.

## acceptance test (from the product repo)
a blackbox test in the selective-quota-blackbox.mjs style that (a) enumerates storeSet/storeSetChecked/writeScopedWithCustody call sites and asserts each key's declared class, (b) proves a quota-denied write on a durable-relevant key surfaces a user note, (c) proves an unscoped write is not readable under another profile's scope, (d) proves acceptRemote does not advance when the preceding persist was not durable. all existing tests stay green. reviewer failure cases first (blind): storage full mid-session, account switch with residue, readback-mismatch, revoke-denied frames, concurrent tab write during applyRemote.

## roles and state
1nstinct solves: classification + enforcement test + minimal surfacing. in2tinct reviews: failure cases first without reading the fix (data loss, limits, rollback, recovery after error), then the review. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean
