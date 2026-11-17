# W-gdb-198y-1nstinct-25
state: OPEN / unclaimed
lab: 1nstinct

Build a new independent scope-aware source/move characterization test for this exact file. Parse lexical nominal ownership including nesting, ignore comments/strings, and compare fully qualified declaration owners across the entire pinned Sources tree. Do not confuse nested names in unrelated owners with duplicates. Preserve pinned bytes. Check old and mapped station, renamed copies, valid overload/nested-name controls, and real duplicate mutants. Use explicit failure paths that remain active under python3 -O. Run normal and optimized positive plus on-disk external negative/restore controls. The existing 01..20 returns are evidence only and may not be copied unchanged.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-25.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-25",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/BuildID.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-25.py checks archive/gor/Sources/gor/BuildID.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: BuildID, parseCommit, value, logLine, shortValue",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-25.py",
    "callee": "archive/gor/Sources/gor/BuildID.swift owning station gor"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-25.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-25.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-25.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:15.872116+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/BuildID.swift",
        "block": "source1",
        "sha256": "4cf3984e2674800af070c8d55f9728f770dc23d7e7417ffa3b728c119e704c62"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-25.py",
        "block": "fixtures1",
        "sha256": "d0e75f8340ea797f021943071099089fa5ede86e9f255f3733bddcd8724d05b2"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "bee6ad9e96b6df26ac6e51de6f97085c22a07880e1d08b249373d593757dcfd9",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-25: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "a144b5e2182964941399778426faa31a7e2ea9b8c0f2e2655a41b2927d58f849"
  }
}
```

```swift id=source1
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

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/BuildID.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='4cf3984e2674800af070c8d55f9728f770dc23d7e7417ffa3b728c119e704c62', 'pinned source changed: rebase and review, never bless silently'
for token in ['BuildID', 'parseCommit', 'value', 'logLine', 'shortValue']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='4cf3984e2674800af070c8d55f9728f770dc23d7e7417ffa3b728c119e704c62'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-25: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-25: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
