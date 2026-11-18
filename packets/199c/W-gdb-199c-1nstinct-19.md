# W-gdb-199c-1nstinct-19 - Invalid remembered subtitle mode scale cannot publish
state: OPEN / unclaimed
lab: 1nstinct

## Product change
SubtitleModeScale.transition must validate the target mode scale as finite positive before changing pictureInPicture. Refuse invalid stored target by returning nil and leave current mode unchanged, so accepting a repaired current-mode scale cannot write the wrong bucket. Preserve duplicate-mode no-op, valid transition values and persistence keys. No network downloader or UI changes.

## Grounded gap and boundary
U2 subtitle size/readback prerequisite; S2 Subtitles. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-19.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. BuildID is read-only compile support in A20: preserve later BuildID/launch-identity returns on rebase; no GorCore edit is leased.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-19",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Subtitles/SubtitlePreferences.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "SubtitleModeScale.transition must validate the target mode scale as finite positive before changing pictureInPicture. Refuse invalid stored target by returning nil and leave current mode unchanged, so accepting a repaired current-mode scale cannot write the wrong bucket. Preserve duplicate-mode no-op, valid transition values and persistence keys. No network downloader or UI changes.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 subtitle size/readback prerequisite; S2 Subtitles",
    "callee": "archive/gor/Sources/gor/Subtitles/SubtitlePreferences.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-19.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-19",
    "paths": [
      "archive/gor/Sources/gor/Subtitles/SubtitlePreferences.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-19.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-19.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-19.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:44:43.924103+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "59a0e4947e768b85d81cccafccc68ff601e91579f6be9a59f283935f25f9c3d1",
    "last_5_lines": [
      "FAIL refusal preserves mode",
      "PASS valid transitions retained",
      "semantic failures=8",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Subtitles/SubtitlePreferences.swift",
        "block": "source1",
        "sha256": "b9d27a54dc0af5dd37504f289bf2240deb923b0df3c14271a64d39eb6efece5f",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-19.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-19.json",
        "block": "fixtures2",
        "sha256": "efa2472a0b3ee0ada2a63ae373c1bb484b99de2799be7daa1fd7cc0cc7271001"
      }
    ],
    "receipt_sha256": "4852b0209462faaced3162470ae8ace8724e6497b344e9e248623092989dd567"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

// MARK: - SubtitleModeScale
/// The canonical mpv property belongs to the currently displayed mode, never
/// to the remembered windowed-PiP intent while fullscreen is active.
struct SubtitleModeScale {
    var normal:Double
    var pip:Double
    private(set) var pictureInPicture=false
    mutating func transition(to pipMode:Bool)->Double? {
        guard pipMode != pictureInPicture else{return nil}
        pictureInPicture=pipMode
        return pipMode ? pip:normal
    }
    mutating func accept(_ value:Double) {
        guard value.isFinite,value>0 else{return}
        if pictureInPicture {pip=value} else {normal=value}
    }
}

// MARK: - SubtitleSizePreference
/// Only explicit subtitle size is durable. Delay/AV offsets remain session state.
enum SubtitleSizePreference {
    static let key="gor.subtitle.fontScale"
    static func valid(_ value:Double)->Bool {value.isFinite && value>0}
    static func restored(defaults:UserDefaults = .standard,stateURL:URL = URL(fileURLWithPath:NSTemporaryDirectory()+"gor-subtitle-state.json"))->Double? {
        if let value=defaults.object(forKey:key) as? NSNumber,valid(value.doubleValue) {return value.doubleValue}
        // First upgrade: recover the last app-authored size receipt before the
        // fresh child process's default1 can overwrite it. No other state migrates.
        guard let data=try? Data(contentsOf:stateURL),data.count<65536,
              let row=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              row["build"] is String,row["pid"] is NSNumber,
              let value=row["sub-scale"] as? NSNumber,valid(value.doubleValue) else{return nil}
        defaults.set(value.doubleValue,forKey:key)
        return value.doubleValue
    }
    static func restoredPiP(defaults:UserDefaults = .standard)->Double {
        let value=defaults.double(forKey:"gor.subtitle.pipFontScale")
        return valid(value) ? value:1
    }
    static func save(_ value:Double,defaults:UserDefaults = .standard,pictureInPicture:Bool=false) {
        guard valid(value) else{return}
        defaults.set(value,forKey:pictureInPicture ? "gor.subtitle.pipFontScale":key)
    }
}

// BEGIN relocated BoundedSubtitleDownload.swift (195w 2a, behavior unchanged)
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ephemeral, memory-only network reads. No URLSession download files or URL
/// cache are created. The delegate stops oversized bodies before keeping them.
final class BoundedSubtitleDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let subtitleLimit = 32 * 1024 * 1024
    private let limit: Int
    private var bytes = Data()
    private var completed = false
    private var session: URLSession?
    private let completion: (Data?) -> Void
    private init(limit: Int, completion: @escaping (Data?) -> Void) {
        self.limit = limit; self.completion = completion
    }
    static func fetch(_ request: URLRequest, limit: Int = subtitleLimit, completion: @escaping (Data?) -> Void) {
        guard limit > 0 else { completion(nil); return }
        let reader = BoundedSubtitleDownload(limit: limit, completion: completion)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: reader, delegateQueue: queue)
        reader.session = session
        session.dataTask(with: request).resume()
    }
    private func finish(_ data: Data?) {
        guard !completed else { return }; completed = true
        bytes.removeAll(keepingCapacity: false)
        completion(data)
        session?.invalidateAndCancel(); session = nil
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
              response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(nil); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !completed, data.count <= limit - bytes.count else { finish(nil); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        let result = error == nil && !bytes.isEmpty ? bytes : nil
        finish(result)
    }
}
// END relocated BoundedSubtitleDownload.swift

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
    "archive/gor/Sources/gor/Subtitles/SubtitlePreferences.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nfor bad in [Double.nan,Double.infinity,-1,0] {\n var mode=SubtitleModeScale(normal:2,pip:bad)\n check(mode.transition(to:true) == nil,\"bad target scale refused\")\n check(!mode.pictureInPicture,\"refusal preserves mode\")\n}\nvar normal=SubtitleModeScale(normal:2,pip:3)\ncheck(normal.transition(to:true) == 3 && normal.transition(to:false) == 2,\"valid transitions retained\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL bad target scale refused
FAIL refusal preserves mode
FAIL bad target scale refused
FAIL refusal preserves mode
FAIL bad target scale refused
FAIL refusal preserves mode
FAIL bad target scale refused
FAIL refusal preserves mode
PASS valid transitions retained
semantic failures=8



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
