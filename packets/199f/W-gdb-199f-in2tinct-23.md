# W-gdb-199f-in2tinct-23 - Overflow-safe crop frame stride admission
state: OPEN / unclaimed

CLASSIFICATION: SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed.
lab: in2tinct

LabCropFrame.init must use checked stride-times-row-count plus row-width arithmetic before comparing plane count. Overflow returns nil, never traps. Keep existing format/dimension bounds and valid padded stride behavior. This is a source-only additive lab crop model, not the live TapCropDetector adapter. No runtime binding claimed.

All listed production files compile in full; dependencies are read-only, not edit leases.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-in2tinct-23",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/LabCropEngine.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "LabCropFrame.init must use checked stride-times-row-count plus row-width arithmetic before comparing plane count. Overflow returns nil, never traps. Keep existing format/dimension bounds and valid padded stride behavior. This is a source-only additive lab crop model, not the live TapCropDetector adapter. No runtime binding claimed.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed.",
    "callee": "Sources/GorAVPlaybackCore/LabCropEngine.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-23.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199f-in2tinct-23",
    "paths": [
      "Sources/GorAVPlaybackCore/LabCropEngine.swift",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-23.py",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-23.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-23.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/LabCropEngine.swift",
        "block": "source1",
        "sha256": "3d55228042fe10505de07b52537a4ca4b7863393f31713ec228de222c95bba7e",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-23.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-23.json",
        "block": "fixtures2",
        "sha256": "114e4f92b7781285c3b04e687e124c3b92918b169993cb21bf8f1d2bfe92f840"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "d458b4d1733b057a9d47dd352e17d02a5ba6de2472d4597890ba6b55d3d153a8",
    "last_5_lines": [
      "0x000056383938f000\u20130x000056383939af90 <no build ID> test /tmp/tmpy1c97hla/test",
      "",
      "Backtrace took 0.00s",
      "",
      ""
    ]
  },
  "classification": "SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed."
}
```

```swift id=source1
// Lab crop engine (G0736 / 195b-N10, lab: 1nstinct): multi-pixfmt luma
// extraction + temporal stabilizer, additive consumer seam behind the pinned
// TapCropDetector surface. Ported line-faithful from kits/n10-cropdetect
// (cropdetect.c, C99); the C reference with its own test suite stays vendored
// in kits/n10-cropdetect and is the executable witness. The pinned
// TapCropDetector/BorderScanConfig semantics are NOT changed by this file.
// Threshold mapping into the pinned surface: barMaxLuma <-> blackThreshold,
// sampleStride <-> sampleStep; the pinned mean/peak scan stays the acceptance
// vocabulary (W-gdb-045).

/// Pixel layouts the engine can sample luma from.
public enum LabCropPixelFormat: String, Equatable, Sendable {
    case gray8, yuv420p, nv12, rgb24, rgba, bgra
}

/// Video range of the incoming samples.
public enum LabCropRange: String, Equatable, Sendable {
    case limited, full
}

/// Engine parameters. Mirrors cd_params; validated by `isValid` (the C pbad
/// rule). Defaults follow the lab kit, not the pinned BorderScanConfig.
public struct LabCropParams: Equatable, Sendable {
    public var blackThreshold = 16        // luma (full-range units) <= this is black
    public var noisePixelsPctX100 = 50    // a line is content when bright pixels exceed this share (1/100 %)
    public var noisePixelsMin = 2         // ... and at least this many pixels
    public var align = 2                  // round rect outward to this multiple
    public var minW = 16, minH = 16       // smallest accepted crop
    public var histLen = 8                // stabilizer window in frames (<=64)
    public var shrinkHold = 8             // frames a tighter crop must persist
    public var sampleStep = 1             // examine every Nth line
    public init() {}
    public var isValid: Bool {
        blackThreshold >= 0 && blackThreshold <= 255 && align >= 1 && align <= 64
            && histLen >= 1 && histLen <= 64 && sampleStep >= 1
            && minW >= 1 && minH >= 1 && shrinkHold >= 0 && noisePixelsMin >= 0
            && noisePixelsPctX100 >= 0 && noisePixelsPctX100 <= 10000
    }
}

/// One frame for detection: plane pointers as byte arrays + byte strides.
/// Plane 0 is luma or packed; NV12 uses plane 1 for chroma (never read).
public struct LabCropFrame: Sendable {
    public let planes: [[UInt8]]
    public let strides: [Int]
    public let width: Int
    public let height: Int
    public let format: LabCropPixelFormat
    public let range: LabCropRange
    public static let maxDim = 32768
    public init?(planes: [[UInt8]], strides: [Int], width: Int, height: Int,
                 format: LabCropPixelFormat, range: LabCropRange) {
        guard !planes.isEmpty, strides.count >= planes.count,
              width > 0, height > 0, width <= Self.maxDim, height <= Self.maxDim
        else { return nil }
        let bpp = format == .rgb24 ? 3 : (format == .rgba || format == .bgra ? 4 : 1)
        guard strides[0] >= width * bpp else { return nil }
        // Every row the sampler can touch must be inside plane 0.
        guard planes[0].count >= strides[0] * (height - 1) + width * bpp else { return nil }
        self.planes = planes; self.strides = strides
        self.width = width; self.height = height
        self.format = format; self.range = range
    }
}

