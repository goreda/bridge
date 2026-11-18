# W-gdb-199f-in2tinct-28 - HLS media sequence exhaustion is typed
state: OPEN / unclaimed

CLASSIFICATION: SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed.
lab: in2tinct

parseMedia must check media and discontinuity sequence increment arithmetic and throw LabHLSError.playlist on unrepresentable next sequence, never trap or wrap. Keep ordinary HLS parsing and duration policy. Source-only lab playlist model, no avformat live transport binding claimed.

All listed production files compile in full; dependencies are read-only, not edit leases.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199f-in2tinct-28",
  "lab": "in2tinct",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "scope": "product",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/LabHLSPlaylist.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "parseMedia must check media and discontinuity sequence increment arithmetic and throw LabHLSError.playlist on unrepresentable next sequence, never trap or wrap. Keep ordinary HLS parsing and duration policy. Source-only lab playlist model, no avformat live transport binding claimed.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "SOURCE-ONLY MODEL. No live adapter/transport/shader wiring or parity acceptance claimed.",
    "callee": "Sources/GorAVPlaybackCore/LabHLSPlaylist.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-28.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199f-in2tinct-28",
    "paths": [
      "Sources/GorAVPlaybackCore/LabHLSPlaylist.swift",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-28.py",
      "Tests/Architecture/199f/W-gdb-199f-in2tinct-28.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199f/W-gdb-199f-in2tinct-28.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "full-source-inputs",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/LabHLSPlaylist.swift",
        "block": "source1",
        "sha256": "69d3253200aa3a241193fffec4134abfa1c7b80c41d24aa245f3789b41a090a0",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-28.py",
        "block": "fixtures1",
        "sha256": "5974f0700f84501377eb62edde0514e10464fb91aa959205f0ddc5ab17d6a3f9"
      },
      {
        "path": "Tests/Architecture/199f/W-gdb-199f-in2tinct-28.json",
        "block": "fixtures2",
        "sha256": "87a3f33dd4700aabb952c01f427ae0a4044202f5ecb9f2e7da4eaddb1efe58d4"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "f98cf3659a960cec9eb55a14cfed42316d07263675fe3a07819449ac5eeba3ef",
    "last_5_lines": [
      "0x0000561d23784000\u20130x0000561d2379b510 <no build ID> test /tmp/tmpy_6qaoyi/test",
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
  "source": "Sources/GorAVPlaybackCore/LabHLSPlaylist.swift",
  "markers": [],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\nlet text=\"#EXTM3U\\n#EXT-X-TARGETDURATION:10\\n#EXT-X-MEDIA-SEQUENCE:\\(Int.max)\\n#EXTINF:1,\\na.ts\\n\"\ndo {_ = try LabHLSPlaylist.parseMedia(text);check(false,\"exhausted sequence refused\")} catch {check(true,\"typed sequence failure\")}\nlet valid=try LabHLSPlaylist.parseMedia(\"#EXTM3U\\n#EXT-X-TARGETDURATION:10\\n#EXTINF:1,\\na.ts\\n\")\ncheck(valid.segments.count == 1,\"normal parse retained\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=-4

*** Signal 4: Backtracing from 0x561d23792fd6... done ***

*** Program crashed: Illegal instruction at 0x0000561d23792fd6 ***

Thread 0 "test" crashed:

0      0x0000561d23792fd6 static LabHLSPlaylist.parseMedia(_:) + 9334 in test
1 [ra] 0x0000561d23797de5 main + 356 in test


Registers:

rax 0x8000000000000001  9223372036854775809
rdx 0x0000000000000000  0
rcx 0x0000561d2379c9f8  b0 b5 78 23 1d 56 00 00 e0 b5 78 23 1d 56 00 00  °µx#·V··àµx#·V··
rbx 0x0000000000000030  48
rsi 0x0000561d427a8d70  61 2e 74 73 00 00 00 00 00 00 00 00 00 00 00 e4  a.ts···········ä
rdi 0x00007ffc45307108  61 2e 74 73 00 00 00 00 00 00 00 00 00 00 00 e4  a.ts···········ä
rbp 0x00007ffc45307430  d0 75 30 45 fc 7f 00 00 e5 7d 79 23 1d 56 00 00  Ðu0Eü···å}y#·V··
rsp 0x00007ffc453067d0  3b 4d a3 9a 00 00 00 00 50 f2 8e 89 4c 7f 00 00  ;M£·····Pò··L···
 r8 0x0000561d2379ca60  00 02 00 00 00 00 00 00 04 89 79 23 1d 56 00 00  ··········y#·V··
 r9 0x0000000000000020  32
r10 0x0000000000000027  39
r11 0x877a594aeb4698cf  9762213320588695759
r12 0x0000000000000000  0
r13 0x00007ffc453072f0  50 8d 7a 42 1d 56 00 00 00 00 00 00 00 00 00 00  P·zB·V··········
r14 0x0000561d2379c858  68 03 de 89 4c 7f 00 00 f0 11 de 89 4c 7f 00 00  h·Þ·L···ð·Þ·L···
r15 0x00007f4c89f68040  e0 92 f6 89 4c 7f 00 00 15 00 00 00 00 00 00 00  à·ö·L···········
rip 0x0000561d23792fd6  0f 0b 0f 0b 66 0f 1f 44 00 00 55 48 89 e5 41 55  ····f··D··UH·åAU

rflags 0x0000000000010202  

cs 0x0033  fs 0x0000  gs 0x0000


Images (19 omitted):

0x0000561d23784000–0x0000561d2379b510 <no build ID> test /tmp/tmpy_6qaoyi/test

Backtrace took 0.00s



```

Publication caveat: NONQUALIFIED. Own replay NOT_RUN; supplied starter is Linux source-only RED, not native/full caller execution. Historical comments confer no permission. SOURCE-ONLY/INERT FILLER: published but excluded from shipping pump stock pending route decision.
