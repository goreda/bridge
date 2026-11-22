import Foundation

/// Matroska/WebM demuxer producing compressed packets in file order with
/// rational timestamps, matching ffmpeg 4.4.2's matroska demuxer semantics:
///  - Stream time base is TimestampScale / 1e9 seconds (default
///    TimestampScale = 1000000 ns, i.e. a 1/1000 s time base).
///  - Packet PTS = DTS = Cluster Timestamp + block timecode, in time-base
///    units. A block in a cluster without a Timestamp element yields nil
///    timestamps (never zero).
///  - Packet duration: BlockDuration when present, else DefaultDuration *
///    laces / TimestampScale (truncating integer division), else 0. A zero
///    duration on PCM audio is filled from the frame size, mirroring
///    ffmpeg's generic fill: floor(frame_samples * tb_den / (rate * tb_num)).
/// Xiph and fixed-size lacing are supported; EBML lacing throws.
public struct MKVDemuxer: PacketDemuxer {

    private struct TrackInfo {
        let number: UInt64
        let kind: String
        let codec: String
        let defaultDuration: UInt64
        let codecDelay: UInt64
        let timecodeScale: Double
        let channels: Int
        let sampleRate: Int
    }

    private struct PacketDesc {
        let trackIndex: Int
        let timecode: Int64?   // in time-base units
        let duration: Int64    // in time-base units, 0 = unknown
        let offset: Int
        let size: Int
    }

    private var data: [UInt8] = []
    private var tracksByNumber: [UInt64: Int] = [:]
    private var trackInfos: [TrackInfo] = []
    private var tbNum: Int64 = 1
    private var tbDen: Int64 = 1000
    private var packets: [PacketDesc] = []
    private var emitIndex: Int = 0

    public init() {}

    public static func looksLikeMKV(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4 && bytes[0] == 0x1A && bytes[1] == 0x45 && bytes[2] == 0xDF && bytes[3] == 0xA3
    }

    public mutating func open(_ bytes: [UInt8]) throws -> [DemuxTrack] {
        if bytes.isEmpty { throw DemuxError.emptyInput }
        guard Self.looksLikeMKV(bytes) else { throw DemuxError.malformed("no EBML header") }
        data = bytes
        tracksByNumber = [:]
        trackInfos = []
        packets = []
        emitIndex = 0

        // EBML header, then Segment.
        var segStart: Int? = nil
        var segEnd: Int? = nil
        var pos = 0
        while pos < bytes.count {
            let (id, hdrLen) = try readID(bytes, pos)
            let (size, sizeLen) = try readSize(bytes, pos + hdrLen)
            let bodyStart = pos + hdrLen + sizeLen
            guard bodyStart + size <= bytes.count else {
                throw DemuxError.truncated("top-level element \(String(id, radix: 16))")
            }
            if id == 0x18538067 { segStart = bodyStart; segEnd = bodyStart + size }
            pos = bodyStart + size
        }
        guard let ss = segStart, let se = segEnd else { throw DemuxError.malformed("no Segment") }

        // Info: TimestampScale (default 1000000).
        var timeScale: UInt64 = 1000000
        if let info = try findElement(bytes, ss, se, 0x1549A966),
           let ts = try findElement(bytes, info.0, info.1, 0x2AD7B1) {
            timeScale = readUInt(bytes, ts.0, ts.1)
        }
        if timeScale == 0 { timeScale = 1000000 }
        // time base = timeScale / 1e9 seconds, reduced
        let g = gcd64(Int64(timeScale), 1_000_000_000)
        tbNum = Int64(timeScale) / g
        tbDen = 1_000_000_000 / g

        // Tracks.
        if let tracksEl = try findElement(bytes, ss, se, 0x1654AE6B) {
            var c = try Cursor(bytes, tracksEl.0, tracksEl.1)
            while c.remaining > 0 {
                let (id, bodyStart, bodyEnd) = try nextElement(&c)
                if id == 0xAE { try parseTrackEntry(bodyStart, bodyEnd) }
                c.pos = bodyEnd
            }
        }
        guard !trackInfos.isEmpty else { throw DemuxError.malformed("no TrackEntry") }

        // Clusters in file order.
        var c = try Cursor(bytes, ss, se)
        while c.remaining > 0 {
            let (id, bodyStart, bodyEnd) = try nextElement(&c)
            if id == 0x1F43B675 {
                try parseCluster(bodyStart, bodyEnd, timeScale: timeScale)
            }
            c.pos = bodyEnd
        }

        return trackInfos.enumerated().map { index, t in
            DemuxTrack(id: index, kind: t.kind, codec: t.codec)
        }
    }

