# W-gdb-199c-1nstinct-18 - Reject overflowing host-fit endpoints
state: OPEN / unclaimed
lab: 1nstinct

## Product change
GorAVHostRect.valid and GorAVHostFit.frame must reject geometry whose finite origin and dimensions produce nonfinite endpoints or fitted origin. Return nil for unrepresentable fits. Preserve normal host-fit sizing, motion springs and transform behavior. No host/window/UI writer edits.

## Grounded gap and boundary
U2 window-fit geometry prerequisite; S2 GorAVBackend. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-18.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery. BuildID is read-only compile support in A20: preserve later BuildID/launch-identity returns on rebase; no GorCore edit is leased.

```packet-json
{
  "packet_id": "W-gdb-199c-1nstinct-18",
  "lab": "1nstinct",
  "writer": "1nstinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/GorAVBackend/GorAVHostMotion.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "GorAVHostRect.valid and GorAVHostFit.frame must reject geometry whose finite origin and dimensions produce nonfinite endpoints or fitted origin. Return nil for unrepresentable fits. Preserve normal host-fit sizing, motion springs and transform behavior. No host/window/UI writer edits.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 window-fit geometry prerequisite; S2 GorAVBackend",
    "callee": "archive/gor/Sources/gor/GorAVBackend/GorAVHostMotion.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-18.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199c-1nstinct-18",
    "paths": [
      "archive/gor/Sources/gor/GorAVBackend/GorAVHostMotion.swift",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-18.py",
      "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-18.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-18.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:44:43.452427+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "5298cd861e241ebaa7b7b14bdba7a6494e87ce5ce2bef4655462c872b58c469e",
    "last_5_lines": [
      "PASS unrepresentable fit refused",
      "PASS normal fit retained",
      "semantic failures=1",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/GorAVBackend/GorAVHostMotion.swift",
        "block": "source1",
        "sha256": "74c7fe2edc868045d8903071a4000f466d17071402aed880d5eb6d3977d7ea19",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-18.py",
        "block": "fixtures1",
        "sha256": "a79d32b81b1e3dc4fcc869965c014fc34ad7303765052141d041925b9fbf51e4"
      },
      {
        "path": "archive/gor/Tests/Architecture/199c/W-gdb-199c-1nstinct-18.json",
        "block": "fixtures2",
        "sha256": "e28daf23bdba1faca6185cd4d8e36eee28ab390caaf2cfd3414aff30b585ebae"
      }
    ],
    "receipt_sha256": "387a9fbdda7dc9c4936df2ae0fb6ac34b2358e38382988f4edd59ef88181dc7b"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

// Ported from gor-fit.lua at d8b677b. Points throughout; no mpv properties or IPC.
struct GorAVHostRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var valid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}

struct GorAVHostTransform: Equatable {
    var panX = 0.0
    var panY = 0.0
    // Log2 zoom, matching video-zoom. Presenter scale is pow(2, zoom).
    var zoom = 0.0
}

struct GorAVHostFit {
    // Usable screen coordinates in AppKit's bottom-left origin.
    static func frame(videoWidth: Double, videoHeight: Double, usable: GorAVHostRect,
                      chromeWidth: Double = 0, chromeTop: Double = 0) -> GorAVHostRect? {
        guard usable.valid, videoWidth.isFinite, videoHeight.isFinite,
              videoWidth > 0, videoHeight > 0, chromeWidth.isFinite, chromeTop.isFinite,
              chromeWidth >= 0, chromeTop >= 0 else { return nil }
        let pw: Double, ph: Double
        if videoWidth >= videoHeight {
            pw = max(1, floor(usable.width * 0.4 * max(1, sqrt(videoWidth / 1280))))
            ph = max(1, floor(pw * videoHeight / videoWidth))
        } else {
            ph = max(1, floor(usable.height * 0.9))
            pw = max(1, floor(ph * videoWidth / videoHeight))
        }
        var w = pw + chromeWidth, h = ph + chromeTop
        let scale = min(1, min(floor(usable.width) / w, floor(usable.height) / h))
        w = floor(w * scale); h = floor(h * scale)
        guard w.isFinite, h.isFinite, w >= 160, h >= 90,
              w > chromeWidth, h > chromeTop else { return nil }
        return GorAVHostRect(x: usable.x + floor((usable.width - w) / 2),
                             y: usable.y + floor((usable.height - h) / 2), width: w, height: h)
    }
}

private struct HostSpring {
    var value: Double
    var velocity = 0.0
    var target: Double
    var omega: Double
    var epsilon: Double
    var moving: Bool { value != target || velocity != 0 }
    mutating func retarget(_ next: Double) {
        guard next.isFinite else { return }
        target = next
        let d = value - target
        if d > 0 { velocity = max(velocity, -omega * d) }
        else if d < 0 { velocity = min(velocity, -omega * d) }
        else { velocity = 0 }
    }
    mutating func step(_ dt: Double) {
        let d = value - target, b = velocity + omega * d, e = exp(-omega * dt)
        let nd = (d + b * dt) * e
        velocity = (velocity - omega * b * dt) * e
        value = target + nd
        if abs(nd) < epsilon && abs(velocity) < epsilon * (omega == 16 ? 12 : 8) {
            value = target; velocity = 0
        }
    }
}

// Value state is testable without AppKit. The host supplies one monotonic clock.
struct GorAVHostMotion {
    private var frameSprings: [HostSpring] = []
    private var picture: [HostSpring] = [
        HostSpring(value: 0, target: 0, omega: 20, epsilon: 0.0005),
        HostSpring(value: 0, target: 0, omega: 20, epsilon: 0.0005),
        HostSpring(value: 0, target: 0, omega: 20, epsilon: 0.003)]
    private var holdVelocity = [0.0, 0, 0]
    private var directions = [0.0, 0, 0]
    private var holdAt: Double?
    private var lastTime: Double?
    private var suspendedZoom: Double?
    private(set) var isPiP = false
    var transform: GorAVHostTransform {
        GorAVHostTransform(panX: picture[0].value, panY: picture[1].value, zoom: picture[2].value)
    }
    var frame: GorAVHostRect? {
        guard frameSprings.count == 4 else { return nil }
        let p = frameSprings.map { $0.value }
        return GorAVHostRect(x: p[0], y: p[1], width: p[2], height: p[3])
    }
    var frameMoving: Bool { frameSprings.contains { $0.moving } }
    var busy: Bool { frameMoving || picture.contains { $0.moving } ||
        directions.contains { $0 != 0 } || holdVelocity.contains { $0 != 0 } }

    mutating func animateFrame(from: GorAVHostRect, to: GorAVHostRect) {
        guard from.valid, to.valid else { return }
        let a = [from.x, from.y, from.width, from.height]
        let b = [to.x, to.y, to.width, to.height]
        if frameSprings.isEmpty { frameSprings = a.map { HostSpring(value: $0, target: $0, omega: 16, epsilon: 0.5) } }
        for i in 0..<4 { frameSprings[i].retarget(b[i]) }
    }
    mutating func cancelFrame() { frameSprings.removeAll() }
    mutating func adopt(_ value: GorAVHostTransform) {
        guard [value.panX, value.panY, value.zoom].allSatisfy(\.isFinite) else { return }
        let a = [value.panX, value.panY, isPiP ? max(0, value.zoom) : value.zoom]
        for i in 0..<3 { picture[i].value = a[i]; picture[i].target = a[i]; picture[i].velocity = 0 }
        holdVelocity = [0, 0, 0]; directions = [0, 0, 0]; holdAt = nil
    }
    mutating func nudge(dx: Double = 0, dy: Double = 0, dz: Double = 0) {
        guard [dx, dy, dz].allSatisfy(\.isFinite) else { return }
        releaseHold(immediate: true)
        for (i, delta) in [dx * 0.05, dy * 0.05, dz * 0.1].enumerated() where delta != 0 {
            let lead = i == 2 ? 0.15 : 0.075
            var target = min(picture[i].value + lead, max(picture[i].value - lead, picture[i].target + delta))
            if i == 2 && isPiP { target = max(0, target) }
            picture[i].retarget(target)
        }
    }
    mutating func hold(dx: Double, dy: Double, dz: Double, now: Double) {
        guard now.isFinite, [dx, dy, dz].allSatisfy(\.isFinite),
              lastTime == nil || now >= lastTime!, holdAt == nil || now >= holdAt! else { return }
        directions = [dx, dy, dz].map { max(-1, min(1, $0)) }; holdAt = now
        if directions.contains(where: { $0 != 0 }) {
            for i in 0..<3 { picture[i].target = picture[i].value; picture[i].velocity = 0 }
        }
    }
    mutating func releaseHold(immediate: Bool = false) {
        directions = [0, 0, 0]; holdAt = nil
        if immediate { holdVelocity = [0, 0, 0] }
    }
    mutating func reset() {
        suspendedZoom = nil; releaseHold(immediate: true)
        for i in 0..<3 { picture[i].retarget(0) }
    }
    mutating func setPiP(_ active: Bool) {
        guard active != isPiP else { return }
        isPiP = active
        if active {
            suspendedZoom = picture[2].target
            setZoomImmediately(max(0, suspendedZoom!))
        } else if let saved = suspendedZoom {
            setZoomImmediately(saved); suspendedZoom = nil
        }
    }
    // Source replacement keeps the owner's frame but never inherits suspended old-file zoom.
    mutating func newPlayback() {
        suspendedZoom = nil; releaseHold(immediate: true)
        picture[2].target = picture[2].value; picture[2].velocity = 0
        if isPiP { suspendedZoom = picture[2].value; setZoomImmediately(max(0, picture[2].value)) }
    }
    private mutating func setZoomImmediately(_ value: Double) {
        picture[2].value = value; picture[2].target = value; picture[2].velocity = 0
        holdVelocity[2] = 0; directions[2] = 0
    }
    mutating func tick(now: Double) {
        guard now.isFinite else { return }
        guard let previous = lastTime else { lastTime = now; return }
        guard now >= previous else { return }
        lastTime = now
        let dt = min(0.05, now - previous)
        for i in frameSprings.indices { frameSprings[i].step(dt) }
        if holdAt == nil || now - holdAt! > 0.6 { directions = [0, 0, 0] }
        let k = 1 - exp(-dt / 0.045)
        for i in 0..<3 {
            if directions[i] != 0 || holdVelocity[i] != 0 {
                holdVelocity[i] += (directions[i] * (i == 2 ? 1 : 0.6) - holdVelocity[i]) * k
                if directions[i] == 0 && abs(holdVelocity[i]) < picture[i].epsilon * 4 { holdVelocity[i] = 0 }
                let lo = i == 2 ? (isPiP ? 0.0 : -1.0) : -1.5, hi = i == 2 ? 4.0 : 1.5
                let next = picture[i].value + holdVelocity[i] * dt
                picture[i].value = max(lo, min(hi, next))
                if next < lo || next > hi { holdVelocity[i] = 0 }
                picture[i].target = picture[i].value; picture[i].velocity = 0
            } else { picture[i].step(dt) }
        }
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
    "archive/gor/Sources/gor/GorAVBackend/GorAVHostMotion.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet m=Double.greatestFiniteMagnitude\nlet bad=GorAVHostRect(x:m,y:0,width:m,height:1000)\ncheck(!bad.valid,\"overflow endpoint rectangle refused\")\ncheck(GorAVHostFit.frame(videoWidth:1920,videoHeight:1080,usable:bad) == nil,\"unrepresentable fit refused\")\nlet normal=GorAVHostFit.frame(videoWidth:1920,videoHeight:1080,usable:GorAVHostRect(x:0,y:0,width:1920,height:1080))\ncheck(normal?.valid == true,\"normal fit retained\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL overflow endpoint rectangle refused
PASS unrepresentable fit refused
PASS normal fit retained
semantic failures=1



```

Claim lease: 2h under existing earliest-claim workflow, refreshed only by verified progress. OPEN/unclaimed. Starter RED is not acceptance; own compiler rerun NOT_RUN.
