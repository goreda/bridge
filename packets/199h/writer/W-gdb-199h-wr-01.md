# W-gdb-199h-wr-01 - Grain vendor binding
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h writer/grain-vendor-binding. Writer item: bind the vendored photon-grain.lua into the product control path end to end. The script ships under Resources/vendor/mpv/scripts, is covered by requiredLua seeding, the fold/toggle map routes grain to script-message-to photon_grain photon-grain-toggle, and the adjust menu carries the grain item (menuPhotonGrain, key g).

Required acceptance: Toggle round-trip flips the grain shader state through the vendored script; the vendor manifest lists photon-grain.lua as a regular file; a missing script is a named refusal, never a crash. Mac compile/runtime through D1.

This is PRODUCT work: at least one listed production file must change with a meaningful behavior change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
  "packet_id": "W-gdb-199h-wr-01",
  "lab": "shared",
  "writer": "1nstinct or in2tinct (earliest claim wins)",
  "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/PPController.swift",
      "excerpt_block": "see pinned excerpts below"
    },
    {
      "path": "archive/gor/Sources/gor/AppDelegate.swift",
      "excerpt_block": "see pinned excerpts below"
    }
  ],
  "interface": {
    "signatures": "Grain vendor binding; Writer item: bind the vendored photon-grain.lua into the product control path end to end. The script ships under Resources/vendor/mpv/scripts, is covered by requiredLua seeding, th",
    "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit",
    "caller": "Toggle round-trip flips the grain shader state through the vendored script; the vendor manifest lists photon-grain.lua as a regular file; a missing script is a named refusal, never a crash. Mac compile/runtime through D1.",
    "callee": "archive/gor/Sources/gor/PPController.swift, archive/gor/Sources/gor/AppDelegate.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-01.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Toggle round-trip flips the grain shader state through the vendored script; the vendor manifest lists photon-grain.lua as a regular file; a missing script is a named refusal, never a crash. Mac compile/runtime through D1.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-<claiming-lab>-W-gdb-199h-wr-01",
    "paths": [
      "archive/gor/Sources/gor/PPController.swift",
      "archive/gor/Sources/gor/AppDelegate.swift",
      "archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-01.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_repo": "goreda/instinct",
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "reference_repo": "goreda/bridge",
    "reference_sha": "fbb0932e82fbd1aa22d5792f7cad77f4d45b27ef",
    "command": "python3 archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-01.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-18T10:03:22.841154+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/PPController.swift",
        "lines": "1954-1968",
        "sha256": "53e6b78f5bf563ba21538484bb05b589c502fd938a31828049a75ced526415cb"
      },
      {
        "path": "archive/gor/Sources/gor/AppDelegate.swift",
        "lines": "713-720",
        "sha256": "6c10cec6f638e6ceb2e16d12816b6640252d28f748eaa2cd9ec002ad923b3eda"
      },
      {
        "path": "archive/gor/Sources/gor/AppDelegate.swift",
        "lines": "3072-3084",
        "sha256": "4d01e1c8a5a65cb28236b4f27a02209cda4b107e96971cdd7993400c5344a8d7"
      },
      {
        "path": "archive/gor/Resources/vendor/mpv/scripts/photon-grain.lua",
        "lines": "1-25",
        "sha256": "96296bb2c644059b8f764c5610afdf29af4f376296cfd07a0f017f6b7f73b16d"
      },
      {
        "path": "archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-01.py",
        "block": "fixtures1",
        "sha256": "d8d21b086cdf81de7d1cd09ac965a03d8ecf8135a3b3753f5df4f4c92e72d53f"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "dec0e3f3215ebe3c458592aa0dc89445dbc9ddedcc4d91b38b80d7f1a1e86c1e",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-01; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "67a3a1037497a1fd41c32cb24130ebf95422134e1c0566c65339f0b3e21ee61a"
  }
}
```

```swift id=Sources/gor/PPController.swift:1954-1968

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
```

```swift id=Sources/gor/AppDelegate.swift:713-720
    /// Writable home for mpv's config dir. The bundled vendor/mpv is sealed
    /// with the app, but photon writes generated GLSL and mpv writes its GPU
    /// shader cache into the config dir. Every launch re-seeds the bundled
    /// defaults into Application Support (fresh scripts per build), skipping
    /// the generated subtrees (shader/, cache/) that only exist locally.
    enum ScriptsSeedResult { case installed, failedOldIntact, failedBroken }
    static let requiredLua = ["photon.lua", "photon-common.lua", "photon-grain.lua", "photon-hud.lua", "autoload.lua"]
    static func seedLuaScripts(from srcIn: URL, into dst: URL, parent: URL) -> ScriptsSeedResult {
```

```swift id=Sources/gor/AppDelegate.swift:3072-3084
        photonMenu.addItem(item("photon",         action: #selector(menuPhotonToggle),  key: "\u{F70C}", mods: []))
        photonMenu.addItem(item("hud",            action: #selector(menuPhotonHUD),     key: "\u{F70B}", mods: []))
        photonMenu.addItem(item("stats",          action: #selector(menuStatsToggle),   key: "i", mods: []))
        photonMenu.addItem(.separator())
        let photonAdjustMenu = group("adjust", in: photonMenu)
        photonAdjustMenu.addItem(item("bright",         action: #selector(menuPhotonBright),  key: "b", mods: []))
        photonAdjustMenu.addItem(item("sharp",          action: #selector(menuPhotonSharp),   key: "x", mods: []))
        photonAdjustMenu.addItem(item("grain",          action: #selector(menuPhotonGrain),   key: "g", mods: []))
        let photonFiltersMenu = group("filters", in: photonMenu)
        photonFiltersMenu.addItem(item("chrome",         action: #selector(menuPhotonChrome),  key: "c", mods: []))
        photonFiltersMenu.addItem(item("chrome filter",  action: #selector(menuPhotonChromeFilter), key: "c", mods: [.shift]))
        photonFiltersMenu.addItem(item("negativ",        action: #selector(menuPhotonNegativ), key: "n", mods: []))

```

```lua id=Resources/vendor/mpv/scripts/photon-grain.lua:1-25
-- ================================================================
--  photon-grain.lua - OUTPUT-stage film grain
--  Owns: grain shader, scene-adaptive state and messages
--  Answers: I40 · TRAP-09
--  Contract: photon bootstrap precedes require; live shader values use parameters
-- ================================================================
local script_dir = mp.get_opt("photon-scriptdir")
if script_dir then
    local probe = io.open(script_dir .. "/photon-common.lua", "r")
    if probe then
        probe:close()
        package.path = script_dir .. "/?.lua;" .. package.path
    else
        mp.msg.error("photon-grain: photon-scriptdir invalid or photon-common.lua missing - checked: " .. script_dir .. "/photon-common.lua")
    end
end
local common_ok, common = pcall(require, "photon-common")
if not common_ok then
    mp.msg.error("photon-grain: could not load photon-common - " .. tostring(common) .. ". This script is disabled.")
    return
end
local PHOTON_REQUIRED_COMMON_VERSION = 2
if not common.check_version("photon-grain", PHOTON_REQUIRED_COMMON_VERSION) then
    return
end
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
BRIDGE_ROOT = Path(os.environ.get("BRIDGE_ROOT", "/nonexistent"))
CHECKS = [["product", "Sources/gor/PPController.swift", 1954, 1968, "53e6b78f5bf563ba21538484bb05b589c502fd938a31828049a75ced526415cb"], ["product", "Sources/gor/AppDelegate.swift", 713, 720, "6c10cec6f638e6ceb2e16d12816b6640252d28f748eaa2cd9ec002ad923b3eda"], ["product", "Sources/gor/AppDelegate.swift", 3072, 3084, "4d01e1c8a5a65cb28236b4f27a02209cda4b107e96971cdd7993400c5344a8d7"], ["product", "Resources/vendor/mpv/scripts/photon-grain.lua", 1, 25, "96296bb2c644059b8f764c5610afdf29af4f376296cfd07a0f017f6b7f73b16d"]]
bad = []
for root, rel, a, b, want in CHECKS:
    base = ROOT if root == "product" else BRIDGE_ROOT
    lines = (base / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-01; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-01; baseline only, product change and semantic test still required
```

secret scan: clean