    public mutating func next() throws -> DemuxPacket? {
        guard emitIndex < packets.count else { return nil }
        let p = packets[emitIndex]
        emitIndex += 1
        let payload = try Cursor(data, 0, data.count).slice(p.offset, p.size, "block payload")
        var duration = p.duration
        let track = trackInfos[p.trackIndex]
        if duration == 0, track.kind == "audio",
           let frameSamples = audioFrameSamples(codec: track.codec, channels: track.channels, bytes: p.size),
           track.sampleRate > 0 {
            // Mirrors ffmpeg's generic audio duration fill (AV_ROUND_DOWN).
            duration = Int64(frameSamples) * tbDen / (Int64(track.sampleRate) * tbNum)
        }
        let pts: RationalTime? = p.timecode.map { RationalTime(value: $0 * tbNum, scale: tbDen) }
        return DemuxPacket(
            trackID: p.trackIndex,
            pts: pts,
            dts: pts,
            duration: duration > 0 ? RationalTime(value: duration * tbNum, scale: tbDen) : nil,
            bytes: payload
        )
    }

    // MARK: - EBML primitives

    private func readID(_ b: [UInt8], _ o: Int) throws -> (UInt64, Int) {
        guard o < b.count else { throw DemuxError.truncated("element id") }
        var len = 1
        var mask: UInt8 = 0x80
        while len <= 4 && (b[o] & mask) == 0 { len += 1; mask >>= 1 }
        guard len <= 4, o + len <= b.count else { throw DemuxError.malformed("bad element id at \(o)") }
        var v: UInt64 = 0
        for i in 0 ..< len { v = (v << 8) | UInt64(b[o + i]) }
        return (v, len)
    }

    /// Reads a vint size (marker bit stripped). Unknown sizes throw.
    private func readSize(_ b: [UInt8], _ o: Int) throws -> (Int, Int) {
        guard o < b.count else { throw DemuxError.truncated("element size") }
        var len = 1
        var mask: UInt8 = 0x80
        while len <= 8 && (b[o] & mask) == 0 { len += 1; mask >>= 1 }
        guard len <= 8, o + len <= b.count else { throw DemuxError.malformed("bad element size at \(o)") }
        var v: UInt64 = UInt64(b[o] & (mask - 1))
        for i in 1 ..< len { v = (v << 8) | UInt64(b[o + i]) }
        let unknown: UInt64 = len == 8 ? UInt64.max : (UInt64(1) << (7 * len)) - 1
        guard v != unknown else { throw DemuxError.unsupported("unknown-size element") }
        guard v <= UInt64(Int.max) else { throw DemuxError.unsupported("element size > Int.max") }
        return (Int(v), len)
    }

    private func nextElement(_ c: inout Cursor) throws -> (UInt64, Int, Int) {
        let start = c.pos
        let (id, idLen) = try readID(c.bytes, start)
        let (size, sizeLen) = try readSize(c.bytes, start + idLen)
        let bodyStart = start + idLen + sizeLen
        guard bodyStart + size <= c.end else {
            throw DemuxError.truncated("element \(String(id, radix: 16)) at \(start) size \(size)")
        }
        return (id, bodyStart, bodyStart + size)
    }

    private func findElement(_ b: [UInt8], _ start: Int, _ end: Int, _ want: UInt64) throws -> (Int, Int)? {
        var c = try Cursor(b, start, end)
        while c.remaining > 0 {
            let (id, bodyStart, bodyEnd) = try nextElement(&c)
            if id == want { return (bodyStart, bodyEnd) }
            c.pos = bodyEnd
        }
        return nil
    }

