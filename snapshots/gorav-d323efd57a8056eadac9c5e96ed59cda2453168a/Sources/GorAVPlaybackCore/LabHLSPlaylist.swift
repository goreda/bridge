// Lab HLS playlist model (G0744 / 195b-B5, lab: 1nstinct), additive consumer
// seam: line-faithful Swift port of kits/b5-hlsplay/hlslive.py (master/media
// playlist parsing, variant choice with the pinned POLICY, live edge, session
// state: window/gap/discontinuity/reconnect/seek). The Python carrier with its
// 22-test unittest suite stays vendored in kits/b5-hlsplay as the executable
// witness. The avformat transport driver is NOT part of this seam: it stays in
// the lab lane (see RET-W0284-avformat-einval); this model consumes playlist
// TEXT only, exactly like the Python module.
// Python<->Swift parity harness in kit: scenario-driven digest diff.
// Mac/Metal NOT_TESTED (pure value-type model, no Metal involvement).

import Foundation

public enum LabHLSError: Error, Equatable, CustomStringConvertible {
    case playlist(String)
    public var description: String {
        switch self { case .playlist(let m): return m }
    }
}

public struct LabHLSVariant: Equatable {
    public var uri: String
    public var bandwidth: Int
    public var avgBandwidth: Int = 0
    public var width: Int = 0
    public var height: Int = 0
    public var codecs: String = ""
    public var frameRate: Double = 0.0
    public init(uri: String, bandwidth: Int) { self.uri = uri; self.bandwidth = bandwidth }
}

public struct LabHLSSegment: Equatable {
    public var uri: String
    public var duration: Double
    public var seq: Int
    public var discontinuity: Bool = false
    public var discSeq: Int = 0
    public init(uri: String, duration: Double, seq: Int) {
        self.uri = uri; self.duration = duration; self.seq = seq
    }
}

public struct LabHLSMedia: Equatable {
    public var target: Int = 0
    public var mediaSeq: Int = 0
    public var discSeq: Int = 0
    public var ended: Bool = false
    public var playlistType: String = ""
    public var segments: [LabHLSSegment] = []
    public var holdBack: Double = 0.0
    public var version: Int = 1
    public init() {}
}

public enum LabHLSPlaylist {

