// Lab VobSub decoder (G0742 / 195b-B2, lab: 1nstinct), additive consumer
// seam: line-faithful Swift port of kits/b2-vobsub/vobsub.c (IDX
// timing/palette/placement parsing, MPEG-PS SPU extraction, SPU RLE decode,
// control sequences, forced/clear, seek reset). The C carrier with its
// 57-check suite stays vendored in kits/b2-vobsub as the executable witness.
// The bitmap ABI the lab marked PROPOSED/BLOCKED_INPUT is answered by value
// types here: each decoded event is an owned LabVobSubBitmap.
// Same bounded limits, same per-event warning flags, same recovery rules.



public struct LabVobSubBitmap: Equatable, Sendable {
    public var width = 0, height = 0, stride = 0
    public var x = 0, y = 0
    public var pixels: [UInt8] = []      // RGBA, height*stride bytes
    public var ptsMs: UInt64 = 0
    public var endMs: UInt64 = 0
    public var flags: UInt32 = 0         // LabVobSubDecoder.ev* bits
    public var nonZeroPixels: UInt32 = 0
    public init() {}
}

public enum LabVobSubError: Error, Equatable {
    case arg, idx, io
}

/// Reader: absolute offset + length (>=1) -> bytes. nil = I/O error; a
/// shorter array signals a short read, exactly the C reader contract.
public typealias LabVobSubReader = (_ offset: UInt64, _ length: Int) -> [UInt8]?

public final class LabVobSubDecoder {
    public static let maxStreams = 32
    public static let maxDim = 4096
    public static let maxEntries = 4096

    public static let evForced: UInt32 = 0x01
    public static let evTruncated: UInt32 = 0x02
    public static let evClippedX: UInt32 = 0x04
    public static let evClippedY: UInt32 = 0x08
    public static let evBadCtrl: UInt32 = 0x10

    private struct Entry { var ptsMs: UInt64 = 0, filepos: UInt64 = 0, stream: UInt8 = 0 }

    private let read: LabVobSubReader
    private let subSize: UInt64

    public private(set) var frameW = 0, frameH = 0
    private var palette = [[UInt8]](repeating: [0, 0, 0], count: 16)
    private var entries = [Entry]()

    private var visible = false
    private var forced = false
    private var colors: [UInt8] = [0, 1, 2, 3]
    private var alpha: [UInt8] = [0, 15, 15, 15]
    private var ax1 = 0, ay1 = 0, ax2 = 0, ay2 = 0
    private var pxOff: [Int] = [0, 0]

    public init(reader: @escaping LabVobSubReader, subSize: UInt64) {
        read = reader; self.subSize = subSize
    }

    public var entryCount: Int { entries.count }

    public func frameSize() -> (w: Int, h: Int)? {
        guard frameW > 0, frameH > 0 else { return nil }
        return (frameW, frameH)
    }

    public func seekReset() { visible = false; forced = false }
    public func clear() { visible = false }

    // ---- IDX parsing -------------------------------------------------

    private static func parseTs(_ s: Substring) -> UInt64? {
        // hh:mm:ss:mmm with sscanf("%2u:%2u:%2u:%3u") width semantics:
        // 1-2 digits, colon, 1-2 digits, colon, 1-2 digits, colon, 1-3 digits.
        func digits(_ t: inout Substring, _ maxN: Int) -> UInt64? {
            var v: UInt64 = 0, n = 0
            while n < maxN, let c = t.first, c >= "0", c <= "9" {
                v = v * 10 + UInt64(c.wholeNumberValue!); t = t.dropFirst(); n += 1
            }
            return n > 0 ? v : nil
        }
        var t = s
        guard let hh = digits(&t, 2), t.first == ":" else { return nil }; t = t.dropFirst()
        guard let mm = digits(&t, 2), t.first == ":" else { return nil }; t = t.dropFirst()
        guard let ss = digits(&t, 2), t.first == ":" else { return nil }; t = t.dropFirst()
        guard let mmm = digits(&t, 3) else { return nil }
        guard mm <= 59, ss <= 59, mmm <= 999 else { return nil }
        return ((hh * 3600 + mm * 60 + ss) * 1000) + mmm
    }

