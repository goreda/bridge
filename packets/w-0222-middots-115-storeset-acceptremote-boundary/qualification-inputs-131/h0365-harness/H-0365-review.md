# W-0222 reviewer report (in2tinct), rounds 1-2 - BASELINE source, no solver fix

Not product acceptance. Characterization, not a pass/fail verdict on the product.

## Chronology
1. Failure cases frozen blind and published, sha256 bd0dfb093550491deba640571c6c459ddd93e70225fb7b8d753dfe7305833aef (https://files.instinct.com/czh5shihem5e-w-0222-blind-cases-frozen). Before that I read only PROBLEM.md and the W-0222 inbox notice.
2. Round 1, commit 0a3e9915cef8fbae8225cb41a319a825d631d878: read sync.js and 3 excerpts; ran exact sync.js in stubbed globals (round1-harness/).
3. Missing-source ask answered by commit e763c45fd11c4a246e00160cad91804d418868af (inbox 19:58 Istanbul). Round 2 below. selective-quota-blackbox.mjs does not exist at the pin (the name in PROBLEM.md was wrong); not a blocker.

## Source pins (sha256 of fetched bytes; raw URLs under https://raw.githubusercontent.com/goreda/bridge/<commit>/packets/w-0222-middots-115-storeset-acceptremote-boundary/)
sync.js 50012f6dae27015c... | app.js 721ea1b52989546c... | draft.js befec0e0de3564ac... | state-scope.js 1132f86679bdbe23... | state-merge.js 2e0dcb32e1c93888... | admin-profile-state.js 937338e2c6a1b081... Product anchor named by the packet: goreda/middots 6b337ef893c1 (release 20261027-f7-held-keys-r1). Full hashes in round2/run-log.txt.

## Round 1: sync.js acceptRemote under injected storage faults (round1-harness/, `node run.mjs`, exit 0)
Exact unmodified sync.js, Node 22, stubbed localStorage/window/fetch, 3 no-op stub modules for imports. One process per case. Synthetic faults only; T4 (silent drop with no throw) is a fault model, not observed browser behavior.
| case | fault | returns | REV | BASE |
| control | none | true | 7 | rev-7 state |
| T2 | REV setItem throws | true | 5 | rev-7 state (REV/BASE disagree) |
| T3 | BASE setItem throws | true | 7 | removed (by design, setBase fallback) |
| T4 | REV+BASE silently dropped | true | 5 | unchanged, no signal |
| T5 | getItem throws (negative control) | false | 5 | unchanged |
| T6 | replay same read | true | 7 | rev-7 state |
Fact: acceptRemote takes no durability input and returns true after swallowed write failures. That alone does not show a non-durable preceding scoped persist.

## Round 2: production app.js text under a vm with stubs
The 5 suites shipped in the packet (source/test) were run from the packet source/ directory: edit-epoch 4, held-keys 15, key-hold 4, merge 9, independent-f6 15 = 47 tests, 0 fail (round2/full-output.txt). They sum to the release record's 47, but I cannot confirm they are the same 47 as the full repo suite; this is "5 packet suites, 47 tests", not a full-repo run.
Their scaffolding slices the production applyRemote and writeScopedWithCustody text out of app.js and runs it in a vm with stubs (react refs, localStorage with scripted faults, acceptRemote as a recorder, applySaved, showNote). I reused that scaffolding verbatim in round2/in2tinct-w0222.test.mjs (sha256 18b7d86c690da7357b27d509a7947c759da001421d8db35cb93064f8e8c120e1), 7 tests, 7 pass. Characterizations:
- Control, healthy storage: accept called once, no note, envelope scope-a.
- writeScopedWithCustody: STATE_KEY setItem denied throws; readback mismatch returns durable:false; custody pending and unwritable returns held:true.
- Q1: STATE_KEY writes denied, no custody pending: applyRemote catches (persisted=false); adminCustodyDirty is false so no early return; the recorder stub shows acceptRemote(rev 42) called, merged state applied, no note, nothing stored. Q4: readback mismatch, same result.
- Negative control: custody pending and unwritable: early return, accept not called, note shown (the F7 gate works on that branch).
- Scope: real state-scope.js: another profile's envelope gives scope-mismatch; legacy payload under an account gives legacy-under-account. Executed for the STATE_KEY copy only, not for every key.
Reading against PROBLEM.md acceptance (d): under this VM fault model the call-site gate is not enforced for the non-dirty, non-durable case. This is not shown to be real end-to-end sync advancement or browser data loss: acceptRemote is a recorder here. Possible mitigation, unproved: the comment says page edits are kept, pushMerged follows, and IndexedDB recovery records exist; none was tested.

## Declaration (acceptance a)
In the packet files I searched (app.js, draft.js, sync.js, state-scope.js by text), I found no table or test declaring key classes; app.js has 2 storeSet writes (wt-index-w line 327, wt-invert line 678), both UI preferences that read as device-local. This is a bounded search of packet files, not a claim about the whole repo.

## Not done
No browser run, no full-repo run, no solver-fix comparison, no media. Authored proposals (note counts, concurrency, crash idempotence, UI) in the frozen cases file are not gates.

## Commands
Round 1: cd round1-harness && node run.mjs. Round 2: copy in2tinct-w0222.test.mjs into packet source/test/ at commit e763c45f and run `node test/<file>` from source/ (Node 22).
