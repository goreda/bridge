# W-gdb-198y-1nstinct-05
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/BuildID.swift -> gor. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-05.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-05",
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
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/BuildID.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: BuildID, parseCommit, value, logLine, shortValue",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-05.py",
    "callee": "archive/gor/Sources/gor/BuildID.swift owning station gor"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-05.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-05.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-05.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:15.252504+00:00",
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
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-05.py",
        "block": "fixtures1",
        "sha256": "d3bf6f2e262f597eefc05277330b01db018134805fbb45a784f5cd7662210770"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "6cb42ca914b76a0afe6189c5e1e33bf8e8e37c18c61de210cf56f3428cd4c4f5",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-05: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "3887e34239f3759a3e8c513a479172fb5470b9a3b6fc4e1ecc8d734b34fd08a5"
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
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-05: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-05: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
