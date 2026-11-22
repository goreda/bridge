// queue 26: demux PTS-semantics parity witness. Compares the lab BridgeDemux (MP4Demuxer/MKVDemuxer via Demuxer)
// against production avformat, per track, on the packet sequence (pts/dts/duration as reduced rationals).
// Output: DIGEST lab fnv=<x>, DIGEST av fnv=<x>, PARITY pass=N fail=M. Exit 0 only when fail=0.
// Linux only / native NOT_RUN. Usage: demux-parity-tests <file>
import Foundation
import BridgeDemux
import CFFmpeg

struct Rat: Equatable, CustomStringConvertible {
    let n: Int64, d: Int64
    init(_ n: Int64, _ d: Int64) {
        var a = n < 0 ? -n : n, b = d
        while b != 0 { (a, b) = (b, a % b) }
        if a == 0 || n == 0 { self.n = 0; self.d = 1 } else { self.n = n / a; self.d = d / a }
    }
    var description: String { "\(n)/\(d)" }
}
struct Pkt: Equatable, CustomStringConvertible {
    var pts: Rat?, dts: Rat?, dur: Rat?
    var description: String { "pts=\(pts?.description ?? "nil") dts=\(dts?.description ?? "nil") dur=\(dur?.description ?? "nil")" }
}
struct Fnv {
    var h: UInt64 = 0xcbf29ce484222325
    mutating func add(_ s: String) { for b in s.utf8 { h ^= UInt64(b); h &*= 0x100000001b3 } ; h ^= 0xff; h &*= 0x100000001b3 }
}

func labSide(_ bytes: [UInt8]) throws -> [[Pkt]] {
    var dx = Demuxer()
    let tracks = try dx.open(bytes)
    var index: [Int: Int] = [:]
    for (i, t) in tracks.enumerated() { index[t.id] = i }
    var out = Array(repeating: [Pkt](), count: tracks.count)
    func r(_ x: RationalTime?) -> Rat? { x.map { Rat($0.value, $0.scale) } }
    while let p = try dx.next() {
        guard let i = index[p.trackID] else { print("FAIL lab packet for unknown track id \(p.trackID)"); continue }
        out[i].append(Pkt(pts: r(p.pts), dts: r(p.dts), dur: r(p.duration)))
    }
    return out
}

func avSide(_ path: String) -> [[Pkt]]? {
    var fc: UnsafeMutablePointer<AVFormatContext>? = nil
    guard avformat_open_input(&fc, path, nil, nil) == 0, let ctx = fc else { return nil }
    defer { var c: UnsafeMutablePointer<AVFormatContext>? = ctx; avformat_close_input(&c) }
    guard avformat_find_stream_info(ctx, nil) >= 0 else { return nil }
    let n = Int(ctx.pointee.nb_streams)
    var out = Array(repeating: [Pkt](), count: n)
    guard let pkt = av_packet_alloc() else { return nil }
    defer { var pp: UnsafeMutablePointer<AVPacket>? = pkt; av_packet_free(&pp) }
    while av_read_frame(ctx, pkt) >= 0 {
        let si = Int(pkt.pointee.stream_index)
        if si >= 0 && si < n, let st = ctx.pointee.streams[si] {
            let tb = st.pointee.time_base
            func r(_ v: Int64) -> Rat? { v == Int64.min ? nil : Rat(v * Int64(tb.num), Int64(tb.den)) }
            let dur: Rat? = pkt.pointee.duration > 0 ? r(pkt.pointee.duration) : (pkt.pointee.duration == 0 ? Rat(0, 1) : nil)
            out[si].append(Pkt(pts: r(pkt.pointee.pts), dts: r(pkt.pointee.dts), dur: dur))
        }
        av_packet_unref(pkt)
    }
    return out
}

@main struct DemuxParity {
    static func main() {
        guard CommandLine.arguments.count > 1 else { print("NOT_RUN: usage demux-parity-tests <file>"); exit(2) }
        let path = CommandLine.arguments[1]
        guard let data = FileManager.default.contents(atPath: path) else { print("NOT_RUN: cannot read \(path)"); exit(2) }
        let lab: [[Pkt]]
        do { lab = try labSide([UInt8](data)) } catch { print("FAIL lab demux error: \(error)"); print("PARITY pass=0 fail=1"); exit(1) }
        guard let av = avSide(path) else { print("NOT_RUN: avformat could not open \(path)"); exit(2) }
        var pass = 0, fail = 0
        func check(_ ok: Bool, _ msg: String) { if ok { pass += 1 } else { fail += 1; print("FAIL \(msg)") } }
        check(lab.count == av.count, "track count lab=\(lab.count) av=\(av.count)")
        var fl = Fnv(), fa = Fnv(), firstDrift: String? = nil
        for t in 0..<min(lab.count, av.count) {
            for p in lab[t] { fl.add("t\(t) \(p)") }
            for p in av[t] { fa.add("t\(t) \(p)") }
            check(lab[t].count == av[t].count, "track \(t) packet count lab=\(lab[t].count) av=\(av[t].count)")
            var bad = false
            for i in 0..<min(lab[t].count, av[t].count) where lab[t][i] != av[t][i] {
                firstDrift = "track \(t) packet \(i) lab[\(lab[t][i])] av[\(av[t][i])]"; bad = true; break
            }
            check(!bad, "track \(t) first drift: \(firstDrift ?? "")")
            print("TRACK \(t) lab=\(lab[t].count) av=\(av[t].count)")
        }
        print("DIGEST lab fnv=\(String(fl.h, radix: 16))")
        print("DIGEST av fnv=\(String(fa.h, radix: 16))")
        print("PARITY pass=\(pass) fail=\(fail)")
        exit(fail == 0 ? 0 : 1)
    }
}