    // Mirror of hlslive._ATTR = ([A-Z0-9-]+)=("[^"]*"|[^,]*)
    public static func parseAttrs(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        var i = s.startIndex
        while i < s.endIndex {
            guard let eq = s[i...].firstIndex(of: "=") else { break }
            let key = String(s[i..<eq])
            guard !key.isEmpty, key.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "-" }) else {
                i = s.index(after: eq); continue
            }
            var j = s.index(after: eq)
            var value: String
            if j < s.endIndex && s[j] == "\"" {
                guard let close = s[s.index(after: j)...].firstIndex(of: "\"") else { break }
                value = String(s[s.index(after: j)..<close])
                j = s.index(after: close)
            } else {
                let close = s[j...].firstIndex(of: ",") ?? s.endIndex
                value = String(s[j..<close])
                j = close
            }
            out[key] = value
            i = j
            if i < s.endIndex && s[i] == "," { i = s.index(after: i) }
            // regex findall semantics: resume scanning at j; any text between
            // matches is skipped because we only accept KEY= at match start.
            if i < s.endIndex, s[i] != "," {
                // advance to next plausible key start (regex would skip freely)
                var k = i
                while k < s.endIndex {
                    if let eq2 = s[k...].firstIndex(of: "=") {
                        let cand = s[k..<eq2]
                        if !cand.isEmpty, cand.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "-" }) { break }
                        k = s.index(after: eq2)
                    } else { k = s.endIndex }
                }
                i = k
            }
        }
        return out
    }

    static func toInt(_ v: String, _ what: String) throws -> Int {
        guard let n = Int(v) else { throw LabHLSError.playlist("bad \(what): '\(v)'") }
        return n
    }
    static func toDouble(_ v: String, _ what: String) throws -> Double {
        guard let n = Double(v) else { throw LabHLSError.playlist("bad \(what): '\(v)'") }
        return n
    }

    static func strippedLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public static func parseMaster(_ text: String) throws -> [LabHLSVariant] {
        let lines = strippedLines(text)
        guard !lines.isEmpty, lines[0] == "#EXTM3U" else { throw LabHLSError.playlist("missing #EXTM3U") }
        var out: [LabHLSVariant] = []
        var pend: [String: String]? = nil
        for l in lines.dropFirst() {
            if l.hasPrefix("#EXT-X-STREAM-INF:") {
                pend = parseAttrs(String(l.dropFirst("#EXT-X-STREAM-INF:".count)))
            } else if !l.hasPrefix("#"), let p = pend {
                guard let bwRaw = p["BANDWIDTH"] else { throw LabHLSError.playlist("STREAM-INF without BANDWIDTH") }
                let resParts = (p["RESOLUTION"] ?? "0x0").split(separator: "x", omittingEmptySubsequences: false).map(String.init)
                let w = resParts.count > 0 ? resParts[0] : "0"
                let h = resParts.count > 1 ? resParts[1] : "0"
                var v = LabHLSVariant(uri: l, bandwidth: try toInt(bwRaw, "BANDWIDTH"))
                v.avgBandwidth = try toInt(p["AVERAGE-BANDWIDTH"] ?? "0", "AVERAGE-BANDWIDTH")
                v.width = try toInt(w, "RESOLUTION")
                v.height = try toInt(h, "RESOLUTION")
                v.codecs = p["CODECS"] ?? ""
                v.frameRate = try toDouble((p["FRAME-RATE"].flatMap { $0.isEmpty ? nil : $0 } ?? "0"), "FRAME-RATE")
                out.append(v)
                pend = nil
            }
        }
        return out
    }

    public static func parseMedia(_ text: String) throws -> LabHLSMedia {
        let lines = strippedLines(text)
        guard !lines.isEmpty, lines[0] == "#EXTM3U" else { throw LabHLSError.playlist("missing #EXTM3U") }
        var m = LabHLSMedia()
        var dur: Double? = nil
        var disc = false
        var seq: Int? = nil
        var dseq = 0
        for l in lines.dropFirst() {
            if l.hasPrefix("#EXT-X-TARGETDURATION:") {
                m.target = try toInt(String(l.dropFirst("#EXT-X-TARGETDURATION:".count)), "TARGETDURATION")
            } else if l.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
                m.mediaSeq = try toInt(String(l.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count)), "MEDIA-SEQUENCE")
            } else if l.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE:") {
                m.discSeq = try toInt(String(l.dropFirst("#EXT-X-DISCONTINUITY-SEQUENCE:".count)), "DISCONTINUITY-SEQUENCE")
                dseq = m.discSeq
            } else if l.hasPrefix("#EXT-X-VERSION:") {
                m.version = try toInt(String(l.dropFirst("#EXT-X-VERSION:".count)), "VERSION")
            } else if l.hasPrefix("#EXT-X-PLAYLIST-TYPE:") {
                m.playlistType = String(l.dropFirst("#EXT-X-PLAYLIST-TYPE:".count))
            } else if l.hasPrefix("#EXT-X-SERVER-CONTROL:") {
                m.holdBack = try toDouble(parseAttrs(String(l.dropFirst("#EXT-X-SERVER-CONTROL:".count)))["HOLD-BACK"] ?? "0", "HOLD-BACK")
            } else if l == "#EXT-X-ENDLIST" {
                m.ended = true
            } else if l == "#EXT-X-DISCONTINUITY" {
                disc = true
            } else if l.hasPrefix("#EXTINF:") {
                let raw = String(l.dropFirst("#EXTINF:".count))
                let num = String(raw.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                guard let d = Double(num) else { throw LabHLSError.playlist("bad EXTINF") }
                guard d.isFinite, d >= 0 else { throw LabHLSError.playlist("EXTINF must be finite and >= 0") }
                dur = d
            } else if !l.hasPrefix("#") {
                guard let d = dur else { throw LabHLSError.playlist("URI without EXTINF") }
                if seq == nil { seq = m.mediaSeq }
                if disc { dseq += 1 }
                var s = LabHLSSegment(uri: l, duration: d, seq: seq!)
                s.discontinuity = disc
                s.discSeq = dseq
                m.segments.append(s)
                seq! += 1
                dur = nil
                disc = false
            }
        }
        if dur != nil { throw LabHLSError.playlist("trailing EXTINF without URI") }
        if m.target == 0 { throw LabHLSError.playlist("missing TARGETDURATION") }
        for s in m.segments where s.duration > Double(m.target) + 0.5 {
            throw LabHLSError.playlist("segment exceeds TARGETDURATION")
        }
        return m
    }

    static func codecOk(_ codecs: String, _ supported: [String]?) -> Bool {
        if codecs.isEmpty || supported == nil { return true }
        return codecs.split(separator: ",").allSatisfy { c in
            let t = c.trimmingCharacters(in: .whitespaces)
            return supported!.contains { t.hasPrefix($0) }
        }
    }

    // AUTHORITATIVE VARIANT POLICY (hlslive.POLICY, model and driver must match):
    // 1. admit only codec-supported variants; 2. height cap: probed height is
    // truth, playlist RESOLUTION only a hint, cap rejects unknown height;
    // 3. highest bandwidth <= safety(0.8)*measured, else lowest admitted;
    // 4. up-switch hysteresis 1.25 with a current variant.
    public static func chooseVariant(_ variants: [LabHLSVariant], bandwidthBps: Double,
                                     maxHeight: Int? = nil, supportedCodecs: [String]? = nil,
                                     safety: Double = 0.8, current: LabHLSVariant? = nil,
                                     switchUpMargin: Double = 1.25,
                                     probedHeights: [String: Int]? = nil) throws -> LabHLSVariant {
        func h(_ v: LabHLSVariant) -> Int {
            if let ph = probedHeights, let p = ph[v.uri] { return p }
            return v.height
        }
        var ok = variants.filter { codecOk($0.codecs, supportedCodecs) && (maxHeight == nil || (h($0) != 0 && h($0) <= maxHeight!)) }
        if ok.isEmpty { throw LabHLSError.playlist("no supported variant") }
        ok.sort { $0.bandwidth < $1.bandwidth }
        let budget = bandwidthBps * safety
        let fit = ok.filter { Double($0.bandwidth) <= budget }
        var pick = fit.last ?? ok[0]
        if let cur = current, pick.bandwidth > cur.bandwidth, ok.contains(cur) {
            if budget < Double(pick.bandwidth) * switchUpMargin { pick = cur }
        }
        return pick
    }

    // Live: 3 target durations from end (or HOLD-BACK / behind). VOD/ENDLIST:
    // first segment. Returns (seq, live).
    public static func liveEdge(_ m: LabHLSMedia, behind: Double? = nil) throws -> (Int, Bool) {
        if m.segments.isEmpty { throw LabHLSError.playlist("empty playlist") }
        if m.ended { return (m.segments[0].seq, false) }
        let hb = behind ?? (m.holdBack != 0 ? m.holdBack : 3.0 * Double(m.target))
        var acc = 0.0
        for s in m.segments.reversed() {
            acc += s.duration
            if acc >= hb { return (s.seq, true) }
        }
        return (m.segments[0].seq, true)
    }
}

