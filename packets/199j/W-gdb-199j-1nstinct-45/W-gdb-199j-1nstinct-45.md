# W-gdb-199j-1nstinct-45 - DZC depth-container parsing traps on corrupt index offsets and absurd plane dimensions

state: VERIFIED
lab: 1nstinct | product: goreda/instinct @ b60352dabc87fe8519832999b4af639f37d786f8 | scope: `archive/gor/Sources/gor/gor/ThreeD.swift`

## Goal
A corrupt or truncated .dzc cache container must be rejected (layout nil / scanValid break) so the pipeline re-prepares it, never crash the render pipeline.

## Caller scope
CALLER SCOPE: the 2D-to-3D prepare/render pipeline in the same file: DZCFile.isComplete gates container reuse at ThreeD.swift:3144, :4455, :4469, :5386, :6208; DZCFile(url:) opens containers at ThreeD.swift:3173, :4126, :9172; DZCWriter resume scans at ThreeD.swift:5722 via DZC.scanValid. Shipping callers in the same file.

## Extraction
Extracted enum DZC (header/index helpers), final class DZCWriter, final class DZCFile and enum DepthQuant verbatim from the pinned file. The lzfse codec is behind canImport(Compression) and compiles to a nil-returning stub on Linux; the test drives the container format directly through the same entry points the pipeline uses.
Comment lines carrying attribution or provenance identifiers elided from the packet source copy: 438 (trigger lines plus their continuation lines; string-aware, code untouched); sha256 below covers the elided copy.

## Verification (Swift 6.0.3, Linux)

- red_Onone: compile_exit=0 semantic_exit=-4 -> PASS
- red_O: compile_exit=0 semantic_exit=-4 -> PASS
- green_Onone: compile_exit=0 semantic_exit=0 -> PASS
- green_O: compile_exit=0 semantic_exit=0 -> PASS

Expected: pinned RED trap semantic_exit=-4, fixed GREEN exit=0.

## Fix
Two guards on untrusted container bytes. (1) Meta.planeBytes multiplies width*height*2 in UInt64 and yields 0 when the product exceeds UInt32, instead of trapping on absurd header dimensions. (2) DZCFile.layout validates each index offset fits Int before converting, instead of trapping on an entry >= 2^63.

## Classification
defensive malformed-input hardening (no live incident observed): containers are app-written cache files, but an interrupted write, a partial sync or an older build leaves bytes the completeness gate was designed to reject; the two narrowing conversions crash before the gate can reject.

## Not run
- Metal / GPU depth render NOT_RUN
- lzfse decompression NOT_RUN (Compression framework absent on Linux; codec stub returns nil)
- macOS app and prepare pipeline execution NOT_RUN

## Reproduce
```
cd W-gdb-199j-1nstinct-45
SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                  # pinned (source/): expect RED
GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py   # fixed: expect GREEN
SWIFTFLAGS=-O SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py                # pinned -O
SWIFTFLAGS=-O GOR_SOURCE_ROOT=$PWD/fixed SWIFTC=/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc python3 run_packet.py  # fixed -O
```

## packet-json
```json
{
  "packet_id": "W-gdb-199j-1nstinct-45",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "archive/gor/Sources/gor/gor/ThreeD.swift",
  "touched_files": [
    "archive/gor/Sources/gor/gor/ThreeD.swift"
  ],
  "interface": {
    "signatures": [
      "static func isComplete(_ url: URL) -> Bool",
      "init?(url: URL)",
      "static func scanValid(_ f: [UInt8], decompress: ([UInt8], Int) -> [UInt8]?) -> (frames: Int, end: Int, meta: DZC.Meta)?"
    ],
    "ownership_lifetime": "DZCFile holds an immutable Data snapshot; value-type helpers",
    "caller": "ThreeD.swift:3144/:4455/:5386/:6208 readiness gates, :3173/:4126/:9172 plane reads, :5722 resume",
    "callee": "Foundation Data/FileHandle; codec closure"
  },
  "test": {
    "command": "SWIFTC=$SWIFTC python3 run_packet.py (GOR_SOURCE_ROOT selects source/ vs fixed/; SWIFTFLAGS=-O for optimized runs)",
    "fixture_block": "fixtures1.json",
    "config_block": "fixtures2.json",
    "expected": "pinned RED trap semantic_exit=-4, fixed GREEN exit=0"
  },
  "target": {
    "branch": "host",
    "paths": [
      "archive/gor/Sources/gor/gor/ThreeD.swift"
    ],
    "return_form": "unified diff + fixed full copy"
  },
  "run_proof": {
    "version": 1,
    "kind": "swiftc two-variant compile+run",
    "inline_files": [
      "run_packet.py",
      "fixtures1.json",
      "fixtures2.json"
    ],
    "log_block": "actual_run_log.txt",
    "verification": {
      "red_Onone": {
        "compile_exit": 0,
        "semantic_exit": -4,
        "pass": true
      },
      "red_O": {
        "compile_exit": 0,
        "semantic_exit": -4,
        "pass": true
      },
      "green_Onone": {
        "compile_exit": 0,
        "semantic_exit": 0,
        "pass": true
      },
      "green_O": {
        "compile_exit": 0,
        "semantic_exit": 0,
        "pass": true
      }
    }
  },
  "state": "VERIFIED",
  "classification": "defensive malformed-input hardening (no live incident observed): containers are app-written cache files, but an interrupted write, a partial sync or an older build leaves bytes the completeness gate was designed to reject; the two narrowing conversions crash before the gate can reject."
}
```

