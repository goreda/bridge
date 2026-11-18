# W-gdb-199c-1nstinct-12 - Validate forward crop-batch timestamps
state: OPEN / unclaimed
lab: 1nstinct

## Product change
TransferProbeAdmission.cropBatch must validate the selected candidate slice before returning it: timestamps must be finite, nonnegative and nondecreasing. Stop before the first invalid or backward timestamp, never skip it to include later values; if the first is invalid return empty. Keep existing index check, frameBytes budget, three-frame cap and inclusive six-second span. Ignore invalid values outside the bounded candidate slice; preserve all transfer source/lock/admission and ticket behavior.

## Grounded gap and boundary
U2 crop-detection pipeline prerequisite; S2 GorSources station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-12.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. All new test paths start under archive/gor/Tests. This packet does not touch GorCore; preserve any later BuildID/launch-identity return when rebasing. If a later rebase requires a GorCore edit, stop and obtain a refreshed source lease instead of silently changing launch identity.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-12",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorSources/TransferTicketContext.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "TransferProbeAdmission.cropBatch must validate the selected candidate slice before returning it: timestamps must be finite, nonnegative and nondecreasing. Stop before the first invalid or backward timestamp, never skip it to include later values; if the first is invalid return empty. Keep existing index check, frameBytes budget, three-frame cap and inclusive six-second span. Ignore invalid values outside the bounded candidate slice; preserve all transfer source/lock/admission and ticket behavior.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 crop-detection pipeline prerequisite; S2 GorSources station",
    "callee": "archive/gor/Sources/gor/GorSources/TransferTicketContext.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-12.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-12",
    "paths": [
      "archive/gor/Sources/gor/GorSources/TransferTicketContext.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-12.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-12.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-12.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:21:53.202120+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "30ef906bb152d9f79b9b89fe3aff2f97b9b964aeadf20a83b1086930c5d42859",
    "last_5_lines": [
      "PASS nondecreasing duplicates preserved",
      "PASS six second bound preserved",
      "semantic failures=2",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorSources/TransferTicketContext.swift",
        "block": "source1",
        "sha256": "561cba0c7d3a3956eba7faf6df5a5962a1adabe0cf90432c557f6696c97c9820",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-12.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-12.json",
        "block": "fixtures2",
        "sha256": "2d2a15de72ad562b9a5ca0114e2b764ae31e4a215b5f3116df2ea0058c8281b6"
      }
    ],
    "receipt_sha256": "164d3d682740ac837845458bf27a56956b5a9cf52c1b3a9fa0f115c141dfb380"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

// Main-queue-only metadata, bound to the exact captured CDN URL. Contains no
// passwords/cookies; protected transfers keep their original captured ticket.
enum TransferTicketContext {
    private static var tickets: [String: (share: String, node: String)] = [:]

    static func remember(url: String?, shareURL: String, node: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let url, let parts = URLComponents(string: shareURL),
              parts.scheme == "https", parts.host?.lowercased() == "transfer.it",
              parts.path.hasPrefix("/t/"),
              let share = parts.path.split(separator: "/").last,
              share.range(of: "^[A-Za-z0-9_-]{8,64}$", options: .regularExpression) != nil,
              node.range(of: "^[A-Za-z0-9_-]{8}$", options: .regularExpression) != nil else { return }
        if tickets.count > 32 { tickets.removeAll() }
        tickets[url] = (String(share), node)
    }

    static func lookup(_ url: String) -> (share: String, node: String)? {
        dispatchPrecondition(condition: .onQueue(.main))
        return tickets[url]
    }
}

// Exact relay identity is registered only by the transfer.it launch path.
// No localhost-port guessing: ordinary MEGA and local/magnet sources bypass it.
enum TransferProbeAdmission {
    private static let lock = NSLock()
    private static var source: String?
    private static var forward = 0.0
    private static var stalled = true
    private static var updated = 0.0
    private static var sampleStamp: String?
    static let minimumForward = 15.0

    static func configure(_ path: String?) {
        lock.lock(); defer { lock.unlock() }
        source = path; forward = 0; stalled = true; updated = 0; sampleStamp = nil
    }
    static func markerCommand(_ path: String?) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["command": ["set_property", "user-data/gor-transfer-source", path ?? ""]])
        return String(decoding: data, as: UTF8.self)
    }
    static func isSource(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return source != nil && source == path
    }
    static func update(path: String, seconds: Double?, pausedForCache: Bool?, stamp: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard source == path else { return }
        if let stamp, stamp == sampleStamp { if pausedForCache == true { stalled = true }; return }
        sampleStamp = stamp
        forward = seconds ?? 0; stalled = pausedForCache != false
        updated = ProcessInfo.processInfo.systemUptime
    }
    static func admits(_ path: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard source != nil, source == path else { return true }
        return updated > 0 && ProcessInfo.processInfo.systemUptime - updated < 3 &&
            forward.isFinite && forward >= minimumForward && !stalled
    }
    // At most six seconds decoded per open, never a whole-film filter scan.
    // Keep at most 96 MiB of batch output (or one existing-size frame).
    static func cropBatch(_ positions: [Double], index: Int, frameBytes: Int) -> [Double] {
        guard positions.indices.contains(index), frameBytes > 0 else { return [] }
        let first = positions[index], cap = max(1, min(3, 96 * 1024 * 1024 / frameBytes))
        return Array(positions[index...].prefix(cap).prefix { $0 - first <= 6 })
    }
    static func cropSelection(_ times: [Double]) -> String {
        guard let first = times.first else { return "0" }
        return times.enumerated().map { i, t in
            "gte(t,\(String(format: "%.9f", locale: Locale(identifier: "en_US_POSIX"), t - first)))*lt(selected_n,\(i + 1))"
        }.joined(separator: "+")
    }

}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5]
CFG=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:
 print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
with tempfile.TemporaryDirectory() as d:
 d=Path(d); main=d/'main.swift'; main.write_text(CFG['test_source']); exe=d/'test'
 args=[swift]+[str(ROOT/p) for p in CFG['sources']]+[str(main),'-o',str(exe)]
 c=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('compile_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 if c.returncode: sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
 print('semantic_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "sources": [
    "archive/gor/Sources/gor/GorSources/TransferTicketContext.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\ncheck(TransferProbeAdmission.cropBatch([10,9,11],index: 0,frameBytes: 1) == [10],\"stop before backward timestamp\")\ncheck(TransferProbeAdmission.cropBatch([-1,0],index: 0,frameBytes: 1).isEmpty,\"negative first timestamp refused\")\ncheck(TransferProbeAdmission.cropBatch([0,Double.infinity,1],index: 0,frameBytes: 1) == [0],\"stop before nonfinite timestamp\")\ncheck(TransferProbeAdmission.cropBatch([0,3,6,9],index: 0,frameBytes: 1) == [0,3,6],\"three-frame inclusive span preserved\")\ncheck(TransferProbeAdmission.cropBatch([1,1,2],index: 0,frameBytes: 1) == [1,1,2],\"nondecreasing duplicates preserved\")\ncheck(TransferProbeAdmission.cropBatch([0,7],index: 0,frameBytes: 1) == [0],\"six second bound preserved\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL stop before backward timestamp
FAIL negative first timestamp refused
PASS stop before nonfinite timestamp
PASS three-frame inclusive span preserved
PASS nondecreasing duplicates preserved
PASS six second bound preserved
semantic failures=2



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