    /// First range of a short ASCII needle in haystack, no Foundation bridging.
    private static func find(_ needle: String, in haystack: Substring) -> Substring.Index? {
        let n = Array(needle)
        let h = Array(haystack)
        guard n.count <= h.count else { return nil }
        for i in 0...(h.count - n.count) {
            if Array(h[i..<(i + n.count)]) == n { return haystack.index(haystack.startIndex, offsetBy: i) }
        }
        return nil
    }

    private static func hexPrefix(_ s: Substring) -> (UInt64, Substring)? {
        var i = s.startIndex
        var v: UInt64 = 0
        var any = false
        while i < s.endIndex, let d = s[i].hexDigitValue, d < 16 {
            v = v * 16 + UInt64(d); i = s.index(after: i); any = true
        }
        return any ? (v, s[i...]) : nil
    }

    @discardableResult
    public func loadIdx(_ text: String, streamIndex: Int = 0) -> LabVobSubError? {
        let streamIndex = max(0, streamIndex)
        entries = []
        for lineSub in text.split(whereSeparator: \.isNewline) {
            let line = lineSub.drop(while: { $0 == " " || $0 == "\t" })
            if line.hasPrefix("size:") {
                let rest = line.dropFirst(5)
                let parts = rest.split(separator: "x", maxSplits: 1)
                if parts.count == 2,
                   let w = Int(parts[0].drop(while: { $0 == " " || $0 == "\t" })),
                   let h = Int(parts[1].drop(while: { $0 == " " || $0 == "\t" })),
                   w > 0, h > 0, w <= LabVobSubDecoder.maxDim, h <= LabVobSubDecoder.maxDim {
                    frameW = w; frameH = h
                }
            } else if line.hasPrefix("palette:") {
                var q = line.dropFirst(8)
                var i = 0
                while !q.isEmpty, i < 16 {
                    guard let (v, rest) = LabVobSubDecoder.hexPrefix(q.drop(while: { $0 == " " || $0 == "\t" })) else { break }
                    palette[i] = [UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
                    i += 1
                    q = rest.drop(while: { $0 == " " || $0 == "\t" })
                    if q.first == "," { q = q.dropFirst() }
                }
            } else if line.hasPrefix("timestamp:") {
                guard let comma = line.firstIndex(of: ",") else { continue }
                guard let ms = LabVobSubDecoder.parseTs(line[line.index(line.startIndex, offsetBy: 10)...].drop(while: { $0 == " " || $0 == "\t" })) else { continue }
                let tail = line[comma...]
                guard let fpStart = LabVobSubDecoder.find("filepos:", in: tail) else { continue }
                let pos = LabVobSubDecoder.hexPrefix(tail[fpStart...].dropFirst(8).drop(while: { $0 == " " || $0 == "\t" }))?.0 ?? 0
                if entries.count < LabVobSubDecoder.maxEntries {
                    entries.append(Entry(ptsMs: ms, filepos: pos, stream: UInt8(0x20 + streamIndex)))
                }
            }
        }
        guard frameW > 0, frameH > 0, !entries.isEmpty else { return .idx }
        return nil
    }

    // ---- SUB reader / PS walk ---------------------------------------

    private func readAt(_ off: UInt64, _ len: Int) -> (bytes: [UInt8], ok: Bool) {
        if off >= subSize { return ([], true) }
        let clamped = min(UInt64(len), subSize - off) // off < subSize: no underflow
        guard let b = read(off, Int(clamped)) else { return ([], false) }
        return (b, true)
    }

    private static func be16(_ p: [UInt8], _ off: Int) -> Int { Int(p[off]) << 8 | Int(p[off + 1]) }
    private static func be32(_ p: [UInt8], _ off: Int) -> UInt32 {
        UInt32(p[off]) << 24 | UInt32(p[off + 1]) << 16 | UInt32(p[off + 2]) << 8 | UInt32(p[off + 3])
    }

    /// Extract the SPU packet for the entry's stream from the PS data at
    /// its filepos. Same 8-hop bound, same truncation tolerance.
    private func extractSPU(_ e: Entry, flags: inout UInt32) throws -> [UInt8] {
        var pos = e.filepos
        var acc: [UInt8] = []
        for _ in 0..<8 {                                 // bound the walk
            var r = readAt(pos, 4)
            guard r.ok, r.bytes.count >= 4 else { throw LabVobSubError.io }
            let sc = LabVobSubDecoder.be32(r.bytes, 0)
            if sc == 0x000001BA {                        // pack header
                r = readAt(pos, 14)
                guard r.ok, r.bytes.count >= 14 else { throw LabVobSubError.io }
                pos += UInt64(14 + Int(r.bytes[13] & 0x07))
                continue
            }
            if sc == 0x000001BD {                        // private_stream_1
                r = readAt(pos, 9)
                guard r.ok, r.bytes.count >= 9 else { throw LabVobSubError.io }
                let plen = LabVobSubDecoder.be16(r.bytes, 4)
                // guard BEFORE subtraction: plen < 3 + hdrlen underflows
                guard plen >= 3 + Int(r.bytes[8]) else { throw LabVobSubError.io }
                let dataOff = 9 + Int(r.bytes[8])
                let payLen = plen - 3 - Int(r.bytes[8])
                guard payLen >= 1 else { throw LabVobSubError.io }
                let sidR = readAt(pos + UInt64(dataOff), 1)
                guard sidR.ok, sidR.bytes.count >= 1 else { throw LabVobSubError.io }
                if sidR.bytes[0] == e.stream {
                    let need = payLen - 1
                    if need == 0 { return acc }          // zero-payload SPU: no zero-length read
                    let bodyR = readAt(pos + UInt64(dataOff) + 1, need)
                    guard bodyR.ok else { throw LabVobSubError.io }
                    acc.append(contentsOf: bodyR.bytes)
                    if bodyR.bytes.count < need {
                        flags |= LabVobSubDecoder.evTruncated
                    }
                    return acc
                }
                pos += UInt64(6 + plen)
                continue
            }
            break                                        // unknown start code: stop
        }
        throw LabVobSubError.io
    }

    // ---- SPU RLE ------------------------------------------------------

    private static func getBit(_ src: [UInt8], _ bitpos: Int) -> Int {
        if bitpos >= src.count * 8 { return 0 }
        return Int((src[bitpos >> 3] >> UInt(7 - (bitpos & 7))) & 1)
    }

    /// RLE-decode one field (2-bit codes, only the field's rows written).
    /// Returns true if the bitstream ran out (truncation tolerated).
    private static func decodeField(_ src: [UInt8], into codes: inout [UInt8],
                                    w: Int, h: Int, parity: Int) -> Bool {
        var bitpos = 0, x = 0, y = parity, truncated = false
        while y < h {
            var peek = 0
            for i in 0..<16 { peek = (peek << 1) | getBit(src, bitpos + i) }
            let n: Int, code: Int
            if peek >= 0x4000 { n = 4; code = peek >> 12 }
            else if peek >= 0x1000 { n = 8; code = peek >> 8 }
            else if peek >= 0x0400 { n = 12; code = peek >> 4 }
            else { n = 16; code = peek }
            if bitpos + n > src.count * 8 { truncated = true }
            bitpos += n
            var run = code >> 2
            if run == 0 { run = w - x }                  // all-zero code: rest of line
            if run > w - x { run = w - x }               // clamp: bounds handling
            for _ in 0..<run { codes[y * w + x] = UInt8(code & 3); x += 1 }
            if x == w {                                  // no per-line byte alignment (DVD SPU)
                x = 0; y += 2
            }
        }
        return truncated
    }

    // ---- control sequences -------------------------------------------

    private func parseControl(_ spu: [UInt8], ctrlOff: Int, durMs: inout UInt64, flags: inout UInt32) {
        var off = ctrlOff
        durMs = 0
        let spuLen = spu.count
        while off + 4 <= spuLen {
            let blockLen = LabVobSubDecoder.be16(spu, off)
            let delay = LabVobSubDecoder.be16(spu, off + 2)
            var cmd = off + 4
            var end = off + blockLen
            var stopSeen = false
            if blockLen < 4 || end > spuLen {
                flags |= LabVobSubDecoder.evTruncated
                end = spuLen
            }
            // duration runs from the display block to the STP_DSP block only
            durMs &+= (UInt64(delay) * 1024 + 45) / 90   // 90kHz/1024 units
            var badCmd = false
            while cmd < end && !badCmd {
                let op = spu[cmd]; cmd += 1
                switch op {
                case 0x00: forced = true; visible = true           // FSTA_DSP
                case 0x01: visible = true                          // STA_DSP
                case 0x02: visible = false; stopSeen = true        // STP_DSP
                case 0x03:                                         // SET_COLOR
                    if cmd + 2 > end { badCmd = true; break }
                    colors[3] = (spu[cmd] >> 4) & 0xF; colors[2] = spu[cmd] & 0xF
                    colors[1] = (spu[cmd + 1] >> 4) & 0xF; colors[0] = spu[cmd + 1] & 0xF
                    cmd += 2
                case 0x04:                                         // SET_CONTR
                    if cmd + 2 > end { badCmd = true; break }
                    alpha[3] = (spu[cmd] >> 4) & 0xF; alpha[2] = spu[cmd] & 0xF
                    alpha[1] = (spu[cmd + 1] >> 4) & 0xF; alpha[0] = spu[cmd + 1] & 0xF
                    cmd += 2
                case 0x05:                                         // SET_DAREA
                    if cmd + 6 > end { badCmd = true; break }
                    ax1 = Int(spu[cmd]) << 4 | Int(spu[cmd + 1] >> 4)
                    ax2 = Int(spu[cmd + 1] & 0xF) << 8 | Int(spu[cmd + 2])
                    ay1 = Int(spu[cmd + 3]) << 4 | Int(spu[cmd + 4] >> 4)
                    ay2 = Int(spu[cmd + 4] & 0xF) << 8 | Int(spu[cmd + 5])
                    cmd += 6
                case 0x06:                                         // SET_DSPXA
                    if cmd + 4 > end { badCmd = true; break }
                    pxOff[0] = LabVobSubDecoder.be16(spu, cmd)
                    pxOff[1] = LabVobSubDecoder.be16(spu, cmd + 2)
                    cmd += 4
                case 0x07: cmd = end                               // CHG_COLCON: skip to end
                case 0xFF: cmd = end                               // END
                default: badCmd = true
                }
            }
            if badCmd { flags |= LabVobSubDecoder.evBadCtrl; cmd = end }
            if stopSeen { break }
            if blockLen < 4 || end == spuLen { break }
            off = end
        }
    }

    // ---- event decode -------------------------------------------------

    /// Decode one IDX entry into an owned bitmap. A recoverable corrupt
    /// entry returns nil event with flags folded into `flags` semantics of
    /// the C: here nil means "empty after clipping"; errors throw.
    @discardableResult
    public func decodeEntry(_ index: Int) throws -> LabVobSubBitmap? {
        guard index >= 0, index < entries.count else { throw LabVobSubError.arg }
        let e = entries[index]
        var flags: UInt32 = 0
        var spu = try extractSPU(e, flags: &flags)
        guard spu.count >= 4 else { throw LabVobSubError.io }

        let spuSize = LabVobSubDecoder.be16(spu, 0)
        let ctrlOff = LabVobSubDecoder.be16(spu, 2)
        if spuSize > spu.count {
            flags |= LabVobSubDecoder.evTruncated
        } else if spuSize < spu.count {
            spu = Array(spu[0..<spuSize])                // ignore trailing garbage
        }
        guard ctrlOff < spu.count, ctrlOff >= 4 else { throw LabVobSubError.io }

        // per-event spec defaults
        forced = false; visible = false
        colors = [0, 1, 2, 3]; alpha = [0, 15, 15, 15]
        ax1 = 0; ay1 = 0; ax2 = frameW - 1; ay2 = frameH - 1
        pxOff = [4, 0]                                   // field-1 default; field-2 unset

        var durMs: UInt64 = 0
        parseControl(spu, ctrlOff: ctrlOff, durMs: &durMs, flags: &flags)

        var x1 = ax1, y1 = ay1, x2 = ax2, y2 = ay2
        if x1 < 0 { x1 = 0; flags |= LabVobSubDecoder.evClippedX }
        if y1 < 0 { y1 = 0; flags |= LabVobSubDecoder.evClippedY }
        if x2 >= frameW { x2 = frameW - 1; flags |= LabVobSubDecoder.evClippedX }
        if y2 >= frameH { y2 = frameH - 1; flags |= LabVobSubDecoder.evClippedY }
        if x2 < x1 || y2 < y1 { return nil }             // empty after clipping
        let w = x2 - x1 + 1, h = y2 - y1 + 1

        var codes = [UInt8](repeating: 0, count: w * h)
        if pxOff[0] >= ctrlOff {
            flags |= LabVobSubDecoder.evTruncated
        } else {
            let f2 = pxOff[1] >= 4 && pxOff[1] < ctrlOff ? pxOff[1] : ctrlOff
            let t1 = LabVobSubDecoder.decodeField(Array(spu[pxOff[0]..<ctrlOff]),
                                                  into: &codes, w: w, h: h, parity: 0)
            if f2 < ctrlOff {
                let t2 = LabVobSubDecoder.decodeField(Array(spu[f2..<ctrlOff]),
                                                      into: &codes, w: w, h: h, parity: 1)
                if t1 || t2 { flags |= LabVobSubDecoder.evTruncated }
            } else if t1 {
                flags |= LabVobSubDecoder.evTruncated
            }
        }

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        var nz: UInt32 = 0
        for i in 0..<(w * h) {
            let c = Int(codes[i] & 3)
            let pi = Int(colors[c] & 0xF)
            let a = alpha[c] & 0xF
            let av = a * 17                              // nibble -> 0..255
            rgba[i * 4] = palette[pi][0]
            rgba[i * 4 + 1] = palette[pi][1]
            rgba[i * 4 + 2] = palette[pi][2]
            rgba[i * 4 + 3] = av
            if av > 0 { nz += 1 }
        }
        var bm = LabVobSubBitmap()
        bm.width = w; bm.height = h; bm.stride = w * 4
        bm.x = x1; bm.y = y1
        bm.pixels = rgba
        bm.ptsMs = e.ptsMs; bm.endMs = e.ptsMs + durMs
        bm.flags = flags | (forced ? LabVobSubDecoder.evForced : 0)
        bm.nonZeroPixels = nz
        return bm
    }

    /// Decode every entry whose timestamp falls in [startMs, endMs), IDX order.
    @discardableResult
    public func decodeRange(_ startMs: UInt64, _ endMs: UInt64) throws -> [LabVobSubBitmap] {
        var out: [LabVobSubBitmap] = []
        for i in 0..<entries.count {
            if entries[i].ptsMs >= startMs && entries[i].ptsMs < endMs {
                if let bm = try decodeEntry(i) { out.append(bm) }
            }
        }
        return out
    }
}

