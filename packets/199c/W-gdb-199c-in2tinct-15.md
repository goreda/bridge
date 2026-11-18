# W-gdb-199c-in2tinct-15 - Invalid crop config cannot clear a stable crop
state: OPEN / unclaimed
lab: in2tinct

## Product change
CropDetectionPump.poll must treat invalid BorderScanConfig as rejected input before changing hysteresis state or spending the poll clock. It must not reinterpret invalid config as a no-bars clear vote. Preserve valid no-bar clearing and rate limiting. Test-local DTO declarations below are exact read-only NormalizedRect/CropSuggestion source, not a detector mock.

## Grounded gap and boundary
U2 crop detection pipeline prerequisite. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-15.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-15",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/TapCropDetector.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "CropDetectionPump.poll must treat invalid BorderScanConfig as rejected input before changing hysteresis state or spending the poll clock. It must not reinterpret invalid config as a no-bars clear vote. Preserve valid no-bar clearing and rate limiting. Test-local DTO declarations below are exact read-only NormalizedRect/CropSuggestion source, not a detector mock.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 crop detection pipeline prerequisite",
    "callee": "Sources/GorAVPlaybackCore/TapCropDetector.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-15.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-15",
    "paths": [
      "Sources/GorAVPlaybackCore/TapCropDetector.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-15.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-15.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-15.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:47.863994+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "69c8387f9753700f4c3ebde9c462e61b5ac8276145be72d1209f958dfd5460b1",
    "last_5_lines": [
      "FAIL invalid config preserves crop",
      "FAIL valid full frame clears",
      "semantic failures=3",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/TapCropDetector.swift",
        "block": "source1",
        "sha256": "648d03d4fd0cdfff34cabd7f52e97e6c8282963b8ba2e6cab018ab6892423f53",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-15.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-15.json",
        "block": "fixtures2",
        "sha256": "d17450524d3d09c5eff9cffc838ae32c1e053e88bf4a54d8241db7117c30bb8f"
      }
    ],
    "receipt_sha256": "ddeaab40cff8c95cd96bae50a755af953a930f55f7a794f14ab4790b8984d797"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
import Foundation

// R8 (arch-195l, dispatch L6): crop detection consuming the P27 frame tap.
// Reading recorded per dispatch: this is the letterbox/pillarbox analysis the
// CropDetecting seam reserved, fed by tapped frames (P27), so the engine's
// crop path reads decoded frames directly and no longer needs photon's
// screenshot reads (PLAN.md P27: "today these read mpv output or
// screenshots"). Pixel analysis here is pure value-type Swift over a luma
// plane: Linux-verifiable, no CoreVideo import; the Darwin CVPixelBuffer
// adapter lives in GorAVMacShell/TappedFrameLuma.swift.

/// Downsample-free view of one frame's luma. `strideBytes` may exceed `width`
/// (padded planes); bytes outside the width are never read.
public struct LumaPlane: Equatable, Sendable {
    public let bytes: [UInt8]
    public let width: Int
    public let height: Int
    public let strideBytes: Int
    public init?(bytes: [UInt8], width: Int, height: Int, strideBytes: Int) {
        guard width > 0, height > 0, strideBytes >= width else { return nil }
        let (lastRow, overflow) = strideBytes.multipliedReportingOverflow(by: height - 1)
        let (needed, overflow2) = lastRow.addingReportingOverflow(width)
        guard !overflow, !overflow2, bytes.count >= needed else { return nil }
        self.bytes = bytes; self.width = width; self.height = height
        self.strideBytes = strideBytes
    }
}

public struct BorderScanConfig: Equatable, Sendable {
    /// Inclusive mean-luma ceiling for a row/column to count as a black bar.
    public var barMaxLuma: Int = 16
    /// No sampled pixel inside a bar row/column may exceed this (letterbox
    /// bars with noise/logo residue stay bars; bright content does not).
    public var barMaxPeak: Int = 48
    /// Bars thinner than this are ignored (1px edge noise is not a bar).
    public var minBarPx: Int = 2
    /// Per-dimension cap: bar share beyond this means dark content, not bars.
    public var maxBarFraction: Double = 0.45
    /// The remaining inner region must keep at least this share per dimension.
    public var minRemainFraction: Double = 0.20
    /// Pixel sampling step inside one row/column scan. >= 1.
    public var sampleStride: Int = 8
    public init(barMaxLuma: Int = 16, barMaxPeak: Int = 48, minBarPx: Int = 2,
                maxBarFraction: Double = 0.45, minRemainFraction: Double = 0.20,
                sampleStride: Int = 8) {
        self.barMaxLuma = barMaxLuma; self.barMaxPeak = barMaxPeak
        self.minBarPx = minBarPx; self.maxBarFraction = maxBarFraction
        self.minRemainFraction = minRemainFraction; self.sampleStride = sampleStride
    }
    public var isValid: Bool {
        (0...255).contains(barMaxLuma) && (0...255).contains(barMaxPeak)
            && barMaxLuma <= barMaxPeak && minBarPx >= 1 && sampleStride >= 1
            && maxBarFraction.isFinite && maxBarFraction > 0 && maxBarFraction < 0.5
            && minRemainFraction.isFinite && minRemainFraction > 0 && minRemainFraction <= 1
    }
}

