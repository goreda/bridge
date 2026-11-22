import Foundation

/// ISO BMFF (MP4/MOV) demuxer producing compressed packets with rational
/// timestamps in the file's decode order, interleaved across tracks by
/// increasing DTS (ties broken by lower track index), matching the packet
/// order of ffmpeg's mov demuxer.
///
/// Timestamp model (validated against ffprobe 4.4.2 output):
///  - Per-sample DTS starts at -(edit-list media_time) of the first
///    non-empty edit, shifted further by -dts_shift, where dts_shift is the
///    magnitude of the most negative CTTS offset (ctts version 1 only).
///  - PTS = DTS + dts_shift + CTTS offset (or DTS when no CTTS table).
///  - Duration = the sample's STTS delta.
/// This covers single-entry edit lists (including the AAC priming edit with
/// media_time = 1024 written by ffmpeg's muxer) and constant delta tables.
public struct MP4Demuxer: PacketDemuxer {

    private struct Sample {
        let offset: Int
        let size: Int
        let dts: Int64
        let pts: Int64
        let duration: Int64
    }

    private struct TrackTable {
        let kind: String
        let codec: String
        let timescale: Int64
        var samples: [Sample]
    }

    private var data: [UInt8] = []
    private var tracks: [TrackTable] = []
    private var order: [(track: Int, sample: Int)] = []
    private var emitIndex: Int = 0

    public init() {}

    public static func looksLikeMP4(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 12 && bytes[4] == 0x66 && bytes[5] == 0x74 &&
        bytes[6] == 0x79 && bytes[7] == 0x70 // "ftyp" at offset 4
    }

    public mutating func open(_ bytes: [UInt8]) throws -> [DemuxTrack] {
        if bytes.isEmpty { throw DemuxError.emptyInput }
        data = bytes
        tracks = []
        order = []
        emitIndex = 0

        var moovRange: (Int, Int)? = nil
        var c = try Cursor(bytes, 0, bytes.count)
        while c.remaining > 0 {
            let (type, bodyStart, boxEnd) = try nextBox(&c)
            if type == "moov" { moovRange = (bodyStart, boxEnd) }
            if type == "moof" || type == "mvex" {
                throw DemuxError.unsupported("fragmented MP4 (\(type))")
            }
            c.pos = boxEnd
        }
        guard let moov = moovRange else { throw DemuxError.malformed("no moov box") }

        var mc = try Cursor(bytes, moov.0, moov.1)
        while mc.remaining > 0 {
            let (type, bodyStart, boxEnd) = try nextBox(&mc)
            if type == "trak" {
                tracks.append(try parseTrak(bodyStart, boxEnd))
            }
            mc.pos = boxEnd
        }
        guard !tracks.isEmpty else { throw DemuxError.malformed("moov contains no trak") }

        buildInterleaveOrder()

        return tracks.enumerated().map { index, t in
            DemuxTrack(id: index, kind: t.kind, codec: t.codec)
        }
    }

    public mutating func next() throws -> DemuxPacket? {
        guard emitIndex < order.count else { return nil }
        let (ti, si) = order[emitIndex]
        emitIndex += 1
        let t = tracks[ti]
        let s = t.samples[si]
        let payload = try Cursor(data, 0, data.count).slice(s.offset, s.size, "sample data")
        return DemuxPacket(
            trackID: ti,
            pts: RationalTime(value: s.pts, scale: t.timescale),
            dts: RationalTime(value: s.dts, scale: t.timescale),
            duration: RationalTime(value: s.duration, scale: t.timescale),
            bytes: payload
        )
    }

    // MARK: - Box walking

    private func nextBox(_ c: inout Cursor) throws -> (String, Int, Int) {
        let boxStart = c.pos
        var size = Int64(try c.u32("box size"))
        let t = try c.slice4("box type")
        var header = 8
        if size == 1 {
            size = Int64(bitPattern: try c.u64("box largesize"))
            header = 16
        } else if size == 0 {
            size = Int64(c.end - boxStart)
        }
        guard size >= Int64(header), boxStart + Int(size) <= c.end else {
            throw DemuxError.truncated("box \(t) at \(boxStart) size \(size)")
        }
        return (t, boxStart + header, boxStart + Int(size))
    }

