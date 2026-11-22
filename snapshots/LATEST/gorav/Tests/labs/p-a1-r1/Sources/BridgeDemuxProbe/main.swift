import Foundation
import BridgeDemux

// Crash-regression probe for P-A1-R1. Feeds crafted bytes to the demuxer
// inside a disposable process: a clean named error keeps exit code 0; a
// trap/OOM shows up as a nonzero termination status in the parent test.
//
//   BridgeDemuxProbe demux FILE
//       -> "OK tracks=T packets=N payloadBytes=B" or "ERROR <description>"
//   BridgeDemuxProbe reopen GOOD BAD [DRAIN]
//       -> "OPEN1 ...", then "REOPEN-ERROR <description>" or
//          "REOPEN-UNEXPECTED-OK", then "AFTER error <description>" |
//          "AFTER nil" | "AFTER packet ..." (stale leak)

func load(_ path: String) -> [UInt8] {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        print("PROBE-USAGE-ERROR cannot read \(path)")
        exit(2)
    }
    return Array(d)
}

let args = CommandLine.arguments
guard args.count >= 3 else {
    print("PROBE-USAGE-ERROR")
    exit(2)
}

switch args[1] {
case "demux":
    let bytes = load(args[2])
    var d = Demuxer()
    do {
        let tracks = try d.open(bytes)
        var n = 0
        var payload = 0
        while let p = try d.next() {
            n += 1
            payload += p.bytes.count
        }
        print("OK tracks=\(tracks.count) packets=\(n) payloadBytes=\(payload)")
    } catch let e as DemuxError {
        print("ERROR \(e)")
    } catch {
        print("ERROR-FOREIGN \(type(of: error)) \(error)")
    }

case "reopen":
    guard args.count >= 4 else {
        print("PROBE-USAGE-ERROR")
        exit(2)
    }
    let drainCount = args.count >= 5 ? Int(args[4]) ?? 3 : 3
    var d = Demuxer()
    do {
        let good = load(args[2])
        let tracks = try d.open(good)
        var n = 0
        var payload = 0
        while n < drainCount, let p = try d.next() {
            n += 1
            payload += p.bytes.count
        }
        print("OPEN1 tracks=\(tracks.count) drained=\(n) payloadBytes=\(payload)")
    } catch {
        print("OPEN1-UNEXPECTED-ERROR \(error)")
        exit(0)
    }
    do {
        _ = try d.open(load(args[3]))
        print("REOPEN-UNEXPECTED-OK")
    } catch let e as DemuxError {
        print("REOPEN-ERROR \(e)")
    } catch {
        print("REOPEN-ERROR-FOREIGN \(type(of: error)) \(error)")
    }
    do {
        if let p = try d.next() {
            print("AFTER packet trackID=\(p.trackID) bytes=\(p.bytes.count)")
        } else {
            print("AFTER nil")
        }
    } catch let e as DemuxError {
        print("AFTER error \(e)")
    } catch {
        print("AFTER error-foreign \(type(of: error))")
    }

default:
    print("PROBE-USAGE-ERROR")
    exit(2)
}
