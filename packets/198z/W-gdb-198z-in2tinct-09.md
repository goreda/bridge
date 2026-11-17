# W-gdb-198z-in2tinct-09 - Relocated fixture consumer b-gate-tests
state: OPEN / unclaimed
lab: in2tinct

Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.

Required acceptance: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior/path change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned blobs, not a full Swift package build. Full source below is read-only input until this packet is claimed. Earliest claim wins;2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification; native/UI/runtime NOT_RUN unless actually executed.

```packet-json
{
  "packet_id": "W-gdb-198z-in2tinct-09",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Named lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/b-gate-tests/BoundsTable.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Relocated fixture consumer b-gate-tests; Update only this production consumer file for the fixed contract top-level fixtures -> Tests/Fixtures and kits -> archive/kits. Preserve each fixture basename, argv override, code behavior and pin string semantics. Audit actual path computations, not global text replacement. Do not change nested Sources/photon-sharp-tests/fixtures, Tests/labs/*/fixtures or kit-local fixtures. No directory move in this return; integrator applies the shared move once. Do not rewrite historical comments just to rename paths.",
    "types": "Existing declarations in exact full sources below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file;2h lease expires without holder commit; no gor U2/S2 host edits",
    "caller": "Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "callee": "Sources/b-gate-tests/BoundsTable.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-09.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Run the existing executable for this consumer after materializing both directory moves in an isolated exact-pin checkout. Assert the same named fixture is loaded before/after. Return exact commands, exit codes and baseline vs moved output. Also run one missing-fixture negative control. Keep Swift/native availability honest.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-198z-in2tinct-09",
    "paths": [
      "Sources/b-gate-tests/BoundsTable.swift",
      "Tests/Architecture/198z/W-gdb-198z-in2tinct-09.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198z/W-gdb-198z-in2tinct-09.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:45:28.630175+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "Sources/b-gate-tests/BoundsTable.swift",
        "block": "source1",
        "sha256": "3e53181fb3baa244ead365bec2ae90df4accdc6bc3a60287a36fb97ff9bf4c5d"
      },
      {
        "path": "Tests/Architecture/198z/W-gdb-198z-in2tinct-09.py",
        "block": "fixtures1",
        "sha256": "f2e9373ebe771275b5d7d54b1ea0f6e929b47a9e20d4aeb49c490fe5bd3e2007"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "af53f32e7bb3f339c55458cc8b604986ba6452d867d64ef1b231c43ed50dcaf9",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-09; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "28e581d57e7f9dabccf706db906cdb9b27dcdaecdf91298fef7eff4fe8de12d3"
  }
}
```

```swift id=source1
import Foundation

/// Cited bounds loaded from kits/bounds-table/bounds.json (read-only).
/// Usage at the two call sites in main.swift (integrator applies; full file not in packet):
///   B1 resume waitFor timeout:        BoundsTable.shared.seconds("resume-after-pause landing")
///   B2 audio-landing waitFor timeout: BoundsTable.shared.seconds("post-seek audio landing")
struct BoundsTable {
    struct Row: Decodable {
        let name: String
        let value: Double
        let unit: String
        let kind: String
        let citation: String
        let confidence: String
    }
    struct File: Decodable { let rows: [Row] }

    let rows: [String: Row]

    static let shared: BoundsTable = {
        // BGATE_BOUNDS_JSON overrides; default is repo-relative to the working directory.
        let path = ProcessInfo.processInfo.environment["BGATE_BOUNDS_JSON"]
            ?? "kits/bounds-table/bounds.json"
        guard let data = FileManager.default.contents(atPath: path),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            FileHandle.standardError.write(Data("b-gate: cannot load bounds table at \(path)\n".utf8))
            exit(2)
        }
        return BoundsTable(rows: Dictionary(uniqueKeysWithValues: file.rows.map { ($0.name, $0) }))
    }()

    /// Seconds for a named row; exits 2 if the row is missing or uncited (no inline fallback).
    func seconds(_ name: String) -> Double {
        guard let r = rows[name], !r.citation.isEmpty, r.value > 0 else {
            FileHandle.standardError.write(Data("b-gate: bound '\(name)' missing or uncited\n".utf8))
            exit(2)
        }
        return r.unit == "ms" ? r.value / 1000 : r.value
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[3]
assert hashlib.sha256((ROOT/'Sources/b-gate-tests/BoundsTable.swift').read_bytes()).hexdigest()=='3e53181fb3baa244ead365bec2ae90df4accdc6bc3a60287a36fb97ff9bf4c5d'
print('BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-09; baseline only, product change and semantic test still required')
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-198z-in2tinct-09; baseline only, product change and semantic test still required
```

secret scan: clean