    private func findBox(_ start: Int, _ end: Int, _ want: String) throws -> (Int, Int)? {
        var c = try Cursor(data, start, end)
        while c.remaining > 0 {
            let (type, bodyStart, boxEnd) = try nextBox(&c)
            if type == want { return (bodyStart, boxEnd) }
            c.pos = boxEnd
        }
        return nil
    }

    private func requireBox(_ start: Int, _ end: Int, _ want: String) throws -> (Int, Int) {
        guard let r = try findBox(start, end, want) else {
            throw DemuxError.malformed("missing \(want) box")
        }
        return r
    }

    // MARK: - Track parsing

    private func parseTrak(_ start: Int, _ end: Int) throws -> TrackTable {
        let (mdiaS, mdiaE) = try requireBox(start, end, "mdia")

        // mdhd: timescale
        let (mdhdS, _) = try requireBox(mdiaS, mdiaE, "mdhd")
        var c = try Cursor(data, mdhdS, mdiaE)
        let mdhdVersion = try c.u8("mdhd version")
        _ = try c.take(3, "mdhd flags")
        let timescale: Int64
        if mdhdVersion == 1 {
            _ = try c.u64("mdhd creation"); _ = try c.u64("mdhd modification")
            timescale = Int64(try c.u32("mdhd timescale"))
        } else {
            _ = try c.u32("mdhd creation"); _ = try c.u32("mdhd modification")
            timescale = Int64(try c.u32("mdhd timescale"))
        }
        guard timescale > 0 else { throw DemuxError.malformed("mdhd timescale \(timescale)") }

        // hdlr: handler type -> kind
        let (hdlrS, _) = try requireBox(mdiaS, mdiaE, "hdlr")
        var hc = try Cursor(data, hdlrS, mdiaE)
        _ = try hc.take(8, "hdlr predef") // version/flags + predefined
        let handler = try hc.slice4("hdlr type")
        let kind: String
        switch handler {
        case "vide": kind = "video"
        case "soun": kind = "audio"
        case "text", "sbtl": kind = "subtitle"
        default: kind = handler
        }

        let (minfS, minfE) = try requireBox(mdiaS, mdiaE, "minf")
        let (stblS, stblE) = try requireBox(minfS, minfE, "stbl")

        // stsd: codec from sample entry format
        let (stsdS, stsdE) = try requireBox(stblS, stblE, "stsd")
        var sc = try Cursor(data, stsdS, stsdE)
        _ = try sc.take(4, "stsd version/flags")
        let entryCount = try sc.u32("stsd entries")
        guard entryCount >= 1 else { throw DemuxError.malformed("stsd with no entries") }
        _ = try sc.u32("stsd entry size")
        let format = try sc.slice4("stsd format")
        let codec: String
        switch format {
        case "avc1", "avc3": codec = "h264"
        case "hvc1", "hev1": codec = "hevc"
        case "mp4a": codec = "aac"
        case "mp4v": codec = "mp4v"
        case "Opus": codec = "opus"
        case "ac-3": codec = "ac3"
        case "ec-3": codec = "eac3"
        default: codec = format
        }

        // stts: decoding time deltas
        let (sttsS, sttsE) = try requireBox(stblS, stblE, "stts")
        var tc = try Cursor(data, sttsS, sttsE)
        _ = try tc.take(4, "stts version/flags")
        let sttsCount = Int(try tc.u32("stts count"))
        var deltas: [(count: Int64, delta: Int64)] = []
        deltas.reserveCapacity(sttsCount)
        var sampleCount: Int64 = 0
        for _ in 0 ..< sttsCount {
            let n = Int64(try tc.u32("stts entry count"))
            let d = Int64(try tc.u32("stts entry delta"))
            deltas.append((n, d))
            sampleCount += n
        }

        // ctts: composition offsets (optional)
        var cttsOffsets: [Int64]? = nil
        if let (cttsS, cttsE) = try findBox(stblS, stblE, "ctts") {
            var cc = try Cursor(data, cttsS, cttsE)
            let version = try cc.u8("ctts version")
            _ = try cc.take(3, "ctts flags")
            let n = Int(try cc.u32("ctts count"))
            var offs: [Int64] = []
            for _ in 0 ..< n {
                let cnt = try cc.u32("ctts entry count")
                let off: Int64 = version == 1 ? Int64(try cc.i32("ctts offset")) : Int64(try cc.u32("ctts offset"))
                for _ in 0 ..< cnt { offs.append(off) }
            }
            guard offs.count == Int(sampleCount) else {
                throw DemuxError.malformed("ctts expands to \(offs.count), stts has \(sampleCount)")
            }
            cttsOffsets = offs
        }

        // stsc: sample-to-chunk
        let (stscS, stscE) = try requireBox(stblS, stblE, "stsc")
        var xc = try Cursor(data, stscS, stscE)
        _ = try xc.take(4, "stsc version/flags")
        let stscCount = Int(try xc.u32("stsc count"))
        var stsc: [(firstChunk: Int64, samplesPerChunk: Int64, desc: Int64)] = []
        for _ in 0 ..< stscCount {
            stsc.append((Int64(try xc.u32("stsc first")), Int64(try xc.u32("stsc spc")), Int64(try xc.u32("stsc desc"))))
        }
        guard !stsc.isEmpty || sampleCount == 0 else { throw DemuxError.malformed("stsc empty") }

        // stsz: sample sizes
        let (stszS, stszE) = try requireBox(stblS, stblE, "stsz")
        var zc = try Cursor(data, stszS, stszE)
        _ = try zc.take(4, "stsz version/flags")
        let defaultSize = try zc.u32("stsz default size")
        let stszCount = Int(try zc.u32("stsz count"))
        guard stszCount == Int(sampleCount) else {
            throw DemuxError.malformed("stsz count \(stszCount) != stts count \(sampleCount)")
        }
        var sizes: [Int] = []
        sizes.reserveCapacity(stszCount)
        if defaultSize == 0 {
            for _ in 0 ..< stszCount { sizes.append(Int(try zc.u32("stsz size"))) }
        } else {
            for _ in 0 ..< stszCount { sizes.append(Int(defaultSize)) }
        }

        // stco / co64: chunk offsets
        var chunkOffsets: [Int64] = []
        if let (stcoS, stcoE) = try findBox(stblS, stblE, "stco") {
            var oc = try Cursor(data, stcoS, stcoE)
            _ = try oc.take(4, "stco version/flags")
            let n = Int(try oc.u32("stco count"))
            for _ in 0 ..< n { chunkOffsets.append(Int64(try oc.u32("stco offset"))) }
        } else if let (co64S, co64E) = try findBox(stblS, stblE, "co64") {
            var oc = try Cursor(data, co64S, co64E)
            _ = try oc.take(4, "co64 version/flags")
            let n = Int(try oc.u32("co64 count"))
            for _ in 0 ..< n {
                let v = try oc.u64("co64 offset")
                guard v <= UInt64(Int64.max) else { throw DemuxError.unsupported("co64 offset > Int64.max") }
                chunkOffsets.append(Int64(v))
            }
        } else {
            throw DemuxError.malformed("no stco/co64")
        }

        // elst: edit list (optional) -> initial dts offset, classic semantics
        var timeOffset: Int64 = 0
        if let (edtsS, edtsE) = try findBox(start, end, "edts"),
           let (elstS, elstE) = try findBox(edtsS, edtsE, "elst") {
            var ec = try Cursor(data, elstS, elstE)
            let version = try ec.u8("elst version")
            _ = try ec.take(3, "elst flags")
            let n = Int(try ec.u32("elst count"))
            var edits: [(duration: Int64, mediaTime: Int64)] = []
            for _ in 0 ..< n {
                if version == 1 {
                    let d = try ec.u64("elst dur"); let mt = try ec.i64("elst media time")
                    _ = try ec.take(4, "elst rate")
                    guard d <= UInt64(Int64.max) else { throw DemuxError.unsupported("elst v1 duration > Int64.max") }
                    edits.append((Int64(d), mt))
                } else {
                    let d = try ec.u32("elst dur"); let mt = try ec.i32("elst media time")
                    _ = try ec.take(4, "elst rate")
                    edits.append((Int64(d), Int64(mt)))
                }
            }
            if !edits.isEmpty {
                var emptyDuration: Int64 = 0
                var startTime: Int64 = 0
                var editStart = 0
                if edits[0].mediaTime == -1 {
                    emptyDuration = edits[0].duration
                    editStart = 1
                }
                if editStart < edits.count, edits[editStart].mediaTime >= 0 {
                    startTime = edits[editStart].mediaTime
                }
                timeOffset = startTime - emptyDuration
            }
        }

        // dts_shift: magnitude of the most negative ctts offset (ctts v1)
        var dtsShift: Int64 = 0
        if let offs = cttsOffsets {
            for o in offs where o < 0 { dtsShift = max(dtsShift, -o) }
        }

        // Expand samples in chunk order.
        var offsets: [(offset: Int64, size: Int)] = []
        offsets.reserveCapacity(Int(sampleCount))
        var stscIndex = 0
        var sampleIndex = 0
        for chunkIndex in 0 ..< chunkOffsets.count {
            let chunkNo = Int64(chunkIndex + 1)
            while stscIndex + 1 < stsc.count && stsc[stscIndex + 1].firstChunk <= chunkNo {
                stscIndex += 1
            }
            let spc = stsc[stscIndex].samplesPerChunk
            var o = chunkOffsets[chunkIndex]
            for _ in 0 ..< spc {
                guard sampleIndex < sizes.count else { throw DemuxError.malformed("stsc/stsz mismatch") }
                offsets.append((o, sizes[sampleIndex]))
                o += Int64(sizes[sampleIndex])
                sampleIndex += 1
            }
        }
        guard sampleIndex == sizes.count else { throw DemuxError.malformed("stsz count mismatch") }

        // dts prefix sums from stts, with the edit-list/dts-shift base.
        var samples: [Sample] = []
        samples.reserveCapacity(Int(sampleCount))
        let base = -timeOffset - dtsShift
        var cur: Int64 = 0
        var i = 0
        for entry in deltas {
            for _ in 0 ..< entry.count {
                let dts = cur + base
                let pts: Int64
                if let offs = cttsOffsets {
                    pts = dts + dtsShift + offs[i]
                } else {
                    pts = dts
                }
                samples.append(Sample(offset: Int(offsets[i].offset), size: offsets[i].size,
                                      dts: dts, pts: pts, duration: entry.delta))
                cur += entry.delta
                i += 1
            }
        }

        return TrackTable(kind: kind, codec: codec, timescale: timescale, samples: samples)
    }

    // MARK: - Interleave

    /// ffmpeg mov demuxer order: repeatedly emit the pending sample with the
    /// smallest DTS (compared exactly in rational seconds); ties go to the
    /// lower track index. Decode order within a track is preserved.
    private mutating func buildInterleaveOrder() {
        var positions = [Int](repeating: 0, count: tracks.count)
        let total = tracks.reduce(0) { $0 + $1.samples.count }
        order.reserveCapacity(total)
        while true {
            var best = -1
            var bestNum: Int64 = 0
            var bestDen: Int64 = 1
            for ti in 0 ..< tracks.count where positions[ti] < tracks[ti].samples.count {
                let dts = tracks[ti].samples[positions[ti]].dts
                let den = tracks[ti].timescale
                if best == -1 || dts * bestDen < bestNum * den {
                    best = ti
                    bestNum = dts
                    bestDen = den
                }
            }
            if best == -1 { break }
            order.append((best, positions[best]))
            positions[best] += 1
        }
    }
}

private extension Cursor {
    func slice4(_ what: String) throws -> String {
        var c = self
        let p = try c.take(4, what)
        let s = String(decoding: bytes[p ..< p + 4], as: UTF8.self)
        return s
    }
}