public final class LabHLSSession {
    public var nextSeq: Int? = nil
    public var discSeq: Int = 0
    public var cache: [Int: String] = [:]
    public var cacheLimit: Int
    public var seekable = false
    public var live = true
    public var ended = false
    public var failures = 0
    public var maxFailures: Int
    public var state = "init"           // init|playing|reconnecting|failed|ended
    public private(set) var events: [LabHLSEvent] = []
    public var window: (Int, Int) = (0, 0)
    public var eventsLimit: Int

    public init(maxFailures: Int = 5, cacheLimit: Int = 8, eventsLimit: Int = 64) {
        self.maxFailures = maxFailures
        self.cacheLimit = cacheLimit
        self.eventsLimit = eventsLimit
    }

    public enum LabHLSEvent: Equatable, CustomStringConvertible {
        case emptyPlaylist
        case gap(from: Int, to: Int)
        case playlistRegressed(next: Int, lastPlusOne: Int)
        case discontinuity(seq: Int, discSeq: Int)
        public var description: String {
            switch self {
            case .emptyPlaylist: return "(empty_playlist)"
            case .gap(let a, let b): return "(gap,\(a),\(b))"
            case .playlistRegressed(let a, let b): return "(playlist_regressed,\(a),\(b))"
            case .discontinuity(let a, let b): return "(discontinuity,\(a),\(b))"
            }
        }
    }

