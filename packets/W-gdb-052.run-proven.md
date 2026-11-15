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
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "kits/b10-music-pin/check.py",
        "block": "kit1"
      },
      {
        "path": "kits/b10-music-pin/fixtures.json",
        "block": "fixtures2"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
    "command": "python3 kits/b10-music-pin/check.py kits/b10-music-pin/fixtures.json",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T22:09:46.115245+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "b10-music-pin: 3/3 rows PASS",
    "inline_files": [
      {
        "path": "kits/b10-music-pin/check.py",
        "block": "kit1",
        "sha256": "bf806079f6daa151ceb68d10258918f658ae5c9b7e682c8cdf14b41772b82367"
      },
      {
        "path": "kits/b10-music-pin/fixtures.json",
        "block": "fixtures2",
        "sha256": "5db848e7a7b34d717685d81393ef4caa8a98f0eecacb5b22b20df85c4a7e6360"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "c3714e473a402a0643852f6d15689608bf6bcc4c8bbffa61e2af5adafe53252e",
    "last_5_lines": [
      "PASS audio-plus-artwork music=True artwork=(1, 'mjpeg')",
      "PASS audio-only music=True artwork=None",
      "PASS audio-plus-real-video music=False artwork=None",
      "PASS negative control: mutated expectation fails (row changed to {'musicSession': False, 'artwork': None})",
      "b10-music-pin: 3/3 rows PASS"
    ],
    "receipt_sha256": "3076000dd2d8ef810d8e311d082ca0a5cfeaafaa0f7f0e2eb7fcdb75e3f028f8"
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

```python id=kit1
#!/usr/bin/env python3
# b10-music-pin: music-session classification + artwork identity pin over the
# pinned MediaInventory.Track surface (@ 2112af0d60df16c5473173b664903f76ce54173e).
# music-session := audio present AND NO non-attached-picture video track.
# Artwork is reported as identity (track index + declared codec) only; no byte
# read API exists at this pin. Absence stays nil.
import json, sys

def classify(tracks):
    has_audio = any(t["kind"] == "audio" for t in tracks)
    has_real_video = any(t["kind"] == "video" and not t.get("isAttachedPicture", False) for t in tracks)
    music = has_audio and not has_real_video
    art = [(t["index"], t["codec"]) for t in tracks if t.get("isAttachedPicture", False)]
    artwork = art[0] if art else None
    return {"musicSession": music, "artwork": artwork}

def main():
    fixtures = json.load(open(sys.argv[1]))
    fails = passed = 0
    for fx in fixtures:
        got = classify(fx["tracks"])
        exp = fx["expect"]
        exp_art = None if exp["artwork"] is None else (exp["artwork"]["index"], exp["artwork"]["codec"])
        ok = got["musicSession"] == exp["musicSession"] and got["artwork"] == exp_art
        if ok: passed += 1; print("PASS %s music=%s artwork=%s" % (fx["name"], got["musicSession"], got["artwork"]))
        else: fails += 1; print("FAIL %s expected %s got %s" % (fx["name"], exp, got))
    # Negative control: flipping the artwork track's attached-picture flag must
    # change the row (presence becomes absence), proving the row discriminates.
    fx0 = fixtures[0]
    mut = [dict(t) for t in fx0["tracks"]]
    for t in mut:
        if t.get("isAttachedPicture"):
            t["isAttachedPicture"] = False
            t["kind"] = "video"
    mgot = classify(mut)
    if mgot == classify(fx0["tracks"]):
        fails += 1; print("FAIL negative control: mutation did not change the row")
    else:
        print("PASS negative control: mutated expectation fails (row changed to %s)" % mgot)
    total = len(fixtures)
    if fails:
        print("b10-music-pin: %d/%d rows PASS, %d FAIL" % (passed, total, fails)); sys.exit(1)
    print("b10-music-pin: %d/%d rows PASS" % (passed, total)); sys.exit(0)

if __name__ == "__main__":
    main()

```

```json id=fixtures2
[
 {"name": "audio-plus-artwork", "tracks": [
   {"index": 0, "kind": "audio", "codec": "flac", "isDefault": true},
   {"index": 1, "kind": "video", "codec": "mjpeg", "isAttachedPicture": true}],
  "expect": {"musicSession": true, "artwork": {"index": 1, "codec": "mjpeg"}}},
 {"name": "audio-only", "tracks": [
   {"index": 0, "kind": "audio", "codec": "mp3", "isDefault": true}],
  "expect": {"musicSession": true, "artwork": null}},
 {"name": "audio-plus-real-video", "tracks": [
   {"index": 0, "kind": "video", "codec": "h264", "isDefault": true},
   {"index": 1, "kind": "audio", "codec": "aac"}],
  "expect": {"musicSession": false, "artwork": null}}
]

```

```text id=actual_run_log
PASS audio-plus-artwork music=True artwork=(1, 'mjpeg')
PASS audio-only music=True artwork=None
PASS audio-plus-real-video music=False artwork=None
PASS negative control: mutated expectation fails (row changed to {'musicSession': False, 'artwork': None})
b10-music-pin: 3/3 rows PASS
```
