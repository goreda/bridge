// Lab PGS decoder (G0741 / 195b-B1, lab: 1nstinct), additive consumer seam:
// line-faithful Swift port of kits/b1-pgs/pgs.c (Blu-ray "PG" segment-stream
// decoder + bitmap compositor). The C carrier with its 45-check suite stays
// vendored in kits/b1-pgs as the executable witness. Events are VALUE types
// (the C's PROPOSED decoder-owned-pointer ABI becomes owned arrays - the
// ownership question the lab flagged BLOCKED_INPUT is answered by value
// semantics). Same bounded limits, same drop-and-resync error behavior.
// Cropping flag and fragmented ODS sequences stay explicitly unsupported,
// exactly as the lab pinned them.

public enum LabPGSEventType: String, Equatable, Sendable {
    case display, clear
}

public struct LabPGSRect: Equatable, Sendable {
    public var x: UInt16 = 0, y: UInt16 = 0, w: UInt16 = 0, h: UInt16 = 0
    public init(x: UInt16, y: UInt16, w: UInt16, h: UInt16) { self.x = x; self.y = y; self.w = w; self.h = h }
}

/// One completed display set. indices is frameW*frameH palette indices
/// (row-major, tight); palette is 256 x 0xRRGGBBAA; both nil on .clear.
public struct LabPGSEvent: Equatable, Sendable {
    public var type: LabPGSEventType
    public var pts90k: UInt64
    public var ptsMs: UInt64
    public var frameW: UInt16
    public var frameH: UInt16
    public var indices: [UInt8]?
    public var palette: [UInt32]?
    public var rects: [LabPGSRect]
}

public final class LabPGSDecoder {
    public static let maxSegBody = 0xFFFF
    public static let maxObjects = 64
    public static let maxWindows = 16
    public static let maxCompObjs = 64
    public static let maxDim = 4096
    public static let maxObjPixels = 16 * 1024 * 1024

    private struct PaletteEntry { var y: UInt8 = 0, cr: UInt8 = 0, cb: UInt8 = 0, a: UInt8 = 0 }
    private struct Window { var id: UInt8 = 0, x: UInt16 = 0, y: UInt16 = 0, w: UInt16 = 0, h: UInt16 = 0 }
    private struct Comp { var objId: UInt16 = 0, winId: UInt8 = 0, x: UInt16 = 0, y: UInt16 = 0 }
    private struct Obj { var used = false, id: UInt16 = 0, version: UInt8 = 0, w = 0, h = 0, pix: [UInt8]? = nil }

    private let fw: Int, fh: Int
    private var pal = [PaletteEntry](repeating: PaletteEntry(), count: 256)
    private var palSet = false
    private var win = [Window](repeating: Window(), count: LabPGSDecoder.maxWindows)
    private var nWin = 0
    private var comp = [Comp](repeating: Comp(), count: LabPGSDecoder.maxCompObjs)
    private var nComp = 0
    private var obj = [Obj](repeating: Obj(), count: LabPGSDecoder.maxObjects)

    private var frameDone = false
    private var frameClear = false
    private var framePts: UInt64 = 0
    private var canvas: [UInt8]
    private var palette = [UInt32](repeating: 0, count: 256)
    private var rects = [LabPGSRect](repeating: LabPGSRect(x: 0, y: 0, w: 0, h: 0), count: LabPGSDecoder.maxWindows)
    private var nRects = 0

    private var hdr = [UInt8](repeating: 0, count: 13)
    private var hdrHave = 0
    private var curType: UInt8 = 0
    private var curLen = 0, curHave = 0
    private var curBuf: [UInt8] = []
    private var pts: UInt32 = 0, dts: UInt32 = 0
    public private(set) var errorText = ""

    public init?(frameW: UInt16, frameH: UInt16) {
        guard frameW > 0, frameH > 0, frameW <= UInt16(LabPGSDecoder.maxDim),
              frameH <= UInt16(LabPGSDecoder.maxDim) else { return nil }
        fw = Int(frameW); fh = Int(frameH)
        canvas = [UInt8](repeating: 0, count: fw * fh)
    }

    private func rd16(_ p: [UInt8], _ off: Int) -> Int { Int(p[off]) << 8 | Int(p[off + 1]) }
    private func rd32(_ p: [UInt8], _ off: Int) -> UInt32 {
        UInt32(p[off]) << 24 | UInt32(p[off + 1]) << 16 | UInt32(p[off + 2]) << 8 | UInt32(p[off + 3])
    }