/// Pixel-space rectangle, same convention as the C cd_rect.
public struct LabCropRect: Equatable, Sendable {
    public var x = 0, y = 0, w = 0, h = 0
    public init() {}
    public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
    public func contains(_ o: LabCropRect) -> Bool {
        x <= o.x && y <= o.y && x + w >= o.x + o.w && y + h >= o.y + o.h
    }
    public func union(_ o: LabCropRect) -> LabCropRect {
        let x0 = min(x, o.x), y0 = min(y, o.y)
        let x1 = max(x + w, o.x + o.w), y1 = max(y + h, o.y + o.h)
        return LabCropRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }
}

/// Per-frame result: raw detection + stabilized rect.
public struct LabCropResult: Equatable, Sendable {
    public var detected = LabCropRect()
    public var stable = LabCropRect()
    public var detectedValid = false   // false on an all-black/blank frame: detected = full frame, history unchanged
    public var stableChanged = false
    public init() {}
}

public enum LabCropEngine {
    /// BT.709 integer luma in full-range units at (x, y). Bounds are the
    /// caller's guarantee (the failable frame init enforces them).
    public static func luma(_ f: LabCropFrame, x: Int, y: Int) -> Int {
        let p0 = f.planes[0]
        let base = y * f.strides[0]
        switch f.format {
        case .gray8, .yuv420p, .nv12:
            var v = Int(p0[base + x])
            if f.range == .limited {
                v = (v - 16) * 255 / 219
                if v < 0 { v = 0 }; if v > 255 { v = 255 }
            }
            return v
        case .rgb24:
            let q = base + 3 * x
            return (54 * Int(p0[q]) + 183 * Int(p0[q + 1]) + 19 * Int(p0[q + 2]) + 128) >> 8
        case .rgba:
            let q = base + 4 * x
            return (54 * Int(p0[q]) + 183 * Int(p0[q + 1]) + 19 * Int(p0[q + 2]) + 128) >> 8
        case .bgra:
            let q = base + 4 * x
            return (54 * Int(p0[q + 2]) + 183 * Int(p0[q + 1]) + 19 * Int(p0[q]) + 128) >> 8
        }
    }

    static func isContent(_ count: Int, total: Int, _ p: LabCropParams) -> Bool {
        if count < p.noisePixelsMin || count == 0 { return false }
        return count * 10000 > p.noisePixelsPctX100 * total || p.noisePixelsPctX100 == 0
    }

    /// Stateless per-frame detection. nil on invalid input; otherwise the
    /// content rect plus a validity flag (blank frame -> full frame, false).
    public static func detect(_ f: LabCropFrame, params pp: LabCropParams = LabCropParams())
        -> (rect: LabCropRect, valid: Bool)? {
        guard pp.isValid else { return nil }
        let W = f.width, H = f.height, s = pp.sampleStep, T = pp.blackThreshold
        var top = -1, bot = -1, left = W, right = -1
        var col = [Int](repeating: 0, count: W)
        var nrows = 0
        var y = 0
        while y < H {
            var cnt = 0
            nrows += 1
            var x = 0
            while x < W {
                if luma(f, x: x, y: y) > T { cnt += 1; col[x] += 1 }
                x += 1
            }
            if isContent(cnt, total: W, pp) { if top < 0 { top = y }; bot = y }
            y += s
        }
        var x = 0
        while x < W {
            if isContent(col[x], total: nrows, pp) { if x < left { left = x }; right = x }
            x += 1
        }
        if top < 0 || right < 0 {
            return (LabCropRect(x: 0, y: 0, w: W, h: H), false)
        }
        bot += s - 1
        if bot >= H { bot = H - 1 }
        let a = pp.align
        var x0 = left, y0 = top, x1 = right + 1, y1 = bot + 1
        x0 -= x0 % a; y0 -= y0 % a               // expand outward so content is never cut
        x1 = (x1 + a - 1) / a * a; y1 = (y1 + a - 1) / a * a
        if x1 > W { x1 = W }; if y1 > H { y1 = H }
        if x1 - x0 < pp.minW { x0 = 0; x1 = W }
        if y1 - y0 < pp.minH { y0 = 0; y1 = H }
        return (LabCropRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0), true)
    }
}

/// Detect + temporal stabilizer (window union; grow at once; shrink only
/// after a tighter rect persists shrinkHold frames; geometry change or
/// reset() clears state). Value type: one engine per stream.
public struct LabCropStabilizer: Sendable {
    public private(set) var params: LabCropParams
    private var hist = [LabCropRect](repeating: LabCropRect(), count: 64)
    private var n = 0, head = 0
    private var stable = LabCropRect()
    private var have = false
    private var shrinkCount = 0
    private var pend = LabCropRect()
    private var fw = 0, fh = 0

