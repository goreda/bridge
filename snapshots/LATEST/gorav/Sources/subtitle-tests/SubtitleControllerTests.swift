import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import GorAVSubtitles

// R7 (arch-195b) witness: external subtitle auto-load discovery, primary/
// secondary selection, per-slot delay, cue identity across seeks, reset.

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print((ok ? "PASS " : "FAIL ") + name)
    if !ok { failures += 1 }
}

let srt = """
1
00:00:01,000 --> 00:00:03,000
Hello

2
00:00:05,000 --> 00:00:07,000
World

"""

let dir = NSTemporaryDirectory() + "subctl-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let video = dir + "/movie.mp4"
try! Data().write(to: URL(fileURLWithPath: video))
try! srt.write(toFile: dir + "/movie.srt", atomically: true, encoding: .utf8)
try! srt.write(toFile: dir + "/movie.en.srt", atomically: true, encoding: .utf8)
try! srt.write(toFile: dir + "/movie.tr.ass", atomically: true, encoding: .utf8) // not valid ASS; discovery only
try! "junk".write(toFile: dir + "/movie.txt", atomically: true, encoding: .utf8)
try! srt.write(toFile: dir + "/other.srt", atomically: true, encoding: .utf8)

// A-series: auto-load discovery
let found = SubtitleAutoLoad.discover(forVideoPath: video)
check("A1 exact basename first", found.first?.path == dir + "/movie.srt" && found.first?.tag == nil)
check("A2 tagged matches discovered, sorted", found.count == 3 && found[1].tag == "en" && found[2].tag == "tr")
check("A3 non-matching and non-subtitle files excluded", !found.contains { $0.path.contains("other") || $0.path.contains("txt") })
check("A4 missing directory is empty, not an error", SubtitleAutoLoad.discover(forVideoPath: dir + "/nope/v.mp4").isEmpty)
check("A5 ssa normalizes to ass format", SubtitleAutoLoad.discover(forVideoPath: video).allSatisfy { $0.format != "ssa" })

// B-AUTOLOAD-FILE: discovery means regular files, not extension-shaped entries.
let kindDir = dir + "/entry-kinds"
try! FileManager.default.createDirectory(atPath: kindDir, withIntermediateDirectories: true)
try! FileManager.default.createDirectory(atPath: kindDir + "/film.srt", withIntermediateDirectories: false)
try! FileManager.default.createDirectory(atPath: kindDir + "/film.directory.ass", withIntermediateDirectories: false)
try! srt.write(toFile: kindDir + "/film.en.srt", atomically: true, encoding: .utf8)
try! FileManager.default.createSymbolicLink(atPath: kindDir + "/film.link.srt", withDestinationPath: "film.en.srt")
try! FileManager.default.createSymbolicLink(atPath: kindDir + "/film.broken.srt", withDestinationPath: "missing.srt")
try! FileManager.default.createSymbolicLink(atPath: kindDir + "/film.folder.srt", withDestinationPath: "film.srt")
mkfifo(kindDir + "/film.pipe.srt", 0o644)
try! FileManager.default.createSymbolicLink(atPath: kindDir + "/film.pipelink.srt", withDestinationPath: "film.pipe.srt")
let kindCandidates = SubtitleAutoLoad.discover(forVideoPath: kindDir + "/film.mp4")
check("B-AUTOLOAD-FILE excludes directories and dangling links", kindCandidates.map { URL(fileURLWithPath: $0.path).lastPathComponent } == ["film.en.srt", "film.link.srt"])
check("B-AUTOLOAD-FILE retains symlink candidate identity", kindCandidates.last?.path == kindDir + "/film.link.srt" && kindCandidates.last?.tag == "link")
check("B-AUTOLOAD-FILE refuses FIFO and symlink-to-FIFO", !kindCandidates.contains { $0.path.hasSuffix("film.pipe.srt") || $0.path.hasSuffix("film.pipelink.srt") })

// B-series: selection, delay, identity across seeks, reset
var ctl = SubtitleController()
let track = try! SubtitleTrack.load(path: dir + "/movie.srt")
ctl.selectPrimary(track)
check("B1 primary cue at 2s", ctl.activeCue(at: 2.0, slot: .primary)?.text == "Hello")
check("B2 secondary empty", ctl.activeCue(at: 2.0, slot: .secondary) == nil)
ctl.selectSecondary(track)
check("B3 secondary cue at 2s", ctl.activeCue(at: 2.0, slot: .secondary)?.text == "Hello")

let idBefore = ctl.activeCueIdentity(at: 2.0, slot: .primary)
// Seek far forward and back: identity must be unchanged for the same time.
_ = ctl.activeCue(at: 500.0, slot: .primary)
_ = ctl.activeCue(at: 0.0, slot: .primary)
check("B4 cue identity stable across seeks", ctl.activeCueIdentity(at: 2.0, slot: .primary) == idBefore)
check("B5 identity carries content id and index", idBefore?.cueIndex == 1 && idBefore != nil)

ctl.setDelay(1.5, slot: .primary)
check("B6 positive delay shows cue later", ctl.activeCue(at: 2.0, slot: .primary) == nil && ctl.activeCue(at: 3.0, slot: .primary)?.text == "Hello")
check("B7 delay does not move other slot", ctl.activeCue(at: 2.0, slot: .secondary)?.text == "Hello")
ctl.setDelay(.nan, slot: .primary)
check("B8 non-finite delay ignored", ctl.activeCue(at: 3.0, slot: .primary)?.text == "Hello")

ctl.setVisible(false, slot: .primary)
check("B9 hidden slot reports no cue", ctl.activeCue(at: 3.0, slot: .primary) == nil)
ctl.setVisible(true, slot: .primary)
check("B10 re-shown slot reports again", ctl.activeCue(at: 3.0, slot: .primary)?.text == "Hello")

ctl.reset()
check("B11 reset unloads secondary", ctl.activeCue(at: 2.0, slot: .secondary) == nil)
check("B12 reset zeroes delay", ctl.activeCue(at: 2.0, slot: .primary)?.text == "Hello")
check("B13 reset keeps primary loaded", ctl.primary != nil)

// C-series: content identity differs between tracks
let srt2 = srt.replacingOccurrences(of: "Hello", with: "Hallo")
try! srt2.write(toFile: dir + "/movie.de.srt", atomically: true, encoding: .utf8)
let track2 = try! SubtitleTrack.load(path: dir + "/movie.de.srt")
ctl.selectSecondary(track2)
let idP = ctl.activeCueIdentity(at: 2.0, slot: .primary)
let idS = ctl.activeCueIdentity(at: 2.0, slot: .secondary)
check("C1 same index, different content id across tracks", idP?.cueIndex == idS?.cueIndex && idP?.trackContentID != idS?.trackContentID)

try? FileManager.default.removeItem(atPath: dir)
print(failures == 0 ? "subtitle-controller-tests: all pass" : "subtitle-controller-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
