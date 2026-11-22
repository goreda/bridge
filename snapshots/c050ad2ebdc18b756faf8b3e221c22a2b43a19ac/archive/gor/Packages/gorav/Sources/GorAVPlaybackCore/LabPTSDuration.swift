// Lab PTS/duration oracle (G0730 / 195a-N04, lab: 1nstinct), additive consumer
// seam: line-faithful Swift port of kits/n4-ptsdur/src/oracle.py - exact
// rational timestamp inventory over saved ffprobe packets/frames JSON plus an
// independent BMFF mvhd/mdhd/tkhd/elst v0/v1 parser. Read-only reference: no
// player verdict, no demuxer/decoder, no best-effort substitution for missing
// PTS. Python<->Swift parity harness in kit: scenario digest diff.
// Mac/Metal NOT_TESTED.

import Foundation

// Exact rational arithmetic mirroring Python's fractions.Fraction for the
// value ranges in the saved probes (Int64-sufficient; reduced at every step).
public struct LabRational: Comparable, CustomStringConvertible {
    public private(set) var n: Int
    public private(set) var d: Int

    static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? abs(a) : gcd(b, a % b) }

    public init(_ n: Int, _ d: Int = 1) throws {
        if d == 0 { throw LabPTSError.invalid("invalid rational: \(n)/0") }
        var nn = n, dd = d
        if dd < 0 { nn = -nn; dd = -dd }
        let g = LabRational.gcd(nn, dd)
        self.n = nn / g
        self.d = dd / g
    }

    public static func parse(_ s: String) throws -> LabRational {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let sl = t.firstIndex(of: "/") {
            let ns = String(t[..<sl]), ds = String(t[t.index(after: sl)...])
            guard let nn = Int(ns), let dd = Int(ds) else { throw LabPTSError.invalid("invalid rational: \(s)") }
            return try LabRational(nn, dd)
        }
        if let i = Int(t) { return try LabRational(i) }
        // exact decimal parse (Fraction accepts decimal strings exactly)
        if let m = t.range(of: "^[+-]?(\\d+)\\.(\\d+)$", options: .regularExpression) {
            let parts = t.split(separator: ".")
            let neg = t.hasPrefix("-")
            let whole = String(parts[0]).replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "-", with: "")
            let frac = String(parts[1])
            guard let w = Int(whole), let fr = Int(frac) else { throw LabPTSError.invalid("invalid rational: \(s)") }
            var den = 1
            for _ in 0..<frac.count { den *= 10 }
            var num = w * den + fr
            if neg { num = -num }
            _ = m
            return try LabRational(num, den)
        }
        throw LabPTSError.invalid("invalid rational: \(s)")
    }

    public var description: String { d == 1 ? "\(n)" : "\(n)/\(d)" }
    public var seconds: Double { Double(n) / Double(d) }

    public static func + (a: LabRational, b: LabRational) throws -> LabRational {
        try LabRational(a.n * b.d + b.n * a.d, a.d * b.d)
    }
    public static func - (a: LabRational, b: LabRational) throws -> LabRational {
        try LabRational(a.n * b.d - b.n * a.d, a.d * b.d)
    }
    public static func < (a: LabRational, b: LabRational) -> Bool { a.n * b.d < b.n * a.d }
    public static func == (a: LabRational, b: LabRational) -> Bool { a.n == b.n && a.d == b.d }
}

public enum LabPTSError: Error, CustomStringConvertible {
    case invalid(String)
    public var description: String {
        switch self { case .invalid(let m): return m }
    }
}

public enum LabPTS {
    /// Python oracle.rational(): nil and the N/A sentinels become nil; anything
    /// unparsable throws.
    public static func rational(_ value: Any?) throws -> LabRational? {
        guard let v = value, !(v is NSNull) else { return nil }
        if let s = v as? String {
            if s == "N/A" || s == "AV_NOPTS_VALUE" { return nil }
            return try LabRational.parse(s)
        }
        if let n = v as? NSNumber {
            let t = String(cString: n.objCType)
            if t == "d" || t == "f" {
                // python str(float) then exact decimal parse; fixtures use ints
                return try LabRational.parse(pyFloat(n.doubleValue))
            }
            return try LabRational.parse(n.stringValue)
        }
        throw LabPTSError.invalid("invalid rational: \(v)")
    }

    public static func tick(_ value: Any?, _ tb: LabRational) throws -> LabRational? {
        guard let v = try rational(value) else { return nil }
        return try LabRational(v.n * tb.n, v.d * tb.d)
    }

    /// Shortest round-trip float text, matching Python repr for these values.
    public static func pyFloat(_ x: Double) -> String {
        if x == x.rounded() && abs(x) < 1e15 { return String(format: "%.1f", x) }
        return "\(x)"
    }

