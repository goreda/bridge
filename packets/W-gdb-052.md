# W-gdb-052 195b-B10 music mode classification + artwork identity: consuming pin (identity/classification-only scope)
state: candidate
solver lab: 1nstinct
reviewer lab: unclaimed
id: W-gdb-052

```packet-json
{
 "packet_id": "W-gdb-052",
 "writer": "gdb",
 "code_owner": "gdb integrator (gorav lane)",
 "product_repo": "goreda/gorav",
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
 "scope": "product",
 "touched_files": [
  {
   "path": "Sources/GorAVFFmpegAdapter/MediaInventory.swift",
   "excerpt_block": "source1"
  }
 ],
 "interface": {
  "signatures": "MediaInventory.Track { index, kind, codec, language?, title?, isDefault, isAttachedPicture, durationSeconds? } (pinned excerpt); additive music-session classification + artwork PRESENCE identity (track index + declared codec) from isAttachedPicture; NO artwork byte read API is introduced at this pin",
  "types": "TrackKind { video, audio, subtitle, data, other }; music-session = audio present AND NO non-attached-picture video track (an attached-picture artwork track does not disqualify music mode); artwork bytes are NOT part of the pinned inventory ABI (Track carries identity only) and byte extraction is OUT OF SCOPE at this pin (no pinned read API exists to pin it against)",
  "ownership_lifetime": "inventory values immutable; no byte copies in scope (identity only); no retained demux references",
  "caller": "session/inventory surface (GorAVEmbeddedSession metadata path)",
  "callee": "the lab music-mode module behind the pinned inventory surface"
 },
 "test": {
  "command": "python3 kits/b10-music-pin/check.py kits/b10-music-pin/fixtures.json",
  "expected": "exit 0; stdout 'b10-music-pin: 3/3 rows PASS'; artwork presence reported as track identity (index + codec) only; absence stays nil",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "ohal/gorav",
  "paths": [
   "Sources/GorAVFFmpegAdapter/",
   "kits/b10-music-pin/"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
music mode classification and artwork presence (195b-B10) need a pinned session/identity seam; without it audio-only files mis-present and artwork presence is guessed from unrelated signals.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav; this pin is PR #3 head).
- real source: see pinned excerpts below
- this packet is the consuming-side pin for legacy 195b target W-0287/B10; the lab module implements against the pinned interface below.

## expected behaviour
a music-mode module on the pinned inventory surface, IDENTITY/CLASSIFICATION ONLY: MediaInventory.Track.isAttachedPicture marks artwork tracks (pinned); a music session is typed when the inventory has audio and NO non-attached-picture video track (attached-picture artwork tracks do not count as video for this rule); artwork is reported as PRESENCE IDENTITY only (which track index carries the attached picture + its declared codec string from the pinned Track fields); artwork absence stays nil; the session surface reports music mode through existing inventory/session types (additive reporting only). Artwork BYTE extraction is explicitly OUT OF SCOPE for this packet: at pin 2112af0d there is no pinned track-bytes read API (verified: CFFmpeg/shim.h exposes no av_read_frame/packet read wrapper and no artwork reader exists in the adapter tree), so no honest read(trackIndex...) contract, lifetime rule or caller excerpt can be pinned here; extraction needs a future packet that pins a real read contract plus source fixture first. The module must NOT invent one.

## exact call site and interface
MediaInventory.swift (pinned excerpt) is the inventory seam; the module consumes the inventory and session metadata; delivery as module code + kits/b10-music-pin/ fixtures.

## behaviour that must not change
MediaInventory field semantics (language/title/isDefault/isAttachedPicture) untouched; artwork never synthesized; no artwork byte API is invented (identity/classification only).

## acceptance test (from the product repo)
python3 kits/b10-music-pin/check.py kits/b10-music-pin/fixtures.json exits 0; the three golden containers map to their typed session/artwork-identity outcomes.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVFFmpegAdapter/MediaInventory.swift (sha256 bbc46476, lines 11-45 of 210)
```swift id=source1
public struct MediaInventory: Equatable, Sendable {

    public enum TrackKind: String, Equatable, Sendable { case video, audio, subtitle, data, other }

    public struct Track: Equatable, Sendable {
        public let index: Int
        public let kind: TrackKind
        public let codec: String
        public let language: String?
        public let title: String?
        public let isDefault: Bool
        public let isAttachedPicture: Bool
        /// Container-reported duration, nil when the stream reports none.
        public let durationSeconds: Double?

        public init(index: Int, kind: TrackKind, codec: String, language: String?, title: String?, isDefault: Bool, isAttachedPicture: Bool, durationSeconds: Double?) {
            self.index = index
            self.kind = kind
            self.codec = codec
            self.language = language
            self.title = title
            self.isDefault = isDefault
            self.isAttachedPicture = isAttachedPicture
            self.durationSeconds = durationSeconds
        }
    }

    public struct Chapter: Equatable, Sendable {
        public let index: Int
        public let title: String?
        public let startSeconds: Double
        public let endSeconds: Double

        public init(index: Int, title: String?, startSeconds: Double, endSeconds: Double) {
            self.index = index
```


## roles and state
solver lab: 1nstinct. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"container": "audio-only mp4 with attached picture", "expect": "music session typed (no NON-attached-picture video track); artwork presence = identity of the attached-picture track (index + declared codec); no byte extraction"}, {"container": "audio-only, no picture", "expect": "music session typed; artwork presence nil (honest absence)"}, {"container": "video(non-attached)+audio", "expect": "not a music session (non-attached-picture video present); artwork presence still reported as identity if an attached-picture track exists"}]
```
