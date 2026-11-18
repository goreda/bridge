# W-gdb-199h-d5r3b-08 - Seek session-change guard (r3: regression scope)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h D4b (r3b, pinned to native50 872dcc32d). Lane c: the existing early guard (sessionChangedDuringTargetLookup with epoch/identity/binding/cancellation revalidation, excerpt below) is regression scope. Cover each clause firing plus the pass-through case.

Re-pin note: r3b moves the pin 35f553acd -> 872dcc32d; all excerpt bytes are identical to r3 at the recorded ranges (the only shift is +3 lines before the sess_replace excerpt, now carved at 1660-1720).

Required acceptance: Executed regression: each guard clause produces the typed refusal; unchanged session passes.

Outcomes: a production change with executed semantic tests, or 'verified-not-needed with evidence' where this packet says so. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs, or the evidence document. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-d5r3b-08",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
 "touched_files": [
  {
   "path": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
   "excerpt_block": "sess_seek_guard (lines 1028-1042)"
  }
 ],
 "interface": {
  "signatures": "Lane c: the existing early guard (sessionChangedDuringTargetLookup with epoch/identity/binding/cancellation revalidation, excerpt below) is regression scope. Cover each clause firing plus the pass-thr",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Executed regression: each guard clause produces the typed refusal; unchanged session passes.",
  "callee": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-08.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires: Executed regression: each guard clause produces the typed refusal; unchanged session passes.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-d5r3b-08",
  "paths": [
   "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
   "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-08.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-08.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T11:50:59.733990+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
    "lines": "1028-1042",
    "block": "Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift:1028-1042",
    "sha256": "a5dea75bca015feaee07855868c78d36a65ea3cd285bef2b2abf766f2babcd89"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-08.py",
    "block": "fixtures1",
    "sha256": "1417d1214b5aaf30cd0db8a9170bd4b754c4a7cba6cf04af1f781f0ced911cc5"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "66326998f658fa0196df01354d91875f697b7fcb8c3108db96aa831c0ed71986",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-08; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "e80d05666978f5a7548c6cd5c26cb7a217ad5698bd11d7ab11d95cd1070edf05"
 }
}
```

```swift id=Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift:1028-1042
        // before any producer stop, ring reset or provider mutation.
        guard !tornDown, !fenced, !preparedOperation, preparedShot == nil,
              plane.seekAllowed, self.session?.epoch == issued.epoch,
              self.decoder === decoder, self.adec === adec,
              self.audioBinding == binding, !commit.isCancelled,
              let liveVideoBinding = decoder.currentBinding(),
              liveVideoBinding.token == videoBinding.token,
              liveVideoBinding.revision == videoBinding.revision else {
            throw EmbeddedRefusal.seekUnavailable("sessionChangedDuringTargetLookup")
        }
        wasPausedAtSeek = plane.state == .paused
        traceSeek("seekBegin")
        clearSubtitleGeneration()
        applyOrReport(.beginSeek)
        seekCounter &+= 1
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift", 1028, 1042, "a5dea75bca015feaee07855868c78d36a65ea3cd285bef2b2abf766f2babcd89"]]
bad = []
for rel, a, b, want in CHECKS:
    lines = (ROOT / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-08; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-08; baseline only, product change and semantic test still required
```
