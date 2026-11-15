# W-gdb-034 end-of-stream signaling vectors
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-034

```packet-json
{
 "packet_id": "W-gdb-034",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "touched_files": [
  {
   "path": "Sources/GorAVPlaybackCore/PlaybackCore.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "onEvent?(.ended(reason: String))",
  "types": "reason strings exactly: eof | sourceEnded | windowClosed | cancelled; one terminal event per pump run",
  "ownership_lifetime": "event log replay; synthetic streams; one terminal event per pump run",
  "caller": "EOS vector checker",
  "callee": "session event sink .ended(reason: String) with exact strings eof/sourceEnded/windowClosed/cancelled (pinned below)"
 },
 "test": {
  "command": "python3 kits/eos-vectors/check.py",
  "expected": "exit 0; stdout 'eos-vectors: all vectors PASS'; each vector matches its expected event sequence with typed reasons; a seeded early EOS fails",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "kits/eos-vectors/"
  ],
  "return_form": "full-files"
 }
}
```

## problem (what fails for the user)
EOS must signal exactly once, at true end, with the typed reason; early EOS (during pause) or late/duplicated EOS shows as a truncated clip or a stuck-at-end player.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; PR #3 head).
- real source: Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51; PumpEndReason excerpt below).
- real test command: the returned checker runs on Linux against a candidate pipeline log.

## expected behaviour
EOS event-ordering vectors: video-only EOF, audio-only EOF, joint EOF, late packets after one stream's EOF, EOF during pause (must not signal early), EOF exactly at a seek target; expected event sequences with typed reasons.

## exact call site and interface
PumpEndReason.endOfStream + the session's ended(reason:) vocabulary (pinned excerpt and pin) are asserted.

## pinned ABI decisions (integrator, 2026-11-15; ended(reason:) interface)
the session's terminal event is the typed enum case .ended(reason: String) on the session event sink (GorAVEmbeddedSession.swift, same pin; onEvent?(.ended(reason:))). reason strings at the pin are EXACTLY: "eof" (PumpEndReason.endOfStream), "sourceEnded", "windowClosed" (cancelled with the window closed), "cancelled" (any other cancel). mapping at the pin (session pump-end switch): .endOfStream -> "eof"; .sourceEnded -> "sourceEnded"; .cancelled + windowClosed -> "windowClosed"; .cancelled -> "cancelled"; failures ride their typed code path, not a bare string guess. EOS vectors assert these exact strings, in order, exactly one terminal event per pump run.

## behaviour that must not change
the typed-reason vocabulary stays; synthetic streams only.

## acceptance test (from the product repo)
each vector's expected event sequence matches; a seeded early EOS fails.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/PlaybackCore.swift (sha256 0a128f51, lines 233-245 of 1382)
```swift id=source1
public enum PumpEndReason: Sendable, Equatable {
    case none            // pre-finalization only; impossible after run()
    case endOfStream
    case sourceEnded
    case cancelled
    case failed(Int32)
    public var rawValue: String {
        switch self {
        case .none: return "none"
        case .endOfStream: return "endOfStream"
        case .sourceEnded: return "sourceEnded"
        case .cancelled: return "cancelled"
        case .failed(let c): return "failed:\(c)"
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed (writes failure cases first, blind to the fix). neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
{"vector":"eof-during-pause","events":["pause","videoEOF","audioEOF","resume","trueEOF"],"expect":["<no ended before trueEOF>","ended(eof)"]}
```