public enum TapCropDetector {
    /// Mean/peak of one row or column sampled every `step` pixels. Integer
    /// only; the caller guarantees the range is inside the plane.
    private static func scan(_ p: LumaPlane, horizontal: Bool, index: Int, step: Int)
        -> (mean: Int, peak: Int) {
        var sum = 0, peak = 0, n = 0
        if horizontal {
            let base = index * p.strideBytes
            var x = 0
            while x < p.width {
                let v = Int(p.bytes[base + x])
                sum += v; if v > peak { peak = v }; n += 1
                x += step
            }
        } else {
            var y = 0
            while y < p.height {
                let v = Int(p.bytes[y * p.strideBytes + index])
                sum += v; if v > peak { peak = v }; n += 1
                y += step
            }
        }
        return (n > 0 ? sum / n : 0, peak)
    }

    /// Detect letterbox/pillarbox bars. nil = no crop suggestion (no bars,
    /// dark frame, or a degenerate/over-aggressive result). Deterministic:
    /// same plane and config always give the same answer.
    public static func detect(_ p: LumaPlane, config: BorderScanConfig = BorderScanConfig())
        -> CropSuggestion? {
        guard config.isValid else { return nil }
        let step = config.sampleStride
        func isBarRow(_ y: Int) -> Bool {
            let s = scan(p, horizontal: true, index: y, step: step)
            return s.mean <= config.barMaxLuma && s.peak <= config.barMaxPeak
        }
        func isBarColumn(_ x: Int) -> Bool {
            let s = scan(p, horizontal: false, index: x, step: step)
            return s.mean <= config.barMaxLuma && s.peak <= config.barMaxPeak
        }
        var top = 0
        while top < p.height, isBarRow(top) { top += 1 }
        var bottom = 0
        while bottom < p.height - top, isBarRow(p.height - 1 - bottom) { bottom += 1 }
        var left = 0
        while left < p.width, isBarColumn(left) { left += 1 }
        var right = 0
        while right < p.width - left, isBarColumn(p.width - 1 - right) { right += 1 }
        if top < config.minBarPx { top = 0 }
        if bottom < config.minBarPx { bottom = 0 }
        if left < config.minBarPx { left = 0 }
        if right < config.minBarPx { right = 0 }
        guard top + bottom + left + right > 0 else { return nil }
        // Fraction guards: refuse to read a dark scene as bars, and refuse
        // to leave a degenerate sliver.
        if Double(top + bottom) > config.maxBarFraction * Double(p.height) { return nil }
        if Double(left + right) > config.maxBarFraction * Double(p.width) { return nil }
        let innerW = p.width - left - right, innerH = p.height - top - bottom
        guard innerW >= 1, innerH >= 1 else { return nil }
        if Double(innerW) < config.minRemainFraction * Double(p.width) { return nil }
        if Double(innerH) < config.minRemainFraction * Double(p.height) { return nil }
        // Dark-frame guard: an inner region that is itself bar-dark is a dark
        // frame, not a crop.
        var sum = 0, n = 0
        var y = top
        while y < top + innerH {
            let s = scan(p, horizontal: true, index: y, step: step)
            sum += s.mean; n += 1
            y += max(1, innerH / 16)
        }
        if n > 0, sum / n <= config.barMaxLuma { return nil }
        guard let rect = NormalizedRect(x: Double(left) / Double(p.width),
                                        y: Double(top) / Double(p.height),
                                        w: Double(innerW) / Double(p.width),
                                        h: Double(innerH) / Double(p.height)) else { return nil }
        // Confidence from bar cleanliness: cleaner bars (lower peak) score
        // higher, floored so a noisy-but-real bar still crosses a 0.5 gate.
        var worstPeak = 0
        if top > 0 { worstPeak = max(worstPeak, scan(p, horizontal: true, index: top - 1, step: step).peak) }
        if left > 0 { worstPeak = max(worstPeak, scan(p, horizontal: false, index: left - 1, step: step).peak) }
        let confidence = min(1.0, max(0.5, 1.0 - Double(worstPeak) / 510.0))
        return CropSuggestion(rect: rect, confidence: confidence)
    }
}

/// Rate-limited, hysteresis-filtered pump from tapped frames to crop
/// suggestions. A suggestion is emitted only after `requiredAgreement`
/// consecutive agreeing detections; bars that vanish for `requiredAgreement`
/// consecutive frames emit a `.full` suggestion (auto-clear). No-bar frames
/// never clear sooner than that: one bright full-frame scene must not undo a
/// stable crop. Every suppression is counter-visible; nothing is silent.
public struct CropDetectionPump: Sendable {
    public struct Counters: Equatable, Sendable {
        public var polls = 0
        public var framesSeen = 0
        public var detections = 0
        public var emitted = 0
        public var emittedClears = 0
        public var suppressedRate = 0
        public var suppressedUnstable = 0
        public init() {}
    }
    public private(set) var counters = Counters()
    public let minInterval: Double
    public let requiredAgreement: Int
    /// Per-component normalized tolerance for "same rect as last time".
    public let tolerance: Double
    private var lastPollClock: Double?
    private var pending: CropSuggestion?
    private var pendingCount = 0
    private var clearCount = 0
    /// Last emitted suggestion; nil until the first stable detection.
    public private(set) var lastEmitted: CropSuggestion?