    private func readUInt(_ b: [UInt8], _ s: Int, _ e: Int) -> UInt64 {
        var v: UInt64 = 0
        for i in s ..< e { v = (v << 8) | UInt64(b[i]) }
        return v
    }

    private func readFloat(_ b: [UInt8], _ s: Int, _ e: Int) throws -> Double {
        if e - s == 4 {
            let bits = UInt32(readUInt(b, s, e))
            return Double(Float(bitPattern: bits))
        } else if e - s == 8 {
            return Double(bitPattern: readUInt(b, s, e))
        }
        throw DemuxError.malformed("float element of \(e - s) bytes")
    }

    // MARK: - Tracks

    private mutating func parseTrackEntry(_ start: Int, _ end: Int) throws {
        var number: UInt64 = 0
        var type: UInt64 = 0
        var codecID = ""
        var defaultDuration: UInt64 = 0
        var codecDelay: UInt64 = 0
        var timecodeScale: Double = 1.0
        var channels = 1
        var sampleRate = 8000

        var c = try Cursor(data, start, end)
        while c.remaining > 0 {
            let (id, s, e) = try nextElement(&c)
            switch id {
            case 0xD7: number = readUInt(data, s, e)
            case 0x83: type = readUInt(data, s, e)
            case 0x86: codecID = String(decoding: data[s ..< e], as: UTF8.self)
            case 0x23E383: defaultDuration = readUInt(data, s, e)
            case 0x56AA: codecDelay = readUInt(data, s, e)
            case 0x23314F: timecodeScale = try readFloat(data, s, e)
            case 0xE1:
                var ac = try Cursor(data, s, e)
                while ac.remaining > 0 {
                    let (aid, as_, ae) = try nextElement(&ac)
                    switch aid {
                    case 0x9F: channels = Int(readUInt(data, as_, ae))
                    case 0xB5: sampleRate = Int(try readFloat(data, as_, ae))
                    default: break
                    }
                    ac.pos = ae
                }
            default: break
            }
            c.pos = e
        }
        if timecodeScale < 0.01 { timecodeScale = 1.0 }

        let kind: String
        switch type {
        case 1: kind = "video"
        case 2: kind = "audio"
        case 17: kind = "subtitle"
        default: kind = "other"
        }
        let codec: String
        switch codecID {
        case "V_MPEG4/ISO/AVC": codec = "h264"
        case "V_MPEGH/ISO/HEVC": codec = "hevc"
        case "V_VP8": codec = "vp8"
        case "V_VP9": codec = "vp9"
        case "V_AV1": codec = "av1"
        case "A_AAC": codec = "aac"
        case "A_PCM/INT/LIT": codec = "pcm_s16le"
        case "A_PCM/INT/BIG": codec = "pcm_s16be"
        case "A_PCM/FLOAT/IEEE": codec = "pcm_f32le"
        case "A_OPUS": codec = "opus"
        case "A_VORBIS": codec = "vorbis"
        case "A_FLAC": codec = "flac"
        case "A_MPEG/L3": codec = "mp3"
        default: codec = codecID.isEmpty ? "unknown" : codecID.lowercased()
        }
        let index = trackInfos.count
        trackInfos.append(TrackInfo(number: number, kind: kind, codec: codec,
                                    defaultDuration: defaultDuration, codecDelay: codecDelay,
                                    timecodeScale: timecodeScale, channels: channels,
                                    sampleRate: sampleRate))
        tracksByNumber[number] = index
    }

    // MARK: - Clusters and blocks

