# W-gdb-199c-1nstinct-09 - Refuse unsupported invalid stream offsets
state: OPEN / unclaimed
lab: 1nstinct

## Product change
admit must refuse every present startPos other than finite zero, using carriesStart. Negative/nonfinite offsets are unsupported pre-open intent, not permission to open from the beginning. Preserve nil/zero success, existing header/subtitle/tunnel precedence, URL string and pre-open-only routing. Do not widen admission or edit U2 hosts.

## Grounded gap and boundary
U2 pre-open fallback semantics; S2 GorAVBackend station. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-09.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-09",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorAVBackend/GorAVStreamAdmission.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "admit must refuse every present startPos other than finite zero, using carriesStart. Negative/nonfinite offsets are unsupported pre-open intent, not permission to open from the beginning. Preserve nil/zero success, existing header/subtitle/tunnel precedence, URL string and pre-open-only routing. Do not widen admission or edit U2 hosts.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 pre-open fallback semantics; S2 GorAVBackend station",
    "callee": "archive/gor/Sources/gor/GorAVBackend/GorAVStreamAdmission.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-09.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-09",
    "paths": [
      "archive/gor/Sources/gor/GorAVBackend/GorAVStreamAdmission.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-09.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-09.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-09.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:53.405359+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "7ca294a98009952032c93b5c060f8b5f2aa5ddfed9c7c5675063855d79ced5ca",
    "last_5_lines": [
      "FAIL unsupported offset refused",
      "FAIL unsupported offset refused",
      "semantic failures=3",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorAVBackend/GorAVStreamAdmission.swift",
        "block": "source1",
        "sha256": "e3d95e54dd3c87a7c30864165d54c2e76d058f02ff1fc85a5de8d7170337c773",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-09.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-09.json",
        "block": "fixtures2",
        "sha256": "e39b4595c366d336030966f82075ba37176c0f0e7ea1b423407bebaba0b4bb52"
      }
    ],
    "adaptation_note": "Coordinator moved test paths under archive/gor/Tests and runner ROOT parents3 to parents5. Original starter logs precede adaptation; adapted compiler rerun NOT_RUN."
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
// ================================================================
//  GorAVStreamAdmission.swift - pre-open stream admission for the gorav engine (T4 M1 gap 1)
//  Owns: deciding whether a playMedia URL may open on the gorav engine.
//  Contract: admission is PRE-OPEN only, mirroring PlayerBackendRoute: an
//  admitted URL goes to gorav, and a gorav-side typed refusal then never
//  replays on mpv; a refused URL falls through to the mpv load path
//  untouched. Owner-signed-off mpv behavior is unchanged on every refusal.
// ================================================================
import Foundation

enum GorAVStreamAdmission {
    enum Refusal: String, Error {
        case notRemoteHTTP = "not an http(s) stream URL"
        case needsTunnel = "blocked host: WARP tunnel is mpv-only"
        case carriesHeaders = "per-load cookie/gofile headers are mpv-only"
        case carriesSubtitles = "companion subtitles are mpv-only for streams"
        case carriesStart = "start offset is mpv-only for streams"
    }

    /// gorav opens only plain, already-resolved http(s) streams. Every gap-1
    /// source reaches playMedia in that form: wt_server torrent URLs (port
    /// 2222), the mega relay (port 2223), IPTV channel URLs, archive.org
    /// download URLs and the transfer.it relay. The owner's torrent app stays
    /// the resolver; gorav's own OpenURLRouter remains the authoritative
    /// classifier engine-side and typed-refuses anything outside its
    /// direct-remote class. Per-load headers, companion subtitles, a start
    /// offset and WARP-tunneled hosts have no gorav path yet and stay on mpv.
    static func admit(url: String, headerCount: Int, subtitleCount: Int, startPos: Double?, needsTunnel: Bool) -> Result<String, Refusal> {
        guard let c = URLComponents(string: url), let scheme = c.scheme?.lowercased(),
              scheme == "http" || scheme == "https", c.host != nil else { return .failure(.notRemoteHTTP) }
        guard !needsTunnel else { return .failure(.needsTunnel) }
        guard headerCount == 0 else { return .failure(.carriesHeaders) }
        guard subtitleCount == 0 else { return .failure(.carriesSubtitles) }
        if let startPos, startPos > 0 { return .failure(.carriesStart) } // explicit 0 is "from the beginning", gorav's default
        return .success(url)
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
    "archive/gor/Sources/gor/GorAVBackend/GorAVStreamAdmission.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nfor x in [Double.nan, Double.infinity, -Double.infinity, -1, 1] {\n if case .failure(.carriesStart) = GorAVStreamAdmission.admit(url: \"https://example.invalid/movie.mp4\",headerCount: 0,subtitleCount: 0,startPos: x,needsTunnel: false) {} else { check(false,\"unsupported offset refused\") }\n}\nfor x: Double? in [nil,0] {\n if case .success = GorAVStreamAdmission.admit(url: \"https://example.invalid/movie.mp4\",headerCount: 0,subtitleCount: 0,startPos: x,needsTunnel: false) {} else { check(false,\"default origin admitted\") }\n}\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL unsupported offset refused
FAIL unsupported offset refused
FAIL unsupported offset refused
semantic failures=3



```

Coordinator adaptation: test paths moved under archive/gor/Tests; ROOT adjusted to repository root. No semantic test changes. Original starter evidence not rerun here.

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
