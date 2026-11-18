# W-gdb-199h-wr-03 - Installed BuildID read
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h writer/installed-buildid-read. Writer item: read the installed app's build identity for the delivery/rollback path. Parse the installed bundle's Contents/Resources/build-id.txt with BuildID.parseCommit semantics (commit= SHA256 of the compiled source manifest, written by build.sh). A missing, unreadable or malformed file yields unknown, never a crash, and the launch log line is still written every launch. The rollback decision consumes only this read value.

Required acceptance: Linux tests for parseCommit edge cases (empty value, whitespace inside value, legacy opaque grammar, missing file) plus an installed-bundle read fixture. Mac compile through D1.

This is PRODUCT work: at least one listed production file must change with a meaningful behavior change and a test. Baseline-only or test-only returns count0. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
  "packet_id": "W-gdb-199h-wr-03",
  "lab": "shared",
  "writer": "1nstinct or in2tinct (earliest claim wins)",
  "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/BuildID.swift",
      "excerpt_block": "see pinned excerpts below"
    }
  ],
  "interface": {
    "signatures": "Installed BuildID read; Writer item: read the installed app's build identity for the delivery/rollback path. Parse the installed bundle's Contents/Resources/build-id.txt with BuildID.parseCommit semantics",
    "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
    "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit",
    "caller": "Linux tests for parseCommit edge cases (empty value, whitespace inside value, legacy opaque grammar, missing file) plus an installed-bundle read fixture. Mac compile through D1.",
    "callee": "archive/gor/Sources/gor/BuildID.swift"
  },
  "scope": "product",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-03.py",
    "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires a real production change plus executed semantic tests: Linux tests for parseCommit edge cases (empty value, whitespace inside value, legacy opaque grammar, missing file) plus an installed-bundle read fixture. Mac compile through D1.",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "lane/lab-<claiming-lab>-W-gdb-199h-wr-03",
    "paths": [
      "archive/gor/Sources/gor/BuildID.swift",
      "archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-03.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_repo": "goreda/instinct",
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "reference_repo": "goreda/bridge",
    "reference_sha": "fbb0932e82fbd1aa22d5792f7cad77f4d45b27ef",
    "command": "python3 archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-03.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-18T10:03:22.842435+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/BuildID.swift",
        "lines": "1-42",
        "sha256": "4cf3984e2674800af070c8d55f9728f770dc23d7e7417ffa3b728c119e704c62"
      },
      {
        "path": "inputs/198k/build.sh",
        "lines": "2618-2626",
        "sha256": "95cc6c8429e7035bdc150788d23ddbee6ef7c6ab8cafea46ca885bc25193c316"
      },
      {
        "path": "archive/gor/Tests/Architecture/199h-wr/W-gdb-199h-wr-03.py",
        "block": "fixtures1",
        "sha256": "7b7d8cb95f23b5eb7af3106bef441f31cdd671cdc3bec0908349aba04bcb0c24"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "64e063df7f18e9c6522b7c930281524ffe1069de770249bbc3f11fc953481b88",
    "last_5_lines": [
      "BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-03; baseline only, product change and semantic test still required"
    ],
    "receipt_sha256": "1dfd6bf679f525613ffcd6ecf2dcd708699ad1667fb2b18a5380ea08099d49c2"
  }
}
```

```swift id=Sources/gor/BuildID.swift:1-42
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

    /// Exact launch log line.
    static func logLine(_ value: String) -> String { "[GOR] build-id \(value)" }

    /// Short form for the About label (7 chars of the source identity, else as-is).
    static func shortValue(_ value: String) -> String {
        value == unknown ? unknown : String(value.prefix(7))
    }
}
```

```bash id=inputs/198k/build.sh:2618-2626
/usr/bin/python3 - "$source_snapshot" "$res/build-id.txt" <<'PY_BUILD_ID'
import hashlib, pathlib, sys
snapshot, output = map(pathlib.Path, sys.argv[1:])
identity = hashlib.sha256(snapshot.read_bytes()).hexdigest()
output.write_text('commit=' + identity + '\nidentity_kind=source-manifest-sha256\n')
assert output.read_text().splitlines()[0] == 'commit=' + identity
print('      build-id (source manifest): ' + identity)
PY_BUILD_ID
# GOR_BUILD_ID_END
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
BRIDGE_ROOT = Path(os.environ.get("BRIDGE_ROOT", "/nonexistent"))
CHECKS = [["product", "Sources/gor/BuildID.swift", 1, 42, "4cf3984e2674800af070c8d55f9728f770dc23d7e7417ffa3b728c119e704c62"], ["bridge", "inputs/198k/build.sh", 2618, 2626, "95cc6c8429e7035bdc150788d23ddbee6ef7c6ab8cafea46ca885bc25193c316"]]
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
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-03; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-wr-03; baseline only, product change and semantic test still required
```

secret scan: clean