    public init?(params: LabCropParams = LabCropParams()) {
        guard params.isValid else { return nil }
        self.params = params
    }

    /// Call on seek / generation change / format change.
    public mutating func reset() {
        let p = params
        self = LabCropStabilizer(params: p)!
    }

    public mutating func process(_ f: LabCropFrame) -> LabCropResult? {
        if have && (f.width != fw || f.height != fh) { reset() }
        fw = f.width; fh = f.height
        guard let det = LabCropEngine.detect(f, params: params) else { return nil }
        let full = LabCropRect(x: 0, y: 0, w: f.width, h: f.height)
        let prev = have ? stable : full
        var res = LabCropResult()
        res.detected = det.rect
        res.detectedValid = det.valid
        if det.valid {
            hist[head] = det.rect
            head = (head + 1) % params.histLen
            if n < params.histLen { n += 1 }
            var u = hist[(head + params.histLen - 1) % params.histLen]
            var i = 0
            while i < n { u = u.union(hist[i]); i += 1 }   // window union: never cuts recent content
            if !have {
                stable = u; have = true; shrinkCount = 0
            } else if !stable.contains(u) {
                stable = stable.union(u); shrinkCount = 0  // grow at once
            } else if stable != u {                        // shrink only if persistent
                if shrinkCount > 0 && pend == u { shrinkCount += 1 } else { pend = u; shrinkCount = 1 }
                if shrinkCount >= params.shrinkHold || params.shrinkHold == 0 { stable = u; shrinkCount = 0 }
            } else {
                shrinkCount = 0
            }
        }
        res.stable = have ? stable : full
        res.stableChanged = res.stable != prev
        return res
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
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith(('ArchiveLibrary.swift','TorrentManager.swift')) else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith(('ArchiveLibrary.swift','TorrentManager.swift')):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "Sources/GorAVPlaybackCore/LabCropEngine.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\ncheck(LabCropFrame(planes:[[0]],strides:[Int.max],width:1,height:2,format:.gray8,range:.full) == nil,\"overflow stride refused\")\ncheck(LabCropFrame(planes:[[0,0,0,0]],strides:[2],width:2,height:2,format:.gray8,range:.full) != nil,\"normal frame retained\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=-4

*** Signal 4: Backtracing from 0x563839394fdf... done ***

*** Program crashed: Illegal instruction at 0x0000563839394fdf ***

Thread 0 "test" crashed:

0 [thunk] 0x0000563839394fdf LabCropFrame.init(planes:strides:width:height:format:range:) + 1647 in test
1 [ra]    0x0000563839398fee main + 221 in test


Registers:

rax 0x8000000000000001  9223372036854775809
rdx 0x0000000000000000  0
rcx 0x0000000000000001  1
rbx 0x0000000000000003  3
rsi 0x0000000000000000  0
rdi 0x000056383ca00fb0  68 38 fa a2 10 7f 00 00 03 00 00 00 00 00 00 00  h8ú¢············
rbp 0x00007ffca2eecd60  90 ce ee a2 fc 7f 00 00 ee 8f 39 39 38 56 00 00  ·Îî¢ü···î·998V··
rsp 0x00007ffca2eecbe0  01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ················
 r8 0x00007f10a2e45fe0  55 48 89 e5 41 56 53 48 89 fb 4c 8b 36 4c 89 f7  UH·åAVSH·ûL·6L·÷
 r9 0x0000000000000027  39
r10 0x00007f10a31f85b0  ed c3 00 00 12 03 0c 00 e0 4e 03 00 00 00 00 00  íÃ······àN······
r11 0x00007f10a3227ee0  55 48 89 e5 5d e9 26 bb ff ff 66 0f 1f 44 00 00  UH·å]é&»ÿÿf··D··
r12 0x00007ffca2eecfa8  30 ec ee a2 fc 7f 00 00 00 00 00 00 00 00 00 00  0ìî¢ü···········
r13 0x00007ffca2eeccf8  60 0d a0 3c 38 56 00 00 01 cd ee a2 fc 7f 00 00  `· <8V···Íî¢ü···
r14 0x000056383939c808  fc 24 fe a2 10 7f 00 00 a8 f0 fd a2 10 7f 00 00  ü$þ¢····¨ðý¢····
r15 0x00007f10a3272040  e0 32 27 a3 10 7f 00 00 15 00 00 00 00 00 00 00  à2'£············
rip 0x0000563839394fdf  0f 0b 66 66 66 66 66 66 2e 0f 1f 84 00 00 00 00  ··ffffff.·······

rflags 0x0000000000010202  

cs 0x0033  fs 0x0000  gs 0x0000


Images (19 omitted):

0x000056383938f000–0x000056383939af90 <no build ID> test /tmp/tmpy1c97hla/test

Backtrace took 0.00s



```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. SOURCE-ONLY/INERT FILLER: published but excluded from shipping pump stock pending route decision.