    func eventsAdd(_ e: LabHLSEvent) {
        events.append(e)
        if events.count > eventsLimit { events.removeFirst(events.count - eventsLimit) }
    }

    // Apply a refreshed playlist. Returns segments to fetch.
    @discardableResult
    public func update(_ m: LabHLSMedia) -> [LabHLSSegment] {
        if m.segments.isEmpty {
            eventsAdd(.emptyPlaylist)
            return []
        }
        live = !m.ended
        ended = m.ended
        let first = m.segments[0].seq, last = m.segments[m.segments.count - 1].seq
        window = (first, last)
        seekable = m.ended || m.playlistType == "VOD" || m.playlistType == "EVENT"
        if nextSeq == nil {
            nextSeq = (try? LabHLSPlaylist.liveEdge(m))?.0 ?? first
        } else if nextSeq! < first {
            eventsAdd(.gap(from: nextSeq!, to: first))
            nextSeq = first
        } else if nextSeq! > last + 1 {
            eventsAdd(.playlistRegressed(next: nextSeq!, lastPlusOne: last + 1))
            nextSeq = last + 1
        }
        let out = m.segments.filter { $0.seq >= nextSeq! }
        for s in out where s.discontinuity {
            eventsAdd(.discontinuity(seq: s.seq, discSeq: s.discSeq))
        }
        failures = 0
        if state == "init" || state == "reconnecting" { state = "playing" }
        if m.ended && out.isEmpty { state = "ended" }
        return out
    }

    public func consumed(_ seg: LabHLSSegment) {
        nextSeq = seg.seq + 1
        discSeq = seg.discSeq
        cache[seg.seq] = seg.uri
        while cache.count > cacheLimit {
            if let mink = cache.keys.min() { cache.removeValue(forKey: mink) }
        }
    }

    // Backoff seconds, or nil when failed permanently.
    @discardableResult
    public func fetchFailed(retryDelayBase: Double = 1.0) -> Double? {
        failures += 1
        if failures > maxFailures { state = "failed"; return nil }
        state = "reconnecting"
        return min(retryDelayBase * pow(2.0, Double(failures - 1)), 30.0)
    }

    // Seek within the playlist window. Not seekable on sliding live windows.
    @discardableResult
    public func seek(_ targetS: Double, _ m: LabHLSMedia) throws -> (Int, Double) {
        guard seekable else { throw LabHLSError.playlist("not seekable (sliding live window)") }
        guard targetS >= 0, targetS.isFinite else { throw LabHLSError.playlist("seek target must be finite and >= 0") }
        var acc = 0.0
        for s in m.segments {
            if acc + s.duration > targetS {
                nextSeq = s.seq
                return (s.seq, targetS - acc)
            }
            acc += s.duration
        }
        throw LabHLSError.playlist("seek beyond end")
    }
}
