# W-gdb-199c-in2tinct-17 - Exclude subtitle-shaped directories from discovery
state: OPEN / unclaimed
lab: in2tinct

## Product change
discover must not return directories named movie.srt/movie.en.ass. Keep existing regular-file discovery, case normalization, exact-before-tagged deterministic ordering and relative-path behavior. Use filesystem metadata, not extension-only guessing. Preserve existing symlink policy unless separately documented and tested.

## Grounded gap and boundary
U2 external subtitle import prerequisite. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-17.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-17",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVSubtitles/SubtitleAutoLoad.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "discover must not return directories named movie.srt/movie.en.ass. Keep existing regular-file discovery, case normalization, exact-before-tagged deterministic ordering and relative-path behavior. Use filesystem metadata, not extension-only guessing. Preserve existing symlink policy unless separately documented and tested.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 external subtitle import prerequisite",
    "callee": "Sources/GorAVSubtitles/SubtitleAutoLoad.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-17.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-17",
    "paths": [
      "Sources/GorAVSubtitles/SubtitleAutoLoad.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-17.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-17.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-17.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:48.670700+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "f154da5078d1b3cce7541278829f71275c377d095ba084317cf42894b02dee91",
    "last_5_lines": [
      "semantic_exit=1",
      "FAIL only actual file discovered",
      "semantic failures=1",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVSubtitles/SubtitleAutoLoad.swift",
        "block": "source1",
        "sha256": "bdf2a96b5fd4b1a09f7a7cd269304d8dcff479215cd7e75d360f1e8e8d4f36e0",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-17.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-17.json",
        "block": "fixtures2",
        "sha256": "3376a9cbd7c97257481a68a17a796cc810d867f743404c6d8cccf531e01e51d4"
      }
    ],
    "receipt_sha256": "91dcb20513a29ea3d1aa9d2b8b08d8c2dc177e6c2bcff988afa4da320d3a9e32"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

/// R7 (arch-195b): external subtitle auto-load discovery. Given a playing
/// video's local path, finds sibling sidecar files: exact-basename matches
/// (movie.srt next to movie.mp4) and language-tagged matches (movie.en.srt).
/// Deterministic order: exact basename first, then tagged matches sorted by
/// tag. Unknown extensions are never returned (they fail at load time as
/// typed refusals via SubtitleTrack.load). Discovery only; no parsing here.
public enum SubtitleAutoLoad {

    public static let extensions: Set<String> = ["srt", "ass", "ssa"]

    public struct Candidate: Equatable, Sendable {
        public let path: String
        /// nil for an exact-basename match; otherwise the tag between the
        /// video basename and the extension (usually a language code).
        public let tag: String?
        public let format: String
        public init(path: String, tag: String?, format: String) {
            self.path = path
            self.tag = tag
            self.format = format
        }
    }

    /// Deterministic candidates for `videoPath`. Returns [] when the video
    /// path has no usable basename or the directory cannot be listed; an
    /// empty result is a fact (no sidecars), never an error.
    public static func discover(forVideoPath videoPath: String) -> [Candidate] {
        let ns = videoPath as NSString
        let dir = ns.deletingLastPathComponent
        let base = ns.deletingPathExtension as NSString
        let baseName = base.lastPathComponent
        guard !baseName.isEmpty else { return [] }
        let listDir = dir.isEmpty ? "." : dir
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: listDir) else { return [] }
        var exact: [Candidate] = []
        var tagged: [Candidate] = []
        for entry in entries {
            let e = entry as NSString
            let ext = e.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }
            let nameNoExt = e.deletingPathExtension
            let full = listDir == "." ? entry : (listDir as NSString).appendingPathComponent(entry)
            let format = ext == "ssa" ? "ass" : ext
            if nameNoExt == baseName {
                exact.append(Candidate(path: full, tag: nil, format: format))
            } else if nameNoExt.hasPrefix(baseName + ".") {
                let tag = String(nameNoExt.dropFirst(baseName.count + 1))
                guard !tag.isEmpty else { continue }
                tagged.append(Candidate(path: full, tag: tag, format: format))
            }
        }
        return exact.sorted { $0.path < $1.path } + tagged.sorted { $0.path < $1.path }
    }
}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[3]
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
    "Sources/GorAVSubtitles/SubtitleAutoLoad.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)\ntry FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)\ndefer { try? FileManager.default.removeItem(at: root) }\ntry FileManager.default.createDirectory(at: root.appendingPathComponent(\"movie.srt\"),withIntermediateDirectories: true)\ntry Data(\"x\".utf8).write(to: root.appendingPathComponent(\"movie.en.ass\"))\nlet found=SubtitleAutoLoad.discover(forVideoPath: root.appendingPathComponent(\"movie.mp4\").path)\ncheck(found.count == 1 && found.first?.tag == \"en\" && found.first?.format == \"ass\",\"only actual file discovered\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL only actual file discovered
semantic failures=1



```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
