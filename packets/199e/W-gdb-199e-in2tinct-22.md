# W-gdb-199e-in2tinct-22 - Serialize concurrent decode heartbeat publication
state: OPEN / unclaimed
lab: in2tinct

Ensure concurrent noteDecodedFrame calls cannot race through the shared temporary filename or publish an older counter after a newer one. Serialize count assignment plus atomic write ordering per instance or use equivalent monotonic publication. Preserve one write per decoded frame, atomic rename, disabled behavior and failure counting. Do not change soak runner or fabricate progress.

All listed production files compile in full. The concurrent stress starter reproduced RED on the initial run and five fresh repeat runs. Thread scheduling is nondeterministic, so an occasional green stress run alone is not proof of race absence; writer must review serialization and run repeated concurrency validation.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-in2tinct-22",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/DecodeHeartbeat.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Ensure concurrent noteDecodedFrame calls cannot race through the shared temporary filename or publish an older counter after a newer one. Serialize count assignment plus atomic write ordering per instance or use equivalent monotonic publication. Preserve one write per decoded frame, atomic rename, disabled behavior and failure counting. Do not change soak runner or fabricate progress.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "Sources/GorAVPlaybackCore/DecodeHeartbeat.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199e/W-gdb-199e-in2tinct-22.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199e-in2tinct-22",
    "paths": [
      "Sources/GorAVPlaybackCore/DecodeHeartbeat.swift",
      "Tests/Architecture/199e/W-gdb-199e-in2tinct-22.py",
      "Tests/Architecture/199e/W-gdb-199e-in2tinct-22.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199e/W-gdb-199e-in2tinct-22.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/DecodeHeartbeat.swift",
        "block": "source1",
        "sha256": "1c5ed5f1b1d7a75132b5295d7640736a180d0c63720fd0f5cf7785f30d271d2b",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199e/W-gdb-199e-in2tinct-22.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "Tests/Architecture/199e/W-gdb-199e-in2tinct-22.json",
        "block": "fixtures2",
        "sha256": "74cfea74b63429efa43289ced97821174c995474bdb4a5de7fe0b033c1e233ac"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "25e24da6ab98d2813cd887d30c7d88e207a2d2c4e504fa4937e591f6cea7381d",
    "last_5_lines": [
      "semantic_exit=1",
      "PASS all frames counted",
      "FAIL owned concurrent publications do not collide",
      "PASS final persisted counter is newest",
      ""
    ],
    "receipt_sha256": "086cb163c58b8cdc66d88affad13c665ce490263f0bcba8b9a7d7165c3bd42ec"
  }
}
```

```swift id=source1
// DecodeHeartbeat.swift - gorav block 168 L14 kit binding: the player's
// OWN decode-progress heartbeat for the L13 soak --heartbeat-file /
// --require-heartbeat gate and the L11 thermal PROGRESS_FILE binding.
//
// CONTRACT (L13 r4): $GORAV_HB_FILE names a per-run file; the value must
// be the player/decoder's OWN DECODE COUNTER - decoded frames produced by
// THIS player run. Never a wall tick, never a CPU proxy, never a liveness
// beacon: the gate treats a non-advancing value as SOAK_INCONCLUSIVE
// (liveness is not decode progress) and a stall as HANG.
//
// PLACEMENT: the writer lives in GorAVPlaybackCore (pure Foundation,
// Linux-venue testable); the decode-event ping lives in ShellFrameSource
// (MacShell), at the point the player's OWN decoder emits a decoded frame.
// Disabled unless the environment names a file: default runs are
// byte-identical to before (no file, no syscalls, no behavior change).
//
// FAILURE DISCIPLINE: a heartbeat write failure NEVER throws into
// playback. It is counted (writeFailures) and the counter keeps
// advancing in memory; the gate's honest outcome for a missing/stale
// file is INCONCLUSIVE, which is the correct signal - telemetry must
// not break playback, and playback must not fabricate telemetry.
import Foundation

public final class DecodeHeartbeat: @unchecked Sendable {
    /// The environment variable the L13 soak runner sets per run
    /// ({run_id}-substituted path; counters reset per playback).
    public static let environmentVariable = "GORAV_HB_FILE"

    private let path: String
    private let lock = NSLock()
    private var _count: UInt64 = 0
    private var _writeFailures: UInt64 = 0

    /// Decoded frames observed this run (starts at 0 per instance -
    /// a fresh playback run is a fresh counter, per the contract).
    public var count: UInt64 { lock.lock(); defer { lock.unlock() }; return _count }
    /// Write failures observed; diagnostic only, never fatal.
    public var writeFailures: UInt64 { lock.lock(); defer { lock.unlock() }; return _writeFailures }

    /// nil path (or empty) means DISABLED: init returns nil and the
    /// player carries no heartbeat at all (default unchanged behavior).
    public init?(path: String?) {
        guard let path, !path.isEmpty else { return nil }
        self.path = path
    }

    /// One decoded frame from the player's own decoder. Writes the new
    /// counter atomically (same-directory temp file + rename) so a
    /// concurrent reader never sees a torn value. Every call writes:
    /// no throttle, no timer - the value IS the decode counter, so the
    /// file advances exactly when decode advances.
    public func noteDecodedFrame() {
        lock.lock()
        _count &+= 1
        let v = _count
        lock.unlock()
        write(v)
    }

    private func write(_ v: UInt64) {
        let tmp = path + ".tmp-\(getpid())"
        do {
            try Data("\(v)\n".utf8).write(to: URL(fileURLWithPath: tmp))
            // POSIX rename(2) over the destination: the ONLY atomic
            // publish. (A remove+move pair would leave a window where
            // the path is absent, readable as a torn heartbeat.)
            if rename(tmp, path) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            lock.lock(); _writeFailures &+= 1; lock.unlock()
            try? FileManager.default.removeItem(atPath: tmp)
        }
    }
}

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(ROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith('ArchiveLibrary.swift') else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith('ArchiveLibrary.swift'):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "Sources/GorAVPlaybackCore/DecodeHeartbeat.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)\ntry FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)\ndefer {try? FileManager.default.removeItem(at:root)}\nlet path=root.appendingPathComponent(\"heartbeat\").path\nlet h=DecodeHeartbeat(path:path)!\nDispatchQueue.concurrentPerform(iterations:400) {_ in h.noteDecodedFrame()}\nlet text=try String(contentsOfFile:path,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)\ncheck(h.count == 400,\"all frames counted\")\ncheck(h.writeFailures == 0,\"owned concurrent publications do not collide\")\ncheck(UInt64(text) == h.count,\"final persisted counter is newest\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=1
PASS all frames counted
FAIL owned concurrent publications do not collide
PASS final persisted counter is newest


```

Publication caveat: NONQUALIFIED race reproducer: five fresh Linux runs RED, nondeterministic. One green run proves nothing. Acceptance requires deterministic ordering/barrier test plus repeated stress, actual source fix and full package/native validation separately.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