    // MARK: BMFF (mvhd/mdhd/tkhd/elst v0/v1 only, read-only)

    public struct Atom { public let kind: String; public let payload: Data }

    static func u32(_ b: Data, _ o: Int) throws -> Int {
        guard o + 4 <= b.count else { throw LabPTSError.invalid("truncated atom header") }
        return b.withUnsafeBytes { p in Int(p.load(fromByteOffset: o, as: UInt32.self).bigEndian) }
    }
    static func i32(_ b: Data, _ o: Int) throws -> Int {
        guard o + 4 <= b.count else { throw LabPTSError.invalid("truncated atom header") }
        return b.withUnsafeBytes { p in Int(Int32(bitPattern: p.load(fromByteOffset: o, as: UInt32.self).bigEndian)) }
    }
    static func u64(_ b: Data, _ o: Int) throws -> Int {
        guard o + 8 <= b.count else { throw LabPTSError.invalid("truncated extended atom") }
        return b.withUnsafeBytes { p in Int(p.load(fromByteOffset: o, as: UInt64.self).bigEndian) }
    }
    static func i64(_ b: Data, _ o: Int) throws -> Int {
        guard o + 8 <= b.count else { throw LabPTSError.invalid("truncated extended atom") }
        return b.withUnsafeBytes { p in Int(bitPattern: UInt(p.load(fromByteOffset: o, as: UInt64.self).bigEndian)) }
    }
    static func u16(_ b: Data, _ o: Int) throws -> Int {
        guard o + 2 <= b.count else { throw LabPTSError.invalid("truncated edit entry") }
        return b.withUnsafeBytes { p in Int(p.load(fromByteOffset: o, as: UInt16.self).bigEndian) }
    }
    static func i16(_ b: Data, _ o: Int) throws -> Int {
        guard o + 2 <= b.count else { throw LabPTSError.invalid("truncated edit entry") }
        return b.withUnsafeBytes { p in Int(Int16(bitPattern: p.load(fromByteOffset: o, as: UInt16.self).bigEndian)) }
    }

    public static func boxes(_ b: Data, loIn: Int = 0, hiIn: Int? = nil) throws -> [Atom] {
        var lo = loIn
        let hi = hiIn ?? b.count
        var out: [Atom] = []
        while lo < hi {
            if lo + 8 > hi { throw LabPTSError.invalid("truncated atom header") }
            var n = try u32(b, lo)
            let kindData = b[b.index(b.startIndex, offsetBy: lo + 4)..<b.index(b.startIndex, offsetBy: lo + 8)]
            let kind = String(decoding: kindData, as: UTF8.self)
            var hdr = 8
            if n == 1 {
                if lo + 16 > hi { throw LabPTSError.invalid("truncated extended atom") }
                n = try u64(b, lo + 8)
                hdr = 16
            } else if n == 0 {
                n = hi - lo
            }
            if n < hdr || lo + n > hi { throw LabPTSError.invalid("invalid atom size") }
            out.append(Atom(kind: kind, payload: b[b.index(b.startIndex, offsetBy: lo + hdr)..<b.index(b.startIndex, offsetBy: lo + n)]))
            lo += n
        }
        return out
    }

    static func one(_ b: Data, _ kind: String) throws -> Data? {
        try boxes(b).first(where: { $0.kind == kind })?.payload
    }

    public struct TimeHeader {
        public let timescale: Int
        public let durationTicks: Int
        public let duration: LabRational
    }

    public static func times(_ b: Data?) throws -> TimeHeader? {
        guard let b = b else { return nil }
        let ver = b[b.startIndex]
        let scale: Int, duration: Int
        if ver == 0 {
            scale = try u32(b, 12)
            duration = try u32(b, 16)
        } else if ver == 1 {
            scale = try u32(b, 20)
            duration = try u64(b, 24)
        } else {
            throw LabPTSError.invalid("unsupported time header version")
        }
        if scale <= 0 { throw LabPTSError.invalid("zero timescale") }
        return TimeHeader(timescale: scale, durationTicks: duration, duration: try LabRational(duration, scale))
    }

    public struct Edit {
        public let durationMovieTicks: Int
        public let duration: LabRational
        public let mediaTimeTicks: Int
        public let mediaTime: LabRational?
        public let movieSegmentStart: LabRational
        public let emptyEdit: Bool
        public let mediaRate: String
        public let unitRateOffset: LabRational?
    }

    public struct Track {
        public let trackId: Int
        public let mediaHeader: TimeHeader?
        public let edits: [Edit]
    }

    public struct BMFF {
        public let movieHeader: TimeHeader?
        public let tracks: [Track]
    }

