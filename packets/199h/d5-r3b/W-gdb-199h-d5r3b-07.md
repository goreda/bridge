# W-gdb-199h-d5r3b-07 - Seek per-origin regression (r3: real API surface)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h D4a (r3b, pinned to native50 872dcc32d). The composition lands the per-origin fix via seekTargets() + mediaRelativePosition(streamOrigin:) using seekDescriptor(session:), referenceOrigin and audioTimebase (excerpt below). Lane c: use the real API surface - audioStart is not automatically the API origin - and no separate Python audio model; the fixture must model the excerpted Swift semantics directly. 'verified-not-needed with evidence' is an accepted outcome.

Re-pin note: r3b moves the pin 35f553acd -> 872dcc32d; all excerpt bytes are identical to r3 at the recorded ranges (the only shift is +3 lines before the sess_replace excerpt, now carved at 1660-1720).

Required acceptance: Fixture over the real API semantics: nonzero start_origin per stream, filmTime maps to the correct relative target per origin.

Outcomes: a production change with executed semantic tests, or 'verified-not-needed with evidence' where this packet says so. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs, or the evidence document. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-d5r3b-07",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
 "touched_files": [
  {
   "path": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
   "excerpt_block": "sess_seek_targets (lines 981-1027)"
  }
 ],
 "interface": {
  "signatures": "The composition lands the per-origin fix via seekTargets() + mediaRelativePosition(streamOrigin:) using seekDescriptor(session:), referenceOrigin and audioTimebase (excerpt below). Lane c: use the rea",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Fixture over the real API semantics: nonzero start_origin per stream, filmTime maps to the correct relative target per origin.",
  "callee": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-07.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires: Fixture over the real API semantics: nonzero start_origin per stream, filmTime maps to the correct relative target per origin.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-d5r3b-07",
  "paths": [
   "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
   "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-07.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-07.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T11:50:59.715872+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift",
    "lines": "981-1027",
    "block": "Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift:981-1027",
    "sha256": "949c04a0a7270df1bf75278d7321507b572ecec9af12cd9bc2f612b09992ba70"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-07.py",
    "block": "fixtures1",
    "sha256": "1a854750c4fe8b371bddc3f75c7ffbbe4e82af379129a63188316d9803e90c56"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "d9c78b2a0052aeea7846a39943e124e45c4d118606a6cc335193269af0bdd78f",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-07; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "51a9f01b2abbfb20611431293b06d0887d5fae43bb41e721641378e5af1a33a8"
 }
}
```

```swift id=Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift:981-1027
    // MARK: - Seek (LANDED M4 orchestration; producer stop+join enforced)

    // Absolute film PTS is the UI/presentation coordinate. Each provider
    // consumes a relative coordinate and adds its own descriptor reference.
    // Audio referenceOrigin can be VIDEO origin; audioStart is not its API origin.
    private static func seekTargets(filmTime: RationalTime,
                                    videoOrigin: RationalTime?, videoTimebase: RationalTime,
                                    audioOrigin: RationalTime?, audioTimebase: RationalTime) throws
        -> (video: RationalTime, audio: RationalTime) {
        let video = try filmTime.mediaRelativePosition(streamOrigin: videoOrigin, streamTimebase: videoTimebase)
        let audio = try filmTime.mediaRelativePosition(streamOrigin: audioOrigin, streamTimebase: audioTimebase)
        return (video, audio)
    }

    public func seek(toSeconds seconds: Double) async throws {
        guard !preparedOperation, preparedShot == nil else {
            throw EmbeddedRefusal.seekUnavailable("prepared shot owns video timeline")
        }
        guard !tornDown, !fenced else { throw EmbeddedRefusal.illegalState("tornDownOrFenced") }
        guard plane.seekAllowed else {
            throw EmbeddedRefusal.seekUnavailable("plane state \(plane.state.rawValue)")
        }
        guard let pump, let commit, let decoder, let adec, let audio,
              let issued = session, let bridge, let flag = audioStopFlag else {
            throw EmbeddedRefusal.notOpen
        }
        guard let binding = audioBinding else {
            // Legacy-stale honesty: post-seek audio would continue from its
            // own position; refuse typed instead of folding into an A/V claim.
            throw EmbeddedRefusal.seekUnavailable("descriptor-unavailable:audio-legacy-stale")
        }
        guard seconds >= 0, seconds.isFinite,
              let millis = Int64(exactly: (seconds * 1000).rounded(.towardZero)),
              let filmTime = try? RationalTime(value: millis, timescale: 1000) else {
            throw EmbeddedRefusal.seekUnavailable("invalidTarget")
        }
        guard let videoBinding = decoder.currentBinding(),
              let videoDescriptor = try? decoder.descriptor(for: videoBinding.token),
              videoDescriptor.seekable, let videoTB = videoDescriptor.streamTimebase,
              let audioDescriptor = await adec.seekDescriptor(session: issued),
              audioDescriptor.seekable, audioDescriptor.binding == binding,
              let targets = try? Self.seekTargets(filmTime: filmTime,
                  videoOrigin: videoDescriptor.startOrigin, videoTimebase: videoTB,
                  audioOrigin: audioDescriptor.referenceOrigin, audioTimebase: audioDescriptor.audioTimebase) else {
            throw EmbeddedRefusal.seekUnavailable("targetOriginUnavailableOrInvalid")
        }
        // Descriptor lookup can suspend. Refuse if the live session changed
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Packages/gorav/Sources/GorAVEmbeddedShell/GorAVEmbeddedSession.swift", 981, 1027, "949c04a0a7270df1bf75278d7321507b572ecec9af12cd9bc2f612b09992ba70"]]
bad = []
for rel, a, b, want in CHECKS:
    lines = (ROOT / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-07; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-07; baseline only, product change and semantic test still required
```
