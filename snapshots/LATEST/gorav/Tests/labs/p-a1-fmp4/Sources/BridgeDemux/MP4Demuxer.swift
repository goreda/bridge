import Foundation

/// ISO BMFF (MP4/MOV) demuxer producing compressed packets with rational
/// timestamps, matching ffmpeg 4.4.2's mov demuxer. Supports progressive
/// (stbl-described) and fragmented (moof/mdat) files, or a mix.
///
/// Timestamp model (validated against ffprobe 4.4.2 output):
///  - Progressive samples: DTS starts at -(media_time) of the first
///    non-empty edit-list entry, minus dts_shift (the magnitude of the most
///    negative CTTS v1 offset). PTS = DTS + dts_shift + CTTS offset.
///    Duration = the sample's STTS delta.
///  - Fragmented samples: DTS starts at the traf's tfdt
///    baseMediaDecodeTime (minus the moov edit-list offset) or, without
///    tfdt, continues after the previous fragment's end; it advances by
///    each sample's duration (trun entry, else tfhd default, else trex
///    default). PTS = DTS + trun CTS offset (0 when absent). Duration is
///    the resolved per-sample value from the fragment tables.
///  - Emission order across tracks (seekable input): the pending sample
///    with the smallest DTS wins, except that samples within a one-second
///    DTS window are ordered by file position (ffmpeg mov_find_next_sample;
///    DTS values are compared after conversion to microseconds with
 ///   round-to-nearest).
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
        let trackID: Int64       // tkhd track_ID; falls back to index+1
        let kind: String
        let codec: String
        let timescale: Int64
        var samples: [Sample]
        var trexDuration: Int64 = 0
        var trexSize: Int64 = 0
        var trexFlags: UInt32 = 0
        var fragmentDtsEnd: Int64? = nil  // running end dts for tfdt-less fragments
        var dtsShift: Int64 = 0
        var timeOffset: Int64 = 0  // moov edit-list offset for this track
    }

    private var data: [UInt8] = []
    private var tracks: [TrackTable] = []
    private var trackIndexByID: [Int64: Int] = [:]
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
        trackIndexByID = [:]
        order = []
        emitIndex = 0

        var moovRange: (Int, Int)? = nil
        var moofRanges: [(Int, Int)] = []
        var c = try Cursor(bytes, 0, bytes.count)
        while c.remaining > 0 {
            let boxStart = c.pos
            let (type, bodyStart, boxEnd) = try nextBox(&c)
            if type == "moov" { moovRange = (bodyStart, boxEnd) }
            if type == "moof" { moofRanges.append((boxStart, boxEnd)) }
            c.pos = boxEnd
        }
        guard let moov = moovRange else { throw DemuxError.malformed("no moov box") }

        // trex defaults (mvex lives in moov, beside trak)
        var trex: [Int64: (duration: Int64, size: Int64, flags: UInt32)] = [:]
        if let mvex = try findBox(moov.0, moov.1, "mvex") {
            var vc = try Cursor(bytes, mvex.0, mvex.1)
            while vc.remaining > 0 {
                let (type, bodyStart, boxEnd) = try nextBox(&vc)
                if type == "trex" {
                    var rc = try Cursor(bytes, bodyStart, boxEnd)
                    _ = try rc.take(4, "trex version/flags")
                    let tid = Int64(try rc.u32("trex track id"))
                    _ = try rc.u32("trex desc index")
                    let dur = Int64(try rc.u32("trex default duration"))
                    let size = Int64(try rc.u32("trex default size"))
                    let flags = try rc.u32("trex default flags")
                    trex[tid] = (dur, size, flags)
                }
                vc.pos = boxEnd
            }
        }

        var mc = try Cursor(bytes, moov.0, moov.1)
        while mc.remaining > 0 {
            let (type, bodyStart, boxEnd) = try nextBox(&mc)
            if type == "trak" {
                var t = try parseTrak(bodyStart, boxEnd)
                if let d = trex[t.trackID] {
                    t.trexDuration = d.duration
                    t.trexSize = d.size
                    t.trexFlags = d.flags
                }
                trackIndexByID[t.trackID] = tracks.count
                tracks.append(t)
            }
            mc.pos = boxEnd
        }
        guard !tracks.isEmpty else { throw DemuxError.malformed("moov contains no trak") }

        for moof in moofRanges {
            try parseMoof(moof.0, moof.1)
        }

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

    // MARK: - Progressive track parsing (stbl)

    private func parseTrak(_ start: Int, _ end: Int) throws -> TrackTable {
        // tkhd: track_ID (for tfhd linkage)
        let (tkhdS, tkhdE) = try requireBox(start, end, "tkhd")
        var trackID: Int64
        var kc = try Cursor(data, tkhdS, tkhdE)
        let tkhdVersion = try kc.u8("tkhd version")
        _ = try kc.take(3, "tkhd flags")
        if tkhdVersion == 1 {
            _ = try kc.u64("tkhd creation"); _ = try kc.u64("tkhd modification")
            trackID = Int64(try kc.u32("tkhd id"))
        } else {
            _ = try kc.u32("tkhd creation"); _ = try kc.u32("tkhd modification")
            trackID = Int64(try kc.u32("tkhd id"))
        }

        let (mdiaS, mdiaE) = try requireBox(start, end, "mdia")

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

        let (hdlrS, _) = try requireBox(mdiaS, mdiaE, "hdlr")
        var hc = try Cursor(data, hdlrS, mdiaE)
        _ = try hc.take(8, "hdlr predef")
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

        // stts
        let (sttsS, sttsE) = try requireBox(stblS, stblE, "stts")
        var tc = try Cursor(data, sttsS, sttsE)
        _ = try tc.take(4, "stts version/flags")
        let sttsCount = Int(try tc.u32("stts count"))
        var deltas: [(count: Int64, delta: Int64)] = []
        var sampleCount: Int64 = 0
        for _ in 0 ..< sttsCount {
            let n = Int64(try tc.u32("stts entry count"))
            let d = Int64(try tc.u32("stts entry delta"))
            deltas.append((n, d))
            sampleCount += n
        }

        // ctts
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

        var dtsShift: Int64 = 0
        if let offs = cttsOffsets {
            for o in offs where o < 0 { dtsShift = max(dtsShift, -o) }
        }

        // elst -> initial dts offset (classic single-edit semantics);
        // applies to both stbl and fragment samples.
        var timeOffset: Int64 = 0
        if let (edtsS, edtsE) = try findBox(start, end, "edts"),
           let (elstS, elstE) = try findBox(edtsS, edtsE, "elst") {
            timeOffset = try parseElst(elstS, elstE)
        }

        var samples: [Sample] = []
        if sampleCount > 0 {
            // stsc
            let (stscS, stscE) = try requireBox(stblS, stblE, "stsc")
            var xc = try Cursor(data, stscS, stscE)
            _ = try xc.take(4, "stsc version/flags")
            let stscCount = Int(try xc.u32("stsc count"))
            var stsc: [(firstChunk: Int64, samplesPerChunk: Int64, desc: Int64)] = []
            for _ in 0 ..< stscCount {
                stsc.append((Int64(try xc.u32("stsc first")), Int64(try xc.u32("stsc spc")), Int64(try xc.u32("stsc desc"))))
            }
            guard !stsc.isEmpty else { throw DemuxError.malformed("stsc empty with \(sampleCount) samples") }

            // stsz
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

            // stco / co64
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

            let base = -timeOffset - dtsShift
            var cur: Int64 = 0
            var i = 0
            samples.reserveCapacity(Int(sampleCount))
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
        }

        return TrackTable(trackID: trackID, kind: kind, codec: codec,
                          timescale: timescale, samples: samples,
                          dtsShift: dtsShift, timeOffset: timeOffset)
    }

    private func parseElst(_ elstS: Int, _ elstE: Int) throws -> Int64 {
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
        guard !edits.isEmpty else { return 0 }
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
        return startTime - emptyDuration
    }

    // MARK: - Fragment parsing (moof/mdat)

    private mutating func parseMoof(_ moofStart: Int, _ moofEnd: Int) throws {
        var hc = try Cursor(data, moofStart, moofEnd)
        let size = Int64(try hc.u32("moof size"))
        _ = try hc.take(4, "moof type")
        if size == 1 { _ = try hc.u64("moof largesize") }
        let moofBodyStart = hc.pos

        var c = try Cursor(data, moofBodyStart, moofEnd)
        while c.remaining > 0 {
            let (type, s, e) = try nextBox(&c)
            if type == "traf" { try parseTraf(s, e, moofStart: moofStart) }
            c.pos = e
        }
    }

    private mutating func parseTraf(_ start: Int, _ end: Int, moofStart: Int) throws {
        var tfhdTrackID: Int64? = nil
        var baseDataOffset: Int64? = nil
        var defDuration: Int64? = nil
        var defSize: Int64? = nil
        var tfdt: Int64? = nil
        var truns: [(Int, Int)] = []

        var c = try Cursor(data, start, end)
        while c.remaining > 0 {
            let (type, s, e) = try nextBox(&c)
            switch type {
            case "tfhd":
                var tc = try Cursor(data, s, e)
                _ = try tc.u8("tfhd version")
                let flags = try { () -> UInt32 in
                    var b0 = UInt32(try tc.u8("tfhd flags0"))
                    b0 = b0 << 8 | UInt32(try tc.u8("tfhd flags1"))
                    b0 = b0 << 8 | UInt32(try tc.u8("tfhd flags2"))
                    return b0
                }()
                tfhdTrackID = Int64(try tc.u32("tfhd track id"))
                if flags & 0x000001 != 0 {
                    let v = try tc.u64("tfhd base offset")
                    guard v <= UInt64(Int64.max) else { throw DemuxError.unsupported("tfhd base offset > Int64.max") }
                    baseDataOffset = Int64(v)
                }
                if flags & 0x000002 != 0 { _ = try tc.u32("tfhd desc index") }
                if flags & 0x000008 != 0 { defDuration = Int64(try tc.u32("tfhd default duration")) }
                if flags & 0x000010 != 0 { defSize = Int64(try tc.u32("tfhd default size")) }
                if flags & 0x000020 != 0 { _ = try tc.u32("tfhd default flags") }
            case "tfdt":
                var tc = try Cursor(data, s, e)
                let version = try tc.u8("tfdt version")
                _ = try tc.take(3, "tfdt flags")
                if version == 1 {
                    let v = try tc.u64("tfdt")
                    guard v <= UInt64(Int64.max) else { throw DemuxError.unsupported("tfdt > Int64.max") }
                    tfdt = Int64(v)
                } else {
                    tfdt = Int64(try tc.u32("tfdt"))
                }
            case "trun":
                truns.append((s, e))
            default:
                break
            }
            c.pos = e
        }

        guard let tid = tfhdTrackID, let trackIndex = trackIndexByID[tid] else {
            throw DemuxError.malformed("traf for unknown track \(tfhdTrackID ?? -1)")
        }
        let base = baseDataOffset ?? Int64(moofStart)

        // Fragment dts is tfdt minus the track's moov edit-list offset
        // (0 for fmp4 written by movenc, which carries no elst).
        let timeOffset = tracks[trackIndex].timeOffset

        var runningDts: Int64 = (tfdt.map { $0 - timeOffset }) ?? tracks[trackIndex].fragmentDtsEnd ?? 0
        var implicitOffset = base
        var newSamples: [Sample] = []

        for (tri, trun) in truns.enumerated() {
            var tc = try Cursor(data, trun.0, trun.1)
            let version = try tc.u8("trun version")
            var flags = UInt32(try tc.u8("trun flags0"))
            flags = flags << 8 | UInt32(try tc.u8("trun flags1"))
            flags = flags << 8 | UInt32(try tc.u8("trun flags2"))
            let count = Int(try tc.u32("trun count"))
            if flags & 0x000001 != 0 {
                let dataOffset = Int64(try tc.i32("trun data offset"))
                implicitOffset = base + dataOffset
            } else if tri > 0 {
                // continues after the previous trun's data (implicitOffset kept)
            }
            if flags & 0x000004 != 0 { _ = try tc.u32("trun first sample flags") }

            for _ in 0 ..< count {
                var dur = defDuration ?? tracks[trackIndex].trexDuration
                var size = defSize ?? tracks[trackIndex].trexSize
                var cts: Int64 = 0
                if flags & 0x000100 != 0 { dur = Int64(try tc.u32("trun sample duration")) }
                if flags & 0x000200 != 0 { size = Int64(try tc.u32("trun sample size")) }
                if flags & 0x000400 != 0 { _ = try tc.u32("trun sample flags") }
                if flags & 0x000800 != 0 {
                    cts = version == 1 ? Int64(try tc.i32("trun cts")) : Int64(try tc.u32("trun cts"))
                }
                guard size >= 0, implicitOffset >= 0,
                      implicitOffset + size <= Int64(data.count) else {
                    throw DemuxError.truncated("fragment sample at \(implicitOffset) size \(size)")
                }
                newSamples.append(Sample(offset: Int(implicitOffset), size: Int(size),
                                         dts: runningDts, pts: runningDts + cts, duration: dur))
                runningDts += dur
                implicitOffset += size
            }
        }

        tracks[trackIndex].samples.append(contentsOf: newSamples)
        tracks[trackIndex].fragmentDtsEnd = runningDts
    }

    // MARK: - Interleave

    /// ffmpeg mov_find_next_sample (seekable input): prefer the pending
    /// sample with the smallest DTS, but when the two candidates are within
    /// one second (DTS compared in microseconds, round-to-nearest), the
    /// earlier file position wins.
    private mutating func buildInterleaveOrder() {
        var positions = [Int](repeating: 0, count: tracks.count)
        let total = tracks.reduce(0) { $0 + $1.samples.count }
        order.reserveCapacity(total)
        while true {
            var best = -1
            var bestDtsUs: Int64 = 0
            var bestPos: Int = 0
            for ti in 0 ..< tracks.count where positions[ti] < tracks[ti].samples.count {
                let s = tracks[ti].samples[positions[ti]]
                let dtsUs = rescaleToMicros(s.dts, timescale: tracks[ti].timescale)
                if best == -1 {
                    best = ti; bestDtsUs = dtsUs; bestPos = s.offset
                } else {
                    let diff = bestDtsUs - dtsUs
                    if diff >= -1_000_000 && diff <= 1_000_000 {
                        if s.offset < bestPos { best = ti; bestDtsUs = dtsUs; bestPos = s.offset }
                    } else if dtsUs < bestDtsUs {
                        best = ti; bestDtsUs = dtsUs; bestPos = s.offset
                    }
                }
            }
            if best == -1 { break }
            order.append((best, positions[best]))
            positions[best] += 1
        }
    }

    /// av_rescale(dts, 1_000_000, timescale) with AV_ROUND_NEAR_INF
    /// (round to nearest, halves away from zero).
    private func rescaleToMicros(_ dts: Int64, timescale: Int64) -> Int64 {
        let r = dts * 1_000_000
        if r >= 0 { return (r + timescale / 2) / timescale }
        return (r - timescale / 2) / timescale
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
