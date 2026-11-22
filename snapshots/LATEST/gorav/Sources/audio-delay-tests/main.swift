import Foundation
import GorAVPlaybackCore
import GorAVAudioClockSwift

// R6 (arch-195l) witness: audio track selection policy, audio delay value
// semantics, ControlBus commands, and the pacing read-side delay offset.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

let eng = AudioTrackInfo(index: 1, language: "eng", title: "English", isDefault: false)!
let tur = AudioTrackInfo(index: 2, language: "tur", title: nil, isDefault: true)!
let und = AudioTrackInfo(index: 5, language: nil, title: nil, isDefault: false)!
let tracks = [eng, tur, und]

// A-series: selection
check("A1-auto-default", AudioTrackPlan.select(.auto, from: tracks) == .success(tur))
check("A2-auto-lowest", AudioTrackPlan.select(.auto, from: [eng, und]) == .success(eng))
check("A3-index", AudioTrackPlan.select(.index(5), from: tracks) == .success(und))
check("A4-index-absent", AudioTrackPlan.select(.index(9), from: tracks) == .failure(.requestedIndexAbsent(9)))
check("A5-index-negative", AudioTrackPlan.select(.index(-1), from: tracks) == .failure(.requestedIndexAbsent(-1)))
check("A6-language", AudioTrackPlan.select(.language("ENG"), from: tracks) == .success(eng))
check("A7-language-absent", AudioTrackPlan.select(.language("fra"), from: tracks) == .failure(.requestedLanguageAbsent("fra")))
check("A8-empty", AudioTrackPlan.select(.auto, from: []) == .failure(.noAudioTracks))
check("A9-info-init-guard", AudioTrackInfo(index: -1, language: nil, title: nil, isDefault: false) == nil)

// A-series: delay value
check("A10-delay-valid", AudioDelay(0.25)?.seconds == 0.25 && AudioDelay(-600)?.seconds == -600)
check("A11-delay-refused", AudioDelay(.nan) == nil && AudioDelay(601) == nil && AudioDelay(-600.5) == nil && AudioDelay(.infinity) == nil)

// A-series: ControlBus
var bus = ControlBus(); bus.open()
check("A12-bus-track", bus.send(.setAudioTrack(.index(2))) == .accepted(commandSeq: 1) && bus.state.audioTrack == .index(2))
check("A13-bus-track-negative", bus.send(.setAudioTrack(.index(-2))) == .refused(.outOfRange) && bus.state.audioTrack == .index(2))
check("A14-bus-delay", bus.send(.setAudioDelay(1.5)) == .accepted(commandSeq: 2) && bus.state.audioDelaySeconds == 1.5)
check("A15-bus-delay-nan", bus.send(.setAudioDelay(.nan)) == .refused(.nonFinite))
check("A16-bus-delay-range", bus.send(.setAudioDelay(700)) == .refused(.outOfRange) && bus.state.audioDelaySeconds == 1.5)
bus.close()
check("A17-bus-closed", bus.send(.setAudioDelay(0)) == .refused(.notOpen))

// A-series: pacing read-side delay (FakeClock pattern from GorAVAudioClockTests)
var fakeNow = 100.0
guard let pacing = AudioPacingPolicy(hostClock: { fakeNow }, sampleRate: 48000, consistencyTolerance: 0.002) else {
    print("FAIL pacing init"); exit(1)
}
// anchor: 48000 samples (1.0s) consumed at host 100 -> media value 2.0 at host 101
// sessionStart itself anchors generation 1 (consumed 0 @ host 100, offset 100),
// so the C mapping reads m(101) = 1.0 and value(101) = 101.0. No extra anchor.
pacing.sessionStart(consumedFrames: 0, atHost: 100.0)
fakeNow = 101.0
guard let base = pacing.wallEpochValue(atHost: 101.0) else { print("FAIL base value"); exit(1) }
check("A18-pacing-base", abs(base - 101.0) < 1e-9)
check("A19-delay-shifts-read", pacing.setDelay(seconds: 0.5)
      && abs(pacing.wallEpochValue(atHost: 101.0)! - (base - 0.5)) < 1e-9)
check("A20-delay-negative", pacing.setDelay(seconds: -0.25)
      && abs(pacing.wallEpochValue(atHost: 101.0)! - (base + 0.25)) < 1e-9)
check("A21-delay-counter", pacing.counters.delayChanges == 2)
check("A22-same-value-not-counted", pacing.setDelay(seconds: -0.25) && pacing.counters.delayChanges == 2)
check("A23-delay-refused", !pacing.setDelay(seconds: .nan) && !pacing.setDelay(seconds: 601)
      && pacing.counters.delayChanges == 2
      && abs(pacing.wallEpochValue(atHost: 101.0)! - (base + 0.25)) < 1e-9)
// pause freezes WITH the delay in force; resume reflects a delay changed under pause
check("A24-pause-freeze", pacing.pause(atHost: 101.0)
      && abs(pacing.wallEpochValue(atHost: 102.0)! - (base + 0.25)) < 1e-9)
check("A25-delay-under-pause-held-until-resume", pacing.setDelay(seconds: 1.0)
      && abs(pacing.wallEpochValue(atHost: 102.0)! - (base + 0.25)) < 1e-9)
// resume re-bases the anchor at the frozen value (base + 0.25); the value
// then shifts by exactly -(new delay) = -1.0 relative to that frozen value.
check("A26-resume-reflects-new-delay", pacing.resume(consumedFrames: 48000, atHost: 102.0)
      && abs(pacing.wallEpochValue(atHost: 102.0)! - ((base + 0.25) - 1.0)) < 1e-9)
var fake2 = 100.0
let pacing2 = AudioPacingPolicy(hostClock: { fake2 }, sampleRate: 48000, consistencyTolerance: 0.002)!
pacing2.sessionStart(consumedFrames: 0, atHost: 100.0)
fake2 = 101.0
let base2 = pacing2.wallEpochValue(atHost: 101.0)!
pacing2.setDelay(seconds: 1.0)
check("A27-exact-delta", abs(pacing2.wallEpochValue(atHost: 101.0)! - (base2 - 1.0)) < 1e-12)

// A-series: R6 repair pins - the AudioTrackInfo.init? contract the session
// unwrap relies on (clamp floor stays constructible; select binds index 0).
check("A28-info-init-zero", AudioTrackInfo(index: 0, language: nil, title: nil, isDefault: false) != nil)
check("A29-select-clamped-zero", AudioTrackPlan.select(.index(0), from: [AudioTrackInfo(index: 0, language: nil, title: nil, isDefault: false)!]) == .success(AudioTrackInfo(index: 0, language: nil, title: nil, isDefault: false)!))

print("audio-delay-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