    public static func bmff(data b: Data) throws -> BMFF {
        guard let moov = try one(b, "moov") else { throw LabPTSError.invalid("missing moov") }
        let movie = try times(one(moov, "mvhd"))
        var tracks: [Track] = []
        for atom in try boxes(moov) where atom.kind == "trak" {
            let t = atom.payload
            guard let tk = try one(t, "tkhd") else { continue }
            let trackid = try u32(tk, tk[tk.startIndex] == 1 ? 20 : 12)
            guard let mdia = try one(t, "mdia") else { continue }
            let media = try times(one(mdia, "mdhd"))
            var edits: [Edit] = []
            if let ed = try one(t, "edts"), let elst = try one(ed, "elst") {
                let ver = elst[elst.startIndex]
                guard ver == 0 || ver == 1 else { throw LabPTSError.invalid("unsupported elst version") }
                let count = try u32(elst, 4)
                var off = 8
                var timeline = try LabRational(0)
                for _ in 0..<count {
                    let duration: Int, mediaTime: Int, rateI: Int, rateF: Int
                    if ver == 1 {
                        duration = try u64(elst, off)
                        mediaTime = try i64(elst, off + 8)
                        rateI = try i16(elst, off + 16)
                        rateF = try i16(elst, off + 18)
                        off += 20
                    } else {
                        duration = try u32(elst, off)
                        mediaTime = try i32(elst, off + 4)
                        rateI = try i16(elst, off + 8)
                        rateF = try i16(elst, off + 10)
                        off += 12
                    }
                    guard let movieTS = movie?.timescale, let mediaTS = media?.timescale else {
                        throw LabPTSError.invalid("zero timescale")
                    }
                    let length = try LabRational(duration, movieTS)
                    let mt: LabRational? = mediaTime == -1 ? nil : try LabRational(mediaTime, mediaTS)
                    let rate = try LabRational(rateI) + (try LabRational(rateF & 65535, 65536))
                    let one = try LabRational(1)
                    let uro: LabRational? = (mt == nil || rate != one) ? nil : (try timeline - mt!)
                    edits.append(Edit(durationMovieTicks: duration, duration: length,
                                      mediaTimeTicks: mediaTime, mediaTime: mt,
                                      movieSegmentStart: timeline, emptyEdit: mediaTime == -1,
                                      mediaRate: rate.description, unitRateOffset: uro))
                    timeline = try timeline + length
                }
            }
            tracks.append(Track(trackId: trackid, mediaHeader: media, edits: edits))
        }
        return BMFF(movieHeader: movie, tracks: tracks)
    }