    /// BT.601 video-range YCbCr -> 0xRRGGBBAA, rounded and clamped.
    static func yccToRGBA(y: UInt8, cr: UInt8, cb: UInt8, a: UInt8) -> UInt32 {
        let yy = (Int(y) - 16) * 76309
        let crd = Int(cr) - 128, cbd = Int(cb) - 128
        var r = (yy + 104597 * crd + 32768) >> 16
        var g = (yy - 25675 * cbd - 53279 * crd + 32768) >> 16
        var b = (yy + 132201 * cbd + 32768) >> 16
        r = min(max(r, 0), 255); g = min(max(g, 0), 255); b = min(max(b, 0), 255)
        return UInt32(r) << 24 | UInt32(g) << 16 | UInt32(b) << 8 | UInt32(a)
    }

    /// RLE decode of one object into dst (w*h bytes). nil error string on
    /// success; same strict truncation/overflow rejection as pgs_rle_decode.
    public static func rleDecode(_ src: [UInt8], width w: Int, height h: Int) -> (out: [UInt8], err: String?)? {
        var dst = [UInt8](repeating: 0, count: w * h)
        var pos = 0, x = 0, y = 0
        let n = src.count
        guard w > 0, h > 0 else { return (dst, "rle: bad args") }
        while y < h {
            if pos >= n { return (dst, "rle: truncated input") }
            let c = src[pos]; pos += 1
            if c != 0 {
                if x >= w { return (dst, "rle: line overflow") }
                dst[y * w + x] = c; x += 1
                continue
            }
            if pos >= n { return (dst, "rle: truncated escape") }
            let b = src[pos]; pos += 1
            if b == 0x00 {                                   // end of line
                while x < w { dst[y * w + x] = 0; x += 1 }
                x = 0; y += 1
            } else if b < 0x40 {                             // short transparent run
                let run = Int(b)
                if x + run > w { return (dst, "rle: run overruns line") }
                for _ in 0..<run { dst[y * w + x] = 0; x += 1 }
            } else if b < 0x80 {                             // long transparent run
                if pos >= n { return (dst, "rle: truncated long run") }
                let run = Int(b & 0x3F) << 8 | Int(src[pos]); pos += 1
                if x + run > w { return (dst, "rle: run overruns line") }
                for _ in 0..<run { dst[y * w + x] = 0; x += 1 }
            } else if b < 0xC0 {                             // short color run
                let run = Int(b & 0x3F)
                if pos >= n { return (dst, "rle: truncated color run") }
                let col = src[pos]; pos += 1
                if x + run > w { return (dst, "rle: run overruns line") }
                for _ in 0..<run { dst[y * w + x] = col; x += 1 }
            } else {                                         // long color run
                if pos + 2 > n { return (dst, "rle: truncated long color run") }
                let run = Int(b & 0x3F) << 8 | Int(src[pos]); pos += 1
                let col = src[pos]; pos += 1
                if x + run > w { return (dst, "rle: run overruns line") }
                for _ in 0..<run { dst[y * w + x] = col; x += 1 }
            }
        }
        if x != 0 { return (dst, "rle: last line unterminated") }
        return (dst, nil)
    }

    private func setErr(_ m: String) { errorText = m }

    private func objReset(id: UInt16, version: UInt8) {
        for i in 0..<LabPGSDecoder.maxObjects {
            if obj[i].used && obj[i].id == id && obj[i].version != version { obj[i] = Obj() }
        }
    }

    private func objFind(_ id: UInt16, create: Bool) -> Int? {
        var freei = -1
        for i in 0..<LabPGSDecoder.maxObjects {
            if obj[i].used && obj[i].id == id { return i }
            if !obj[i].used && freei < 0 { freei = i }
        }
        if !create || freei < 0 { return nil }
        obj[freei].used = true; obj[freei].id = id
        return freei
    }

    private func hPDS(_ p: [UInt8], _ n: Int) -> Int {
        if n < 2 || (n - 2) % 5 != 0 { setErr("PDS: bad length"); return -1 }
        var off = 2 // skip palette id + version
        while off + 5 <= n {
            let idx = Int(p[off])
            pal[idx] = PaletteEntry(y: p[off + 1], cr: p[off + 2], cb: p[off + 3], a: p[off + 4])
            off += 5
        }
        palSet = true
        return 0
    }

    private func hWDS(_ p: [UInt8], _ n: Int) -> Int {
        if n < 1 { setErr("WDS: bad length"); return -1 }
        let cnt = Int(p[0])
        if cnt > LabPGSDecoder.maxWindows || n < 1 + cnt * 9 { setErr("WDS: window count/size overflow"); return -1 }
        nWin = cnt
        var off = 1
        for i in 0..<cnt {
            win[i] = Window(id: p[off], x: UInt16(rd16(p, off + 1)), y: UInt16(rd16(p, off + 3)),
                            w: UInt16(rd16(p, off + 5)), h: UInt16(rd16(p, off + 7)))
            off += 9
        }
        return 0
    }

