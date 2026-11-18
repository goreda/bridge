# W-gdb-199h-wrr2-03 - Installed BuildID read (r2: current-candidate check + wiring)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h WR (r2, pinned to native49 b570c15ac). BuildID reads <bundle>/Contents/Resources/build-id.txt (parseCommit pure parser, launchLine) and AppDelegate prints one bounded line per launch (excerpts below). Lane-c: applies in principle; needs a current-candidate BuildID check; rollback caller and launch logging not wired. r2 scope: add the current-candidate comparison (installed vs candidate build-id) with a typed mismatch result, wire the rollback caller to it, and extend launch logging to record the comparison outcome. Linux-test the pure parser/comparator parts.

Required acceptance: Linux tests: parser edge cases (missing/empty/malformed commit=, whitespace) + candidate comparison outcomes; patch wires rollback caller and launch line.

This is PRODUCT work: at least one listed Sources file must change with a meaningful behavior change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-wrr2-03",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "b570c15ac927fe3b5fdaf831bd5167f8f45059aa",
 "touched_files": [
  {
   "path": "archive/gor/Sources/gor/GorCore/BuildID.swift",
   "excerpt_block": "buildid_full (lines 1-76)"
  },
  {
   "path": "archive/gor/Sources/gor/AppDelegate.swift",
   "excerpt_block": "buildid_full (lines 1-76)"
  }
 ],
 "interface": {
  "signatures": "BuildID reads <bundle>/Contents/Resources/build-id.txt (parseCommit pure parser, launchLine) and AppDelegate prints one bounded line per launch (excerpts below). Lane-c: applies in principle; needs a ",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Linux tests: parser edge cases (missing/empty/malformed commit=, whitespace) + candidate comparison outcomes; patch wires rollback caller and launch line.",
  "callee": "archive/gor/Sources/gor/GorCore/BuildID.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r2/W-gdb-199h-wrr2-03.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Linux tests: parser edge cases (missing/empty/malformed commit=, whitespace) + candidate comparison outcomes; patch wires rollback caller and launch line.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-wrr2-03",
  "paths": [
   "archive/gor/Sources/gor/GorCore/BuildID.swift",
   "archive/gor/Sources/gor/AppDelegate.swift",
   "archive/gor/Tests/Architecture/199h-d5r2/W-gdb-199h-wrr2-03.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "b570c15ac927fe3b5fdaf831bd5167f8f45059aa",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r2/W-gdb-199h-wrr2-03.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T10:34:30.319178+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Sources/gor/GorCore/BuildID.swift",
    "lines": "1-76",
    "block": "Sources/gor/GorCore/BuildID.swift:1-76",
    "sha256": "544881ae92b8f6b4235ed47b70c14f4997ee10a05faa06d877d5bf8f3df80365"
   },
   {
    "path": "archive/gor/Sources/gor/AppDelegate.swift",
    "lines": "480-486",
    "block": "Sources/gor/AppDelegate.swift:480-486",
    "sha256": "0e4be0eca3c4f60035475fa5829ffafa6ddc1355ba34ab8e4d6bac49d83a84aa"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r2/W-gdb-199h-wrr2-03.py",
    "block": "fixtures1",
    "sha256": "f0f1d4ffbad5448309f5da2c2aa0042b87904ee1fc850302c2f27dce278a46e4"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "1bafb12d6f8d9e9e68864e7621ea84e398c99d04b7cfc0de8632de7063ca38cc",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr2-03; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "8a1bf6bd485c9c98aeaf5b00ce54e0dd597be6e5073fcf6fe5fb3935728130b9"
 }
}
```

```swift id=Sources/gor/GorCore/BuildID.swift:1-76
import Foundation

/// K8(b): build identity shown in About and written to the synced log at launch.
/// Source: <bundle>/Contents/Resources/build-id.txt, written by build.sh.
/// The legacy key is commit=, but its value is the SHA256 of the compiled
/// source manifest, not a Git commit. Keep the format backward compatible.
/// A missing, unreadable or malformed file never crashes the app: the value is
/// "unknown" and the log line is still written on every launch (no skipping).
enum BuildID {
    static let resourceName = "build-id"
    static let resourceExtension = "txt"
    static let unknown = "unknown"

    /// Pure parser (no I/O). Returns the source identity value, or nil when the text has
    /// no usable `commit=` line (empty value or value containing whitespace).
    static func parseCommit(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("commit=") else { continue }
            let value = String(line.dropFirst("commit=".count)).trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value.contains(where: { $0.isWhitespace }) { return nil }
            return value
        }
        return nil
    }

    /// Value for display and log: the source identity, or "unknown".
    static func value(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let commit = parseCommit(text) else { return unknown }
        return commit
    }

    /// Pure parser (no I/O). Returns the delivered archive/gor tree sha, or nil when the
    /// text has no usable `tree=` line (must be exactly 40 lowercase hex chars).
    static func parseTree(_ text: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("tree=") else { continue }
            let value = String(line.dropFirst("tree=".count)).trimmingCharacters(in: .whitespaces)
            guard value.count == 40, value.allSatisfy({ $0.isASCII && ($0.isNumber || ("a"..."f").contains($0)) }) else { return nil }
            return value
        }
        return nil
    }

    /// Delivered archive/gor tree sha, or "unknown". Same never-crash contract as value().
    static func tree(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let text = try? String(contentsOf: url, encoding: .utf8),
              let tree = parseTree(text) else { return unknown }
        return tree
    }

    /// UTC launch timestamp for the launch line (ISO 8601, seconds precision).
    static func launchTimestamp(_ date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Exact launch log line: installed BuildID sha, archive/gor tree sha, launch time.
    /// One bounded ASCII line per launch; gor-periodic-capture carries it to the repo.
    static func launchLine(value: String, tree: String, at: Date = Date()) -> String {
        let safeValue = (value.isEmpty || value.contains(where: { $0.isWhitespace })) ? unknown : value
        let safeTree = (tree.isEmpty || tree.contains(where: { $0.isWhitespace })) ? unknown : tree
        return "[GOR] build-id \(safeValue) tree=\(safeTree) launch=\(launchTimestamp(at))"
    }

    /// Short form for the About label (7 chars of the source identity, else as-is).
    static func shortValue(_ value: String) -> String {
        value == unknown ? unknown : String(value.prefix(7))
    }
}
```

```swift id=Sources/gor/AppDelegate.swift:480-486
        print("[GOR] bundleID: \(Bundle.main.bundleIdentifier ?? "nil"), path: \(Bundle.main.bundlePath), executable: \(CommandLine.arguments[0])")
        // K8(b): build identity line, written on every launch (including "unknown").
        // arch-199b: one bounded line per launch - installed BuildID sha, delivered
        // archive/gor tree sha, launch time. Nothing on screen; rides the capture route.
        print(BuildID.launchLine(value: BuildID.value(), tree: BuildID.tree()))
        
        NSApp.setActivationPolicy(StagedRunPaths.active ? .prohibited : .regular)
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Sources/gor/GorCore/BuildID.swift", 1, 76, "544881ae92b8f6b4235ed47b70c14f4997ee10a05faa06d877d5bf8f3df80365"], ["Sources/gor/AppDelegate.swift", 480, 486, "0e4be0eca3c4f60035475fa5829ffafa6ddc1355ba34ab8e4d6bac49d83a84aa"]]
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
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr2-03; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-wrr2-03; baseline only, product change and semantic test still required
```