    public static func bmff(file path: String) throws -> BMFF {
        try bmff(data: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    // MARK: probe summarization (oracle.summarize)

    public struct StreamRow {
        public var index = 0
        public var codec: String? = nil
        public var type: String? = nil
        public var timeBase = ""
        public var startPts: Any? = nil
        public var origin: LabRational? = nil
        public var reportedStart: Any? = nil
        public var durationTs: Any? = nil
        public var streamDuration: LabRational? = nil
        public var reportedDuration: Any? = nil
        public var packetCount = 0
        public var frameCount = 0
        public var missingPacketPts = 0
        public var missingPacketDts = 0
        public var missingFramePts = 0
        public var missingFrameEnd = 0
        public var firstPacketPts: LabRational? = nil
        public var firstPacketDts: LabRational? = nil
        public var decodedFirstPts: LabRational? = nil
        public var decodedEnd: LabRational? = nil
        public var knownFrameEndMax: LabRational? = nil
        public var decodedSpan: LabRational? = nil
        public var bestEffortCount = 0
        public var skipDiscard: [(pts: Any?, sideData: Any)] = []
    }

    public struct Summary {
        public var formatName: Any? = nil
        public var formatStart: Any? = nil
        public var formatDuration: Any? = nil
        public var streams: [StreamRow] = []
        public var alignOrigin: LabRational? = nil
        public var alignFirstPts: LabRational? = nil
        public var alignEnd: LabRational? = nil
        public var bmff: BMFF? = nil
    }

    /// dict.get(key, fallback): key present-with-null still counts as present.
    static func get(_ d: [String: Any], _ k: String, fallback fk: String? = nil) -> Any? {
        if d.keys.contains(k) { return d[k] is NSNull ? nil : d[k] }
        if let fk = fk { return d[fk] is NSNull ? nil : d[fk] }
        return nil
    }

    public static func summarize(probe: [String: Any], frameprobe: [String: Any], file: String? = nil) throws -> Summary {
        guard let streams = probe["streams"] as? [[String: Any]] else {
            throw LabPTSError.invalid("streams list required")
        }
        let frames = frameprobe["frames"] as? [[String: Any]] ?? []
        let packets = probe["packets"] as? [[String: Any]] ?? []
        var result = Summary()
        let fmt = probe["format"] as? [String: Any] ?? [:]
        result.formatName = fmt["format_name"]
        result.formatStart = fmt["start_time"]
        result.formatDuration = fmt["duration"]
        for s in streams {
            guard let sidAny = s["index"], !(sidAny is NSNull) else {
                throw LabPTSError.invalid("stream index required")
            }
            let sid = (sidAny as? NSNumber)?.intValue ?? Int("\(sidAny)")!
            guard let tb = try rational(s["time_base"]), tb > (try LabRational(0)) else {
                throw LabPTSError.invalid("positive time_base required")
            }
            let ps = packets.filter { (($0["stream_index"] as? NSNumber)?.intValue ?? -1) == sid }
            let fs = frames.filter { (($0["stream_index"] as? NSNumber)?.intValue ?? -1) == sid }
            var pts: [LabRational?] = [], dts: [LabRational?] = [], ends: [LabRational] = [], fpts: [LabRational?] = []
            var missingEnd = 0
            for p in ps {
                pts.append(try tick(p["pts"], tb))
                dts.append(try tick(p["dts"], tb))
            }
            for f in fs {
                // best-effort reported separately, never substituted for absent PTS
                let pt = try tick(get(f, "pts", fallback: "pkt_pts"), tb)
                fpts.append(pt)
                var dur: LabRational? = nil
                let isAudio = (s["codec_type"] as? String) == "audio"
                let nb = f["nb_samples"], sr = s["sample_rate"]
                let nbOk = nb != nil && !(nb is NSNull)
                // python truthiness: missing/None -> false; '' or numeric 0 -> false;
                // a string like "0" stays truthy exactly like python (would raise later).
                let srOk: Bool = {
                    guard let sr = sr, !(sr is NSNull) else { return false }
                    if let s = sr as? String { return !s.isEmpty }
                    if let n = sr as? NSNumber { return n.intValue != 0 }
                    return true
                }()
                if isAudio && nbOk && srOk {
                    let nbI = (nb as? NSNumber)?.intValue ?? Int("\(nb!)")!
                    let srI = (sr as? NSNumber)?.intValue ?? Int("\(sr!)")!
                    dur = try LabRational(nbI, srI)
                } else {
                    dur = try tick(get(f, "duration", fallback: "pkt_duration"), tb)
                }
                if pt == nil || dur == nil { missingEnd += 1 } else { ends.append(try pt! + dur!) }
            }
            let fp = fpts.compactMap { $0 }
            let pp = pts.compactMap { $0 }
            let dd = dts.compactMap { $0 }
            var row = StreamRow()
            row.index = sid
            row.codec = s["codec_name"] as? String
            row.type = s["codec_type"] as? String
            row.timeBase = tb.description
            row.startPts = s["start_pts"]
            row.origin = try tick(s["start_pts"], tb)
            row.reportedStart = s["start_time"]
            row.durationTs = s["duration_ts"]
            row.streamDuration = try tick(s["duration_ts"], tb)
            row.reportedDuration = s["duration"]
            row.packetCount = ps.count
            row.frameCount = fs.count
            row.missingPacketPts = ps.count - pp.count
            row.missingPacketDts = ps.count - dd.count
            row.missingFramePts = fs.count - fp.count
            row.missingFrameEnd = missingEnd
            row.firstPacketPts = pp.min()
            row.firstPacketDts = dd.min()
            row.decodedFirstPts = fp.min()
            row.decodedEnd = (!ends.isEmpty && missingEnd == 0) ? ends.max() : nil
            row.knownFrameEndMax = ends.max()
            row.decodedSpan = (!ends.isEmpty && !fp.isEmpty && missingEnd == 0) ? try ends.max()! - fp.min()! : nil
            row.bestEffortCount = fs.filter { f in f.keys.contains("best_effort_timestamp") && !(f["best_effort_timestamp"] is NSNull) }.count
            row.skipDiscard = ps.filter { $0.keys.contains("side_data_list") }.map { (pts: $0["pts"], sideData: $0["side_data_list"]!) }
            result.streams.append(row)
        }
        let v = result.streams.first(where: { $0.type == "video" })
        let a = result.streams.first(where: { $0.type == "audio" })
        if let v = v, let a = a {
            if let ao = a.origin, let vo = v.origin { result.alignOrigin = try ao - vo }
            if let ap = a.decodedFirstPts, let vp = v.decodedFirstPts { result.alignFirstPts = try ap - vp }
            if let ae = a.decodedEnd, let ve = v.decodedEnd { result.alignEnd = try ae - ve }
        }
        if let file = file {
            let ext = (file as NSString).pathExtension.lowercased()
            if ext == "mp4" || ext == "mov" { result.bmff = try bmff(file: file) }
        }
        return result
    }
}
