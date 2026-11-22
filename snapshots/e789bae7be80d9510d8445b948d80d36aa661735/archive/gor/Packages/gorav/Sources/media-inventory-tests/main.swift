import Foundation
import GorAVCore
import GorAVFFmpegAdapter

// R10 (arch-195b) witness: media inventory over real containers through the
// admitted open path; image-duration rule as pure behavior on typed tracks.

var failures = 0
func check(_ name: String, _ ok: Bool, _ info: String = "") {
    print((ok ? "PASS " : "FAIL ") + name + (ok || info.isEmpty ? "" : " \(info)"))
    if !ok { failures += 1 }
}

let root = ProcessInfo.processInfo.environment["GORAV_REPO"] ?? FileManager.default.currentDirectoryPath
let pins = [URL(fileURLWithPath: root)]

// M-series: muxed mp4 inventory
do {
    let inv = try MediaInventory.load(path: root + "/fixtures/e1-h264-aac-10s.mp4", pinnedRoots: pins)
    check("M1 two tracks", inv.tracks.count == 2, "\(inv.tracks.count)")
    let v = inv.tracks.first { $0.kind == .video }
    let a = inv.tracks.first { $0.kind == .audio }
    check("M2 video track h264 default", v?.codec == "h264" && v?.isDefault == true, "\(String(describing: v))")
    check("M3 audio track aac", a?.codec == "aac", "\(String(describing: a))")
    check("M4 duration about 10s from container", inv.durationSeconds != nil && abs(inv.durationSeconds! - 10.0) < 0.5, "\(String(describing: inv.durationSeconds))")
    check("M5 duration provenance container", inv.effectiveDurationSeconds().provenance == .container)
    check("M6 no chapters is a fact", inv.chapters.isEmpty)
    check("M7 metadata map is typed (may be empty)", inv.metadata.count >= 0)
} catch {
    check("M1 load threw", false, "\(error)")
}

// A-series: audio-only wav inventory
do {
    let inv = try MediaInventory.load(path: root + "/fixtures/tone-48k.wav", pinnedRoots: pins)
    check("A1 one audio track pcm_s16le", inv.tracks.count == 1 && inv.tracks[0].kind == .audio && inv.tracks[0].codec == "pcm_s16le", "\(inv.tracks)")
    check("A2 wav has a container duration", inv.durationSeconds != nil && abs(inv.durationSeconds! - 1.0) < 0.2, "\(String(describing: inv.durationSeconds))")
    check("A3 effective duration is the container one", inv.effectiveDurationSeconds().provenance == .container)
} catch {
    check("A1 wav load threw", false, "\(error)")
}

// I-series: image-duration rule (pure behavior on typed tracks)
func fakeTrack(pic: Bool) -> MediaInventory.Track {
    MediaInventory.Track(index: 0, kind: .video, codec: "mjpeg", language: nil, title: nil, isDefault: true, isAttachedPicture: pic, durationSeconds: nil)
}
let picInv = MediaInventory(tracks: [fakeTrack(pic: true)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("I1 picture-only source gets the image duration", picInv.effectiveDurationSeconds().seconds == MediaInventory.defaultImageDurationSeconds && picInv.effectiveDurationSeconds().provenance == .imageDurationRule)
check("I2 image duration configurable", picInv.effectiveDurationSeconds(imageDuration: 42).seconds == 42)
let vidInv = MediaInventory(tracks: [fakeTrack(pic: false)], chapters: [], metadata: [:], durationSeconds: nil, durationProvenance: .unknown)
check("I3 non-picture source without duration stays unknown", vidInv.effectiveDurationSeconds().seconds == nil && vidInv.effectiveDurationSeconds().provenance == .unknown)
let durInv = MediaInventory(tracks: [fakeTrack(pic: true)], chapters: [], metadata: [:], durationSeconds: 3.5, durationProvenance: .container)
check("I4 container duration wins over the rule", durInv.effectiveDurationSeconds().seconds == 3.5 && durInv.effectiveDurationSeconds().provenance == .container)

// X-series: admission parity with the decoders
do {
    _ = try MediaInventory.load(path: "/etc/hostname", pinnedRoots: pins)
    check("X1 outside pinned roots refused", false, "loaded")
} catch MediaInventory.LoadError.rejected(let m) {
    check("X1 outside pinned roots refused", m.contains("outside pinned roots"), m)
} catch { check("X1 outside pinned roots refused", false, "\(error)") }
do {
    _ = try MediaInventory.load(path: "ftp://example.com/x.mp4", pinnedRoots: pins)
    check("X2 non-admitted scheme refused", false, "loaded")
} catch MediaInventory.LoadError.rejected(let m) {
    check("X2 non-admitted scheme refused", m.contains("scheme not admitted"), m)
} catch { check("X2 non-admitted scheme refused", false, "\(error)") }
do {
    _ = try MediaInventory.load(path: "http://user:s3cr3t@127.0.0.1:1/x.mp4?token=abc123", pinnedRoots: pins)
    check("X3 dead endpoint throws", false, "loaded")
} catch {
    let m = "\(error)"
    check("X3 error redacts credentials", m.contains("REDACTED") && !m.contains("s3cr3t") && !m.contains("abc123"), m)
}

check("I5 shipped image default is two seconds", MediaInventory.defaultImageDurationSeconds == 2)
check("I6 invalid image duration stays unknown", picInv.effectiveDurationSeconds(imageDuration: .nan).seconds == nil)
print(failures == 0 ? "media-inventory-tests: all pass" : "media-inventory-tests: \(failures) FAIL")
exit(failures == 0 ? 0 : 1)
