# W-gdb-199h-wrr2-01 - Grain vendor binding (r2 re-pin)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h WR (r2, pinned to native49 b570c15ac). Bind the photon-grain.lua vendor script end to end: AppDelegate requiredLua membership and symlink refusal (excerpts below), PPController spine fold toggle routing script-message photon-grain-toggle to photon_grain (excerpt below), and the script's own baseline constants. r2 change: re-pinned to b570c15ac (file moved to gor/gor/PPController.swift; AppDelegate verification at new lines). Lane-c: applies in principle.

Required acceptance: Linux test: requiredLua membership + symlink refusal model + toggleTarget routing table match against the pinned excerpts.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-wrr2-01",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "b570c15ac927fe3b5fdaf831bd5167f8f45059aa",
 "touched_files": [
  {
   "path": "archive/gor/Sources/gor/AppDelegate.swift",
   "excerpt_block": "appd_requiredlua (lines 720-762)"
  },
  {
   "path": "archive/gor/Sources/gor/gor/PPController.swift",
   "excerpt_block": "appd_requiredlua (lines 720-762)"
  },
  {
   "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
   "excerpt_block": "appd_requiredlua (lines 720-762)"
  }
 ],
 "interface": {
  "signatures": "Bind the photon-grain.lua vendor script end to end: AppDelegate requiredLua membership and symlink refusal (excerpts below), PPController spine fold toggle routing script-message photon-grain-toggle t",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Linux test: requiredLua membership + symlink refusal model + toggleTarget routing table match against the pinned excerpts.",
  "callee": "archive/gor/Sources/gor/AppDelegate.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r2/W-gdb-199h-wrr2-01.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Linux test: requiredLua membership + symlink refusal model + toggleTarget routing table match against the pinned excerpts.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-wrr2-01",
  "paths": [
   "archive/gor/Sources/gor/AppDelegate.swift",
   "archive/gor/Sources/gor/gor/PPController.swift",
   "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
   "archive/gor/Tests/Architecture/199h-d5r2/W-gdb-199h-wrr2-01.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "b570c15ac927fe3b5fdaf831bd5167f8f45059aa",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r2/W-gdb-199h-wrr2-01.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T10:34:30.280976+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Sources/gor/AppDelegate.swift",
    "lines": "720-762",
    "block": "Sources/gor/AppDelegate.swift:720-762",
    "sha256": "a554755b2e2e8143e232272f7187b9527eb47c2499ad151f10ef21b1d53273fb"
   },
   {
    "path": "archive/gor/Sources/gor/gor/PPController.swift",
    "lines": "1962-1980",
    "block": "Sources/gor/gor/PPController.swift:1962-1980",
    "sha256": "7c905724327d8aa8802f2894914e890b0f0a3b3a824e8a39e30163ce87ae2e60"
   },
   {
    "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
    "lines": "89-96",
    "block": "Resources/vendor/mpv/scripts/photon-grain.lua:89-96",
    "sha256": "2d4db7380976f6ab23bf85ed789b15205f576b71650e641fbdaceed60fd7f492"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r2/W-gdb-199h-wrr2-01.py",
    "block": "fixtures1",
    "sha256": "579a57eb4161395dbe57f4aef0e9491c017da990f1941465dc6a4636f9eb7492"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "33b7741ea1c86a117e1c5f7df31a25d3b49f8ddfa97186c43dc909f239c5be4c",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr2-01; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "c15856cddeb34f5b6005dd933e1a36053afecf934ea5ddcd0ffa926e73ed87f7"
 }
}
```

```swift id=Sources/gor/AppDelegate.swift:720-762
    /// defaults into Application Support (fresh scripts per build), skipping
    /// the generated subtrees (shader/, cache/) that only exist locally.
    enum ScriptsSeedResult { case installed, failedOldIntact, failedBroken }
    static let requiredLua = ["photon.lua", "photon-common.lua", "photon-grain.lua", "photon-hud.lua", "autoload.lua"]
    static func seedLuaScripts(from srcIn: URL, into dst: URL, parent: URL) -> ScriptsSeedResult {
        let fm = FileManager.default
        let tmp = parent.appendingPathComponent(".seed-\(UUID().uuidString)-scripts")
        let backup = parent.appendingPathComponent(".old-\(UUID().uuidString)-scripts")
        func log(_ m: String) { NSLog("[gor] scripts seed: %@", m); Diag.mediaRecord("SEED " + m) }
        func fail(_ op: String, _ code: Int) -> Error {
            log("FAILED op=\(op) code=\(code)")
            return NSError(domain: "gor.mpv.seed", code: code)
        }
        func posix(_ op: String, _ e: Int32) -> Error {
            log("FAILED op=\(op) errno=\(e)")
            return NSError(domain: NSPOSIXErrorDomain, code: Int(e))
        }
        func info(_ u: URL) throws -> stat? {
            var st = stat()
            if lstat(u.path, &st) == 0 { return st }
            let e = errno
            if e == ENOENT { return nil }
            throw posix("lstat-\(u.lastPathComponent)", e)
        }
        // Includes every entry name, including links, without traversing links.
        // Used for rollback readback, where old non-Lua files must be preserved.
        func names(_ root: URL, strict: Bool = false, source: Bool = false) throws -> [String] {
            var failure: Error?
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil, options: [], errorHandler: { _, e in failure = e; return false }) else { throw fail("enumerate", 1) }
            var out: [String] = []
            for case let u as URL in en {
                guard let st = try info(u) else { throw fail("entry-disappeared", 2) }
                let kind = st.st_mode & S_IFMT
                let rel = String(u.path.dropFirst(root.path.count + 1))
                if kind == S_IFLNK {
                    en.skipDescendants()
                    if source {
                        if requiredLua.contains(rel) { throw fail("required-symlink-\(rel)", 3) }
                        log("SKIPPED symlink file=\(rel)"); continue
                    }
                    if strict { throw fail("verify-symlink-\(rel)", 4) }
                }
                if strict || source {
```

```swift id=Sources/gor/gor/PPController.swift:1962-1980
        spineUI.onFoldToggle = { [weak self] section in
            guard let self = self, !section.isEmpty else { return }

            let toggleTarget: [String: (script: String, msg: String)] = [
                "photon":  ("photon",         "photon-toggle"),
                "bright":  ("photon",         "photon-bright-toggle"),
                "sharp":   ("photon_sharp",   "photon-sharp-toggle"),
                "grain":   ("photon_grain",   "photon-grain-toggle"),
                "chrome":  ("photon_chrome",  "photon-chrome-toggle"),
                "negativ": ("photon_negativ", "photon-negativ-toggle")
            ]
            var batch = "{\"command\":[\"script-message-to\",\"photon_hud\",\"photon-hud-toggle-fold\",\"\(section)\"]}"
            if let t = toggleTarget[section] {
                batch += "\n{\"command\":[\"script-message-to\",\"\(t.script)\",\"\(t.msg)\"]}"
            }
            self.batchIPC(batch)
        }

        spineUI.onToggleLiveCaption = { [weak self] languageCode in
```

```lua id=Resources/vendor/mpv/scripts/photon-grain.lua:89-96
local GR_WINDOW_COMP_MAX = GR_WINDOW_COMP_MIN * 2

-- ── adaptive baseline ──
-- gr_amount = clamp(base_amount(scene) * gr_user_ratio, MIN, MAX)
local GRAIN_BASE_AMOUNT_MIN  =  0.55  -- was 0.25/2=0.125 — see gr_resolve_adaptive_params two-tier note: darkest-to-brightest ratio cut from 21.6x to ~2.4x, real film's exposure/push relationship, not a mechanism-revealing swing
local GRAIN_BASE_AMOUNT_MAX  =  1.00  -- was 1.35*2=2.7
local GRAIN_OFFSET_STEP      =  0.025 -- actual amount per press, including near zero
local GRAIN_OFFSET_MIN       = -1.00
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Sources/gor/AppDelegate.swift", 720, 762, "a554755b2e2e8143e232272f7187b9527eb47c2499ad151f10ef21b1d53273fb"], ["Sources/gor/gor/PPController.swift", 1962, 1980, "7c905724327d8aa8802f2894914e890b0f0a3b3a824e8a39e30163ce87ae2e60"], ["Resources/vendor/mpv/scripts/photon-grain.lua", 89, 96, "2d4db7380976f6ab23bf85ed789b15205f576b71650e641fbdaceed60fd7f492"]]
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
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr2-01; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr2-01; baseline only, product change and semantic test still required
```