## extracted swift (fixed)
```swift
enum ThreeDDegradeProbe { static func noteWriteError(_ e: Error) {} }
enum DZC {
    static let magic = Array("GORDZ001".utf8), trailer = Array("GORDZEND".utf8), headerSize = 64
    struct Meta: Equatable {
        var shot: UInt32, fpsNum: UInt32, fpsDen: UInt32, startFrame: UInt64
        var width: UInt32, height: UInt32, depthWidth: UInt32, depthHeight: UInt32, nFrames: UInt32
        var planeBytes: UInt32 { let p = UInt64(width) * UInt64(height) * 2; return p <= UInt64(UInt32.max) ? UInt32(p) : 0 }
    }
    static func fpsPair(_ fps: Double) -> (UInt32, UInt32) { fps == fps.rounded() ? (UInt32(fps), 1) : (UInt32((fps * 1000).rounded()), 1000) }

    private static let crcTable: [UInt32] = (0..<256).map { n in var c = UInt32(n); for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }; return c }
    static func crc32(_ d: [UInt8]) -> UInt32 { var c: UInt32 = 0xFFFFFFFF; for b in d { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }; return c ^ 0xFFFFFFFF }

    /// depth_container.quantise: z metres [h*w] -> edge-padded even plane of w10 (v = 256/z, w10 = clip(rint(v/1024*1023), 0, 1023); z <= 1e-3 or non-finite -> 0).
    static func quantise(z: [Float], h: Int, w: Int) -> (plane: [UInt16], width: Int, height: Int) {
        let wp = w + (w & 1), hp = h + (h & 1); var out = [UInt16](repeating: 0, count: wp * hp)
        for y in 0..<h { for x in 0..<w { out[y * wp + x] = DepthQuant.w10(zMetres: z[y * w + x]) } }
        if wp != w { for y in 0..<h { out[y * wp + w] = out[y * wp + w - 1] } }
        if hp != h { for x in 0..<wp { out[h * wp + x] = out[(h - 1) * wp + x] } }
        return (out, wp, hp)
    }
    static func le(_ v: UInt64, _ n: Int) -> [UInt8] {
        // 195y native#30 sweep: same one-line bitop closure shape as the unpack timeout; explicit loop, identical results.
        var out: [UInt8] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let shift: UInt64 = 8 * UInt64(i)
            out.append(UInt8((v >> shift) & 0xFF))
        }
        return out
    }
    static func rd(_ b: [UInt8], _ o: Int, _ n: Int) -> UInt64 {
        // 195y native#30 sweep: same one-line bitop closure shape as the unpack timeout; explicit loop, identical results.
        var acc: UInt64 = 0
        for i in 0..<n {
            let shift: UInt64 = 8 * UInt64(i)
            acc = acc | (UInt64(b[o + i]) << shift)
        }
        return acc
    }

    static func header(_ m: Meta) -> [UInt8] {
        var h = magic + le(1, 2) + le(1, 2) + le(0, 4) + le(UInt64(m.shot), 4) + le(UInt64(m.fpsNum), 4) + le(UInt64(m.fpsDen), 4) + le(m.startFrame, 8)
        h += le(UInt64(m.width), 4) + le(UInt64(m.height), 4) + le(UInt64(m.depthWidth), 4) + le(UInt64(m.depthHeight), 4) + le(UInt64(m.nFrames), 4) + le(UInt64(m.planeBytes), 4)
        return h + [UInt8](repeating: 0, count: headerSize - h.count)
    }
    static func parseHeader(_ b: [UInt8]) -> Meta? {
        guard b.count >= headerSize, Array(b[0..<8]) == magic, rd(b, 8, 2) == 1, rd(b, 10, 2) == 1 else { return nil }
        return Meta(shot: UInt32(rd(b, 16, 4)), fpsNum: UInt32(rd(b, 20, 4)), fpsDen: UInt32(rd(b, 24, 4)), startFrame: rd(b, 28, 8), width: UInt32(rd(b, 36, 4)),
                    height: UInt32(rd(b, 40, 4)), depthWidth: UInt32(rd(b, 44, 4)), depthHeight: UInt32(rd(b, 48, 4)), nFrames: UInt32(rd(b, 52, 4)))
    }
    static func record(planeLE: [UInt8], compressed: [UInt8]) -> [UInt8] { le(UInt64(compressed.count), 4) + le(UInt64(crc32(planeLE)), 4) + compressed }
    static func tail(offsets: [UInt64]) -> [UInt8] { offsets.flatMap { le($0, 8) } + trailer }
    static func planeBytesLE(_ p: [UInt16]) -> [UInt8] { p.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }

    /// Leading frames whose record parses, decompresses to plane_bytes and matches its crc; also returns the byte offset after the last valid record.
    static func scanValid(_ f: [UInt8], decompress: ([UInt8], Int) -> [UInt8]?) -> (frames: Int, end: Int, meta: Meta)? {
        guard let m = parseHeader(f) else { return nil }
        var o = headerSize, n = 0
        while o + 8 <= f.count {
            let len = Int(rd(f, o, 4)), crc = UInt32(rd(f, o + 4, 4))
            guard o + 8 + len <= f.count, n < Int(m.nFrames), let raw = decompress(Array(f[(o + 8)..<(o + 8 + len)]), Int(m.planeBytes)), raw.count == Int(m.planeBytes), crc32(raw) == crc else { break }
            o += 8 + len; n += 1
        }
        return (n, o, m)
    }
}
final class DZCWriter {
    typealias Codec = (compress: ([UInt8]) -> [UInt8]?, decompress: ([UInt8], Int) -> [UInt8]?)
    private let url: URL, meta: DZC.Meta, codec: Codec
    private var handle: FileHandle?, offsets: [UInt64] = []
    private(set) var framesWritten = 0

    /// Starts a new file (replaces any existing one) or, with resume, truncates an existing one after its valid prefix. nil on I/O failure or a header mismatch.
    init?(url: URL, meta: DZC.Meta, resume: Bool = false, codec: Codec = DZCWriter.lzfse) {
        self.url = url; self.meta = meta; self.codec = codec
        let fm = FileManager.default
        if resume, let d = try? Data(contentsOf: url), let s = DZC.scanValid([UInt8](d), decompress: codec.decompress), s.meta == meta {
            guard let h = try? FileHandle(forUpdating: url) else { return nil }
            do { try h.truncate(atOffset: UInt64(s.end)); try h.seekToEnd() } catch { return nil }
            handle = h; framesWritten = s.frames
            var o = DZC.headerSize
            for _ in 0..<s.frames { offsets.append(UInt64(o)); o += 8 + Int(DZC.rd([UInt8](d), o, 4)) }
        } else {
            guard fm.createFile(atPath: url.path, contents: Data(DZC.header(meta))), let h = try? FileHandle(forWritingTo: url) else { return nil }
            do { try h.seekToEnd() } catch { return nil }
            handle = h
        }
    }
    /// One frame of metres (depthHeight x depthWidth). False on codec/I/O failure or too many frames.
    func append(zMetres z: [Float]) -> Bool {
        let dh = Int(meta.depthHeight), dw = Int(meta.depthWidth)
        guard let h = handle, z.count == dh * dw, framesWritten < Int(meta.nFrames) else { return false }
        let q = DZC.quantise(z: z, h: dh, w: dw)
        guard q.width == Int(meta.width), q.height == Int(meta.height) else { return false }
        let raw = DZC.planeBytesLE(q.plane)
        guard let comp = codec.compress(raw), let off = try? h.offset() else { return false }
        do { try h.write(contentsOf: Data(DZC.record(planeLE: raw, compressed: comp))) } catch { ThreeDDegradeProbe.noteWriteError(error); return false }
        offsets.append(off); framesWritten += 1; return true
    }
    func synchronize() { try? handle?.synchronize() }
    /// Writes index + trailer. Only valid once every frame is written; the file is incomplete (but scannable) until this returns true.
    func finish() -> Bool {
        guard let h = handle, framesWritten == Int(meta.nFrames) else { return false }
        do { try h.write(contentsOf: Data(DZC.tail(offsets: offsets))); try h.close() } catch { ThreeDDegradeProbe.noteWriteError(error); return false }
        handle = nil; return true
    }

    static let lzfse: Codec = (
        { raw in
            #if canImport(Compression)
            var dst = [UInt8](repeating: 0, count: raw.count + raw.count / 8 + 4096)
            let n = compression_encode_buffer(&dst, dst.count, raw, raw.count, nil, COMPRESSION_LZFSE)
            return n > 0 ? Array(dst[0..<n]) : nil
            #else
            return nil
            #endif
        },
        { comp, expected in
            #if canImport(Compression)
            var dst = [UInt8](repeating: 0, count: expected)
            let n = compression_decode_buffer(&dst, dst.count, comp, comp.count, nil, COMPRESSION_LZFSE)
            return n == expected ? dst : nil
            #else
            return nil
            #endif
        })
}
final class DZCFile {
    let meta: DZC.Meta
    private let data: Data, offsets: [Int]
    var count: Int { offsets.count }
    var fps: Double { Double(meta.fpsNum) / Double(max(1, meta.fpsDen)) }

    /// True when the file is a complete container: header parses, size agrees with n_frames and the last 8 bytes are the trailer.
    static func isComplete(_ url: URL) -> Bool { DZCFile.layout(url) != nil }

    private static func layout(_ url: URL) -> (meta: DZC.Meta, data: Data, offsets: [Int])? {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.count >= DZC.headerSize + 8,
              let m = DZC.parseHeader([UInt8](d.prefix(DZC.headerSize))), m.nFrames > 0 else { return nil }
        let n = Int(m.nFrames), tail = n * 8 + 8
        guard d.count >= DZC.headerSize + tail, Array(d.suffix(8)) == DZC.trailer else { return nil }
        let idx = [UInt8](d[(d.count - tail)..<(d.count - 8)])
        var offs: [Int] = []
        for k in 0..<n {
            let v = DZC.rd(idx, k * 8, 8)
            guard v <= UInt64(Int.max) else { return nil }
            offs.append(Int(v))
        }
        guard offs.allSatisfy({ $0 >= DZC.headerSize && $0 + 8 <= d.count - tail }) else { return nil }
        return (m, d, offs)
    }

    init?(url: URL) {
        guard let l = DZCFile.layout(url) else { return nil }
        meta = l.meta; data = l.data; offsets = l.offsets
    }

    func pts(_ i: Int) -> Double { Double(Int(meta.startFrame) + i) / fps }

    /// Index of the first frame at/after `pts` (clamped to the last frame).
    func index(atOrAfter pts: Double) -> Int {
        let i = Int((pts * fps).rounded(.up)) - Int(meta.startFrame)
        return min(max(0, i), count - 1)
    }

    /// The decoded plane (width x height little-endian u16 as [UInt16]); nil when the record does not decompress or fails its crc.
    func plane(_ i: Int, decompress: ([UInt8], Int) -> [UInt8]? = DZCWriter.lzfse.decompress) -> [UInt16]? {
        guard offsets.indices.contains(i) else { return nil }
        let o = offsets[i], head = [UInt8](data[o..<(o + 8)])
        let len = Int(DZC.rd(head, 0, 4)), crc = UInt32(DZC.rd(head, 4, 4))
        guard o + 8 + len <= data.count, let raw = decompress([UInt8](data[(o + 8)..<(o + 8 + len)]), Int(meta.planeBytes)),
              raw.count == Int(meta.planeBytes), DZC.crc32(raw) == crc else { return nil }
        return (0..<(raw.count / 2)).map { (index: Int) -> UInt16 in
            let low: UInt16 = UInt16(raw[index * 2])
            let high: UInt16 = UInt16(raw[index * 2 + 1]) << 8
            return low | high
        }
    }
}
enum DepthQuant {
    static let dScale: Float = 256.0, vInvMax: Float = 1024.0
    /// prepare_film.write_depth_hevc: z metres -> 10-bit luma. z <= 1e-3 or non-finite -> 0 (masked / infinity). np.rint = half to even.
    static func w10(zMetres z: Float) -> UInt16 {
        guard z.isFinite, z > 1e-3 else { return 0 }
        let inv = dScale / max(z, 1e-3)
        let q = (inv / vInvMax * 1023.0).rounded(.toNearestOrEven)
        return UInt16(min(max(q, 0), 1023))
    }
}

func writeIt(_ bytes: [UInt8]) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dzc-packet-test.dzc")
    try! Data(bytes).write(to: url)
    return url
}
let m = DZC.Meta(shot: 0, fpsNum: 24, fpsDen: 1, startFrame: 0, width: 2, height: 2, depthWidth: 2, depthHeight: 2, nFrames: 1)
let planeLE = DZC.planeBytesLE([UInt16](repeating: 256, count: 4))
let rec = DZC.record(planeLE: planeLE, compressed: planeLE)
let good = DZC.header(m) + rec + DZC.tail(offsets: [UInt64(DZC.headerSize)])
guard DZCFile.isComplete(writeIt(good)) else { print("FAIL valid container rejected"); exit(1) }
// Corrupt index: an offset entry that does not fit Int must reject, never trap.
let badIndex = DZC.header(m) + rec + DZC.tail(offsets: [0xFFFFFFFFFFFFFFFF])
if DZCFile.isComplete(writeIt(badIndex)) { print("FAIL absurd index offset accepted"); exit(1) }
// Corrupt header: absurd plane dimensions must not overflow planeBytes.
let huge = DZC.Meta(shot: 0, fpsNum: 24, fpsDen: 1, startFrame: 0, width: 70000, height: 70000, depthWidth: 2, depthHeight: 2, nFrames: 1)
let bytes = DZC.header(huge) + DZC.record(planeLE: [], compressed: []) + DZC.tail(offsets: [UInt64(DZC.headerSize)])
let scan = DZC.scanValid(bytes, decompress: { _, _ in [] })
if scan == nil { print("FAIL scanValid returned nil for the decodable header"); exit(1) }
print("OK")
exit(0)

```