    private func hPCS(_ p: [UInt8], _ n: Int) -> Int {
        if n < 11 { setErr("PCS: bad length"); return -1 }
        if rd16(p, 0) != fw || rd16(p, 2) != fh { setErr("PCS: frame geometry mismatch"); return -1 }
        let state = p[7]
        if state == 0x00 {          // normal: accumulate
        } else if state == 0x80 || state == 0x40 { // acquisition point / epoch start: reset
            palSet = false; nWin = 0; nComp = 0
            for i in 0..<LabPGSDecoder.maxObjects { obj[i] = Obj() }
        } else {
            setErr("PCS: unknown composition state"); return -1
        }
        let cnt = Int(p[10])
        if cnt > LabPGSDecoder.maxCompObjs || n < 11 + cnt * 8 { setErr("PCS: composition size overflow"); return -1 }
        nComp = cnt
        var off = 11
        for i in 0..<cnt {
            comp[i] = Comp(objId: UInt16(rd16(p, off)), winId: p[off + 2],
                           x: UInt16(rd16(p, off + 4)), y: UInt16(rd16(p, off + 6)))
            // off+3: object_cropped_flag (ignored, cropping not supported)
            off += 8
        }
        return 0
    }

    private func hODS(_ p: [UInt8], _ n: Int) -> Int {
        if n < 4 { setErr("ODS: bad length"); return -1 }
        let id = UInt16(rd16(p, 0)); let ver = p[2]; let flags = p[3]
        // arch-197c lane c: accept 0xc0 (spec first|last = complete in one
        // segment) - the value real encoders emit on the wire (confirmed on
        // the arch-196v e1 corpus PGS stream; decodes clean with ffmpeg's
        // pgssub). The extension the result packet pinned ("extend after
        // integrator confirms real streams need it"). Same strict size
        // check as the lab's 0x40-only path, kept for the vendored sample.
        if flags == 0x80 || flags == 0x40 || flags == 0xc0 { // first or only (0xc0: spec complete)
            if n < 11 { setErr("ODS: bad header length"); return -1 }
            let size = Int(p[4]) << 16 | Int(p[5]) << 8 | Int(p[6]) // rle size incl w/h
            if size < 4 { setErr("ODS: bad object size"); return -1 }
            let w = rd16(p, 7), h = rd16(p, 9)
            if w == 0 || h == 0 || w > LabPGSDecoder.maxDim || h > LabPGSDecoder.maxDim
                || w * h > LabPGSDecoder.maxObjPixels {
                setErr("ODS: object dimensions out of bounds"); return -1
            }
            if flags == 0x40 || flags == 0xc0 {             // only: complete in one segment
                if n - 11 != size - 4 { setErr("ODS: size mismatch"); return -1 }
                objReset(id: id, version: ver)
                guard let oi = objFind(id, create: true) else { setErr("ODS: object table full"); return -1 }
                let r = LabPGSDecoder.rleDecode(Array(p[11..<n]), width: w, height: h)
                guard let dec = r, dec.err == nil else { obj[oi] = Obj(); if let e = r?.err { setErr(e) }; return -1 }
                obj[oi].pix = dec.out; obj[oi].w = w; obj[oi].h = h; obj[oi].version = ver
                return 0
            }
            // first of a sequence: fragmented multi-segment ODS is not supported;
            // accept only when the remainder already fits in this segment
            if n - 11 >= size - 4 {
                objReset(id: id, version: ver)
                guard let oi = objFind(id, create: true) else { setErr("ODS: object table full"); return -1 }
                let r = LabPGSDecoder.rleDecode(Array(p[11..<(11 + size - 4)]), width: w, height: h)
                guard let dec = r, dec.err == nil else { obj[oi] = Obj(); if let e = r?.err { setErr(e) }; return -1 }
                obj[oi].pix = dec.out; obj[oi].w = w; obj[oi].h = h; obj[oi].version = ver
                return 0
            }
            setErr("ODS: fragmented object sequences not supported")
            return -1
        }
        if flags == 0x00 { setErr("ODS: continuation without start"); return -1 }
        setErr("ODS: unknown sequence flag")
        return -1
    }