    public init?(minInterval: Double = 1.0, requiredAgreement: Int = 3, tolerance: Double = 0.01) {
        guard minInterval.isFinite, minInterval >= 0, requiredAgreement >= 1,
              tolerance.isFinite, tolerance > 0, tolerance < 1 else { return nil }
        self.minInterval = minInterval
        self.requiredAgreement = requiredAgreement
        self.tolerance = tolerance
    }

    private func agrees(_ a: NormalizedRect, _ b: NormalizedRect) -> Bool {
        abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
            && abs(a.w - b.w) <= tolerance && abs(a.h - b.h) <= tolerance
    }

    /// One poll tick. `clock` is seconds (any monotonic source). `plane` nil
    /// means the tap had no frame this tick: counted as a poll but neither a
    /// detection nor a clear vote, and it does not disturb pending stability.
    @discardableResult
    public mutating func poll(clock: Double, plane: LumaPlane?,
                              config: BorderScanConfig = BorderScanConfig()) -> CropSuggestion? {
        counters.polls += 1
        guard clock.isFinite else { counters.suppressedRate += 1; return nil }
        if let last = lastPollClock, clock - last < minInterval {
            counters.suppressedRate += 1
            return nil
        }
        lastPollClock = clock
        guard let plane else { return nil }
        counters.framesSeen += 1
        guard let suggestion = TapCropDetector.detect(plane, config: config) else {
            // No bars on this frame: one clear vote. Pending detection is
            // dropped; clearing needs its own agreement run.
            pending = nil; pendingCount = 0
            clearCount += 1
            if clearCount >= requiredAgreement,
               let last = lastEmitted, !agrees(last.rect, .full) {
                let clear = CropSuggestion(rect: .full, confidence: 0.6)!
                lastEmitted = clear
                clearCount = 0
                counters.emitted += 1
                counters.emittedClears += 1
                return clear
            }
            if clearCount >= requiredAgreement { clearCount = 0 }
            counters.suppressedUnstable += 1
            return nil
        }
        counters.detections += 1
        clearCount = 0
        if let p = pending, agrees(p.rect, suggestion.rect) {
            pendingCount += 1
        } else {
            pending = suggestion
            pendingCount = 1
        }
        guard pendingCount >= requiredAgreement else {
            counters.suppressedUnstable += 1
            return nil
        }
        if let last = lastEmitted, agrees(last.rect, suggestion.rect) { return nil }
        lastEmitted = suggestion
        counters.emitted += 1
        return suggestion
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
    "Sources/GorAVPlaybackCore/TapCropDetector.swift"
  ],
  "test_source": "import Foundation\npublic struct NormalizedRect: Equatable, Sendable {\n    public let x: Double, y: Double, w: Double, h: Double\n    public init?(x: Double, y: Double, w: Double, h: Double) {\n        guard x.isFinite, y.isFinite, w.isFinite, h.isFinite, w > 0, h > 0,\n              x >= 0, y >= 0, x + w <= 1.0 + 1e-9, y + h <= 1.0 + 1e-9 else { return nil }\n        self.x = x; self.y = y; self.w = w; self.h = h\n    }\n    public static let full = NormalizedRect(x: 0, y: 0, w: 1, h: 1)!\n}\npublic struct CropSuggestion: Equatable, Sendable {\n    public let rect: NormalizedRect\n    public let confidence: Double\n    public init?(rect: NormalizedRect, confidence: Double) {\n        guard confidence.isFinite, confidence > 0, confidence <= 1 else { return nil }\n        self.rect = rect; self.confidence = confidence\n    }\n}\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nlet bytes = (0..<12).flatMap { y in (0..<12).map { _ in UInt8(y < 2 || y >= 10 ? 0 : 200) } }\nlet bars=LumaPlane(bytes: bytes,width: 12,height: 12,strideBytes: 12)!\nlet full=LumaPlane(bytes: Array(repeating: 200,count: 144),width: 12,height: 12,strideBytes: 12)!\nvar p=CropDetectionPump(minInterval: 0,requiredAgreement: 1)!\ncheck(p.poll(clock: 0,plane: bars,config: BorderScanConfig(sampleStride: 1)) != nil,\"stable crop established\")\nlet before=p.lastEmitted\ncheck(p.poll(clock: 1,plane: bars,config: BorderScanConfig(sampleStride: 0)) == nil,\"invalid config emits nothing\")\ncheck(p.lastEmitted == before,\"invalid config preserves crop\")\ncheck(p.poll(clock: 2,plane: full,config: BorderScanConfig(sampleStride: 1))?.rect == .full,\"valid full frame clears\")\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
PASS stable crop established
FAIL invalid config emits nothing
FAIL invalid config preserves crop
FAIL valid full frame clears
semantic failures=3



```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
