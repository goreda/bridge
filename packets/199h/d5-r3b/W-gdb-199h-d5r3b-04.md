# W-gdb-199h-d5r3b-04 - Render retention window (r3: regression coverage)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h D2e (r3b, pinned to native50 872dcc32d). Lane c: the nil-playhead guard and the current-window revalidation already exist in collectRetired (excerpt below), so this packet is regression coverage unless a new witness shows a live defect. Cover: unknown playhead retires nothing; window revalidation immediately before unlink; reentry during an in-flight sweep.

Re-pin note: r3b moves the pin 35f553acd -> 872dcc32d; all excerpt bytes are identical to r3 at the recorded ranges (the only shift is +3 lines before the sess_replace excerpt, now carved at 1660-1720).

Required acceptance: Executed regression tests for the three guards, or a new-witness defect report with reproduction.

Outcomes: a production change with executed semantic tests, or 'verified-not-needed with evidence' where this packet says so. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs, or the evidence document. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-d5r3b-04",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
 "touched_files": [
  {
   "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
   "excerpt_block": "coord_retired (lines 7188-7207)"
  }
 ],
 "interface": {
  "signatures": "Lane c: the nil-playhead guard and the current-window revalidation already exist in collectRetired (excerpt below), so this packet is regression coverage unless a new witness shows a live defect. Cove",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Executed regression tests for the three guards, or a new-witness defect report with reproduction.",
  "callee": "archive/gor/Sources/gor/gor/ThreeD.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-04.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires: Executed regression tests for the three guards, or a new-witness defect report with reproduction.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-d5r3b-04",
  "paths": [
   "archive/gor/Sources/gor/gor/ThreeD.swift",
   "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-04.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-04.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T11:50:59.630033+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
    "lines": "7188-7207",
    "block": "Sources/gor/gor/ThreeD.swift:7188-7207",
    "sha256": "56a24b55784ab894579943a814444897a0584301bb72a9f959c492c88572018f"
   },
   {
    "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
    "lines": "3361-3411",
    "block": "Sources/gor/gor/ThreeD.swift:3361-3411",
    "sha256": "5051113d8774c8118a765d8c39680262a45ac32b5d420ff4b31d1dd7064dddef"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-04.py",
    "block": "fixtures1",
    "sha256": "9ad62e916e498eeea6a9693411cb2de75d3ceac5d5b88a2ab9ef4489ce5d3c67"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "abcee0eff15171fe78e6981e79de7db4406616af21cb559c746904069335bf12",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-04; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "02a80a7b6fa85a9df35551cf685abba7e562fc5392a03272343486dcdb8315dd"
 }
}
```

```swift id=Sources/gor/gor/ThreeD.swift:7188-7207
    private func collectRetired() {
        // An old gorav prepared swap owns its files until its actual result and
        // stale-result restoration have both returned (D3).
        guard !preparedLoadPending,let entry=cachePin?.entry,DepthCacheBudget.owned(entry) else {return}
        let retained=Set(lastGood.values.map { $0.url }).union(mpvRetainedURLs)
        for url in retired where url != showingURL && !retained.contains(url) {
            guard url.deletingLastPathComponent()==entry,DepthCacheBudget.plainFile(url),
                  let shot=RenderShotRetention.shot(in:url.lastPathComponent),busy[shot]==nil else {continue}
            // Retirement is a queued intention, not permission to ignore a
            // later playhead. Revalidate its window immediately before unlink.
            guard let playhead=retentionPlayhead,
                  !RenderShotRetention.inWindow(shot:shot,playhead:playhead) else {continue}
            do {try FileManager.default.removeItem(at:url)} catch {continue}
            let side=url.deletingPathExtension().appendingPathExtension("json")
            if DepthCacheBudget.plainFile(side) {try? FileManager.default.removeItem(at:side)}
            retired.remove(url)
        }
    }

    /// A depth re-prepare may temporarily remove coverage metadata. The old
```

```swift id=Sources/gor/gor/ThreeD.swift:3361-3411
        fileprivate func retentionLock(exclusive:Bool)throws->Int32 {
            let fd=try lockFile("-retain")
            guard flock(fd,(exclusive ? LOCK_EX:LOCK_SH)|LOCK_NB)==0 else {close(fd);throw Failure.busy}
            return fd
        }
        fileprivate func budgeted(_ count:UInt64,_ body:()throws->Void)throws {
            try DepthCacheBudget.withLock(root) {
                try anchored();try DepthCacheIO.checkLocked(root:root,bytes:count);try body()
            }
        }
        fileprivate func readRecord(_ name:String)throws->Record {
            let fd=openat(dir,name,O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_NOFOLLOW);guard fd>=0 else {throw Failure.missing}
            defer {close(fd)}
            let before=try regular(fd);guard before.st_size>0,before.st_size<=recordLimit else {throw Failure.invalid}
            let data=try readChunk(fd,recordLimit+1)
            guard data.count==before.st_size,same(before,try regular(fd)) else {throw Failure.changed}
            guard let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],let nested=object["map"],try JSONSerialization.data(withJSONObject:nested).count<=4096 else {throw Failure.invalid}
            let record=try JSONDecoder().decode(Record.self,from:data)
            guard record.identity.commitName==name,record.identity.sourceKey==key else {throw Failure.invalid}
            return record
        }
        func begin(identity:Identity,map:ShotTimelineMap)throws->Writer {
            guard identity.sourceKey==key else {throw Failure.invalid}
            return try publication {try Writer(lease:self,identity:identity,map:map)}
        }
        func verify(identity:Identity,expectedMap:ShotTimelineMap)throws->Verified {
            guard identity.sourceKey==key else {throw Failure.invalid}
            return try publication {
                let record=try readRecord(identity.commitName)
                guard record.identity==identity,record.map==expectedMap else {throw Failure.invalid}
                let pin=try retentionLock(exclusive:false)
                do {
                    let fd=openat(dir,record.mediaName,O_RDONLY|O_NONBLOCK|O_CLOEXEC|O_NOFOLLOW);guard fd>=0 else {throw Failure.missing}
                    do {
                        let (bytes,sha)=try digest(fd)
                        guard bytes==record.mediaBytes,sha==record.mediaSHA256 else {throw Failure.invalid}
                        return Verified(lease:self,record:record,fd:fd,pin:pin)
                    } catch {close(fd);throw error}
                } catch {close(pin);throw error}
            }
        }
        /// Unknown/invalid committed metadata aborts cleanup. Only unreferenced,
        /// recognized generation files retire only with an exclusive entry-wide retain pin.
        @discardableResult func reapOrphans()throws->[String] {
            try publication {
                let retention:Int32
                do {retention=try retentionLock(exclusive:true)} catch Failure.busy {return []}
                defer {close(retention)}
                let names=try FileManager.default.contentsOfDirectory(atPath:entry.path)
                var retained=Set<String>()
                for name in names where recognized(name) && name.hasSuffix(".local-v2.json") {
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Sources/gor/gor/ThreeD.swift", 7188, 7207, "56a24b55784ab894579943a814444897a0584301bb72a9f959c492c88572018f"], ["Sources/gor/gor/ThreeD.swift", 3361, 3411, "5051113d8774c8118a765d8c39680262a45ac32b5d420ff4b31d1dd7064dddef"]]
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
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-04; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-04; baseline only, product change and semantic test still required
```
