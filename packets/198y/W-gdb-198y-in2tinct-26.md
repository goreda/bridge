# W-gdb-198y-in2tinct-26
state: OPEN / unclaimed
lab: in2tinct

Build a new source-contract false-positive regression test for the exact file, independently from the prior fragment tests. Preserve source-pin evidence separately. Mask Swift comments and string literals before named declaration assertions. Add at least two real declaration signature/value boundary assertions and three mutation controls including comment-only decoy, string-only decoy, and renamed/removed declaration. Do not allow a comment/string containing an expected fragment to satisfy its declaration. Use explicit failures under python3 -O and execute normal/optimized positive plus on-disk external negative/restore controls. This remains source characterization, never Swift semantics or runtime.

Allowed return path: Tests/Architecture/198y/W-gdb-198y-in2tinct-26.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-in2tinct-26",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/TapCropDetector.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at Tests/Architecture/198y/W-gdb-198y-in2tinct-26.py checks Sources/GorAVPlaybackCore/TapCropDetector.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: LumaPlane, BorderScanConfig, TapCropDetector, scan, detect, isBarRow, isBarColumn, CropDetectionPump, Counters, agrees",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-26.py",
    "callee": "Sources/GorAVPlaybackCore/TapCropDetector.swift owning station GorAVPlaybackCore"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-26.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gorav",
    "paths": [
      "Tests/Architecture/198y/W-gdb-198y-in2tinct-26.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/198y/W-gdb-198y-in2tinct-26.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.295530+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/TapCropDetector.swift",
        "block": "source1",
        "sha256": "648d03d4fd0cdfff34cabd7f52e97e6c8282963b8ba2e6cab018ab6892423f53"
      },
      {
        "path": "Tests/Architecture/198y/W-gdb-198y-in2tinct-26.py",
        "block": "fixtures1",
        "sha256": "35978ed385610a2dd0cc86675bf4ce6fbc57d13345d2e86a66cbed66e82a2a91"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "a555232d24ba72de6ba79ce1258034cce330e013ab0a22e441b6114ad9a5382f",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-in2tinct-26: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "96d18a2ded5d4b70cd9eb35731f41e12673971baad3e25544546e20be545844e"
  }
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
import hashlib
ROOT=Path(__file__).resolve().parents[3]
p=ROOT/'Sources/GorAVPlaybackCore/TapCropDetector.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='648d03d4fd0cdfff34cabd7f52e97e6c8282963b8ba2e6cab018ab6892423f53', 'pinned source changed: rebase and review, never bless silently'
for token in ['LumaPlane', 'BorderScanConfig', 'TapCropDetector', 'scan', 'detect', 'isBarRow', 'isBarColumn', 'CropDetectionPump', 'Counters', 'agrees']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='648d03d4fd0cdfff34cabd7f52e97e6c8282963b8ba2e6cab018ab6892423f53'
print('CHARACTERIZATION_PASS W-gdb-198y-in2tinct-26: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-in2tinct-26: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