    private mutating func parseCluster(_ start: Int, _ end: Int, timeScale: UInt64) throws {
        var clusterTime: Int64? = nil
        var blocks: [(start: Int, end: Int, duration: UInt64?)] = []
        var c = try Cursor(data, start, end)
        while c.remaining > 0 {
            let (id, s, e) = try nextElement(&c)
            switch id {
            case 0xE7:
                clusterTime = Int64(readUInt(data, s, e))
            case 0xA3: // SimpleBlock
                blocks.append((s, e, nil))
            case 0xA0: // BlockGroup
                var blockRange: (Int, Int)? = nil
                var blockDuration: UInt64? = nil
                var gc = try Cursor(data, s, e)
                while gc.remaining > 0 {
                    let (gid, gs, ge) = try nextElement(&gc)
                    if gid == 0xA1 { blockRange = (gs, ge) }
                    if gid == 0x9B { blockDuration = readUInt(data, gs, ge) }
                    gc.pos = ge
                }
                if let br = blockRange { blocks.append((br.0, br.1, blockDuration)) }
            default:
                break
            }
            c.pos = e
        }

        for (bs, be, explicitDuration) in blocks {
            var o = bs
            let (trackNumber, tnLen) = try readSize(data, o) // vint, same coding as size
            o += tnLen
            guard o + 3 <= be else { throw DemuxError.truncated("block header") }
            let blockTime = Int64(Int16(bitPattern: UInt16(data[o]) << 8 | UInt16(data[o + 1])))
            let flags = data[o + 2]
            o += 3
            guard let trackIndex = tracksByNumber[UInt64(trackNumber)] else { continue }
            let track = trackInfos[trackIndex]

            let timecode: Int64?
            if let ct = clusterTime {
                // matroskadec: cluster time is divided by the track timecode scale
                let clusterInTrackTB = Int64(Double(ct) / track.timecodeScale)
                let codecDelayInTB = Int64(track.codecDelay / timeScale)
                timecode = clusterInTrackTB + blockTime - codecDelayInTB
            } else {
                timecode = nil
            }

            let lace = (flags >> 1) & 0x3
            var frames: [(offset: Int, size: Int)] = []
            var laces = 1
            switch lace {
            case 0:
                frames.append((o, be - o))
            case 1: // Xiph lacing
                laces = Int(data[o]) + 1
                o += 1
                var sizes: [Int] = []
                for _ in 0 ..< (laces - 1) {
                    var v = 0
                    while true {
                        guard o < be else { throw DemuxError.truncated("xiph lace size") }
                        let x = Int(data[o]); o += 1
                        v += x
                        if x != 255 { break }
                    }
                    sizes.append(v)
                }
                let used = sizes.reduce(0, +)
                sizes.append(be - o - used)
                for sz in sizes {
                    guard sz >= 0, o + sz <= be else { throw DemuxError.truncated("xiph lace frame") }
                    frames.append((o, sz)); o += sz
                }
            case 2: // fixed-size lacing
                laces = Int(data[o]) + 1
                o += 1
                let per = (be - o) / laces
                guard per * laces == be - o else { throw DemuxError.malformed("fixed lace not divisible") }
                for _ in 0 ..< laces { frames.append((o, per)); o += per }
            default:
                throw DemuxError.unsupported("EBML lacing")
            }

            var blockDuration: UInt64 = explicitDuration ?? 0
            if blockDuration == 0 && track.defaultDuration != 0 {
                // matroskadec: default_duration * laces / time_scale, truncating
                blockDuration = track.defaultDuration * UInt64(laces) / timeScale
            }

            var tc = timecode
            for n in 0 ..< frames.count {
                let dur: Int64
                if laces > 1 {
                    let bl = blockDuration > UInt64(Int64.max) ? Int64.max : Int64(blockDuration)
                    dur = bl * Int64(n + 1) / Int64(laces) - bl * Int64(n) / Int64(laces)
                } else {
                    dur = blockDuration > UInt64(Int64.max) ? Int64.max : Int64(blockDuration)
                }
                packets.append(PacketDesc(trackIndex: trackIndex, timecode: tc,
                                          duration: dur, offset: frames[n].offset, size: frames[n].size))
                if let t = tc { tc = dur > 0 ? t + dur : nil }
            }
        }
    }

    private func audioFrameSamples(codec: String, channels: Int, bytes: Int) -> Int? {
        guard channels > 0 else { return nil }
        switch codec {
        case "pcm_s16le", "pcm_s16be": return bytes / (2 * channels)
        case "pcm_f32le": return bytes / (4 * channels)
        default: return nil
        }
    }
}

func gcd64(_ a0: Int64, _ b0: Int64) -> Int64 {
    var a = a0, b = b0
    while b != 0 { let r = a % b; a = b; b = r }
    return a == 0 ? 1 : abs(a)
}