    private func hEnd(_ ptsIn: UInt64) -> Int {
        if nComp == 0 {                                     // display clear
            frameDone = true; frameClear = true; framePts = ptsIn; nRects = 0
            return 0
        }
        if !palSet { setErr("END: display set has no palette"); return -1 }
        for i in 0..<canvas.count { canvas[i] = 0 }
        for i in 0..<256 { palette[i] = LabPGSDecoder.yccToRGBA(y: pal[i].y, cr: pal[i].cr, cb: pal[i].cb, a: pal[i].a) }
        nRects = 0
        for i in 0..<nComp {
            guard let oi = objFind(comp[i].objId, create: false), obj[oi].pix != nil else {
                setErr("END: composition references unknown object"); return -1
            }
            var wIdx: Int? = nil
            for j in 0..<nWin where win[j].id == comp[i].winId { wIdx = j }
            guard let wi = wIdx else { setErr("END: composition references unknown window"); return -1 }
            let o = obj[oi], wnd = win[wi]
            // clip object to its window (window coords are absolute)
            var x0 = Int(comp[i].x); if x0 < Int(wnd.x) { x0 = Int(wnd.x) }
            var y0 = Int(comp[i].y); if y0 < Int(wnd.y) { y0 = Int(wnd.y) }
            var x1 = Int(comp[i].x) + o.w; if x1 > Int(wnd.x) + Int(wnd.w) { x1 = Int(wnd.x) + Int(wnd.w) }
            var y1 = Int(comp[i].y) + o.h; if y1 > Int(wnd.y) + Int(wnd.h) { y1 = Int(wnd.y) + Int(wnd.h) }
            if x1 > fw { x1 = fw }
            if y1 > fh { y1 = fh }
            if x1 > x0 && y1 > y0 {
                for j in y0..<y1 {
                    for k in x0..<x1 {
                        canvas[j * fw + k] = o.pix![(j - Int(comp[i].y)) * o.w + (k - Int(comp[i].x))]
                    }
                }
                if nRects < LabPGSDecoder.maxWindows {
                    rects[nRects] = LabPGSRect(x: UInt16(x0), y: UInt16(y0),
                                               w: UInt16(x1 - x0), h: UInt16(y1 - y0))
                    nRects += 1
                }
            }
        }
        frameDone = true; frameClear = false; framePts = ptsIn
        return 0
    }

    private func handleSegment() -> Int {
        let p = curBuf, n = curLen
        switch curType {
        // arch-197c lane c: spec segment types (the vendored lab had WDS/ODS
        // swapped; see kits/b1-pgs/pgs.c SEG_* comment). ODS=0x15, WDS=0x17.
        case 0x14: return hPDS(p, n)
        case 0x15: return hODS(p, n)
        case 0x16: return hPCS(p, n)
        case 0x17: return hWDS(p, n)
        case 0x80:
            if n != 0 { setErr("END: nonzero body"); return -1 }
            return hEnd(UInt64(pts))
        default:
            setErr("unknown segment type")
            return -1
        }
    }

    /// Feed bytes of the "PG"-magic segment stream. Split and concatenated
    /// segments are handled. Returns true when all bytes parsed cleanly;
    /// false when a segment was malformed: it is dropped, errorText set, and
    /// bytes after it in the same call are dropped (decoder stays usable).
    @discardableResult
    public func feed(_ data: [UInt8]) -> Bool {
        errorText = ""
        var pos = 0
        let len = data.count
        while pos < len {
            if curLen == 0 {
                var take = 13 - hdrHave
                if take > len - pos { take = len - pos }
                hdr.replaceSubrange(hdrHave..<(hdrHave + take), with: data[pos..<(pos + take)])
                hdrHave += take; pos += take
                if hdrHave < 13 { continue }
                if hdr[0] != 0x50 || hdr[1] != 0x47 {       // "PG"
                    setErr("bad magic, resync failed")
                    hdrHave = 0
                    return false                            // spec streams are contiguous; drop the rest
                }
                pts = rd32(hdr, 2); dts = rd32(hdr, 6)
                curType = hdr[10]
                curLen = rd16(hdr, 11)
                curHave = 0; hdrHave = 0
                if curLen > 0 {
                    curBuf = [UInt8](repeating: 0, count: curLen)
                } else {                                    // END segment: no body
                    if handleSegment() != 0 { curLen = 0; return false }
                    curLen = 0
                }
                continue
            }
            let want = curLen - curHave
            let avail = len - pos
            let take = min(want, avail)
            curBuf.replaceSubrange(curHave..<(curHave + take), with: data[pos..<(pos + take)])
            curHave += take; pos += take
            if curHave == curLen {
                let rc = handleSegment()
                curBuf = []; curLen = 0; curHave = 0
                if rc != 0 { return false }                 // drop rest of call; err set by handler
            }
        }
        return true
    }

    /// Poll a completed event (display or clear at its PTS). A newer
    /// completed display set replaces an unconsumed older one.
    public func nextEvent() -> LabPGSEvent? {
        guard frameDone else { return nil }
        defer { frameDone = false }
        if frameClear {
            return LabPGSEvent(type: .clear, pts90k: framePts, ptsMs: framePts / 90,
                               frameW: UInt16(fw), frameH: UInt16(fh),
                               indices: nil, palette: nil, rects: [])
        }
        return LabPGSEvent(type: .display, pts90k: framePts, ptsMs: framePts / 90,
                           frameW: UInt16(fw), frameH: UInt16(fh),
                           indices: canvas, palette: palette, rects: Array(rects[0..<nRects]))
    }
}