## fix diff
```diff
--- /tmp/packets_199j/W-gdb-199j-1nstinct-45/source/archive/gor/Sources/gor/gor/ThreeD.swift	2026-11-18 05:24:34.035609642 +0300
+++ /tmp/packets_199j/W-gdb-199j-1nstinct-45/fixed/archive/gor/Sources/gor/gor/ThreeD.swift	2026-11-18 05:24:34.035609642 +0300
@@ -2928,7 +2928,7 @@
     struct Meta: Equatable {
         var shot: UInt32, fpsNum: UInt32, fpsDen: UInt32, startFrame: UInt64
         var width: UInt32, height: UInt32, depthWidth: UInt32, depthHeight: UInt32, nFrames: UInt32
-        var planeBytes: UInt32 { width * height * 2 }
+        var planeBytes: UInt32 { let p = UInt64(width) * UInt64(height) * 2; return p <= UInt64(UInt32.max) ? UInt32(p) : 0 }
     }
     static func fpsPair(_ fps: Double) -> (UInt32, UInt32) { fps == fps.rounded() ? (UInt32(fps), 1) : (UInt32((fps * 1000).rounded()), 1000) }
 
@@ -3073,7 +3073,12 @@
         let n = Int(m.nFrames), tail = n * 8 + 8
         guard d.count >= DZC.headerSize + tail, Array(d.suffix(8)) == DZC.trailer else { return nil }
         let idx = [UInt8](d[(d.count - tail)..<(d.count - 8)])
-        let offs = (0..<n).map { Int(DZC.rd(idx, $0 * 8, 8)) }
+        var offs: [Int] = []
+        for k in 0..<n {
+            let v = DZC.rd(idx, k * 8, 8)
+            guard v <= UInt64(Int.max) else { return nil }
+            offs.append(Int(v))
+        }
         guard offs.allSatisfy({ $0 >= DZC.headerSize && $0 + 8 <= d.count - tail }) else { return nil }
         return (m, d, offs)
     }

```

## runner
```python
(run_packet.py, sha256 d349b0d2d8c64c039e2f8e221e40d4cb888b329badaad3f6818a05a25a5d15c7)
```

## fixtures
```json
fixtures1.json sha256 29b397e1b86e60e0c3fb92198edab6a3bb8019bab38153245db2cea34b02ed93
fixtures2.json sha256 843f90daef1437370cce8b1f9d5ed95e011261cce64dfdb976608b742996f01e
```

## run log
```text
== source -Onone ==
compile_exit=0
semantic_exit=-4

== source -O ==
compile_exit=0
semantic_exit=-4

== fixed -Onone ==
compile_exit=0
OK
semantic_exit=0

== fixed -O ==
compile_exit=0
OK
semantic_exit=0
```

Privacy revision 0526: whole comment runs removed. Non-comment statements string-aware compared equal to previously independently replayed adapted versions. Previous Linux proof binds OLD source hashes; new writer re-verification is separately attributed, Ops did not rerun Swift binaries for this comment-only revision. NONQUALIFIED; all prior boundary failures and native/full-host exclusions remain. Canonical runner discovery adaptation remains not executed.
