# P-A1 BridgeDemux spec

Clean-room MP4 (ISO BMFF) and Matroska demux library. Foundation only, no
third-party code. Input is the whole container as `[UInt8]`; output is the
track table plus compressed (still-encoded) packets with rational
timestamps, in the container's natural decode order.

## Public interface

Exactly as assigned in packet P-A1: `RationalTime`, `DemuxTrack`,
`DemuxPacket`, `PacketDemuxer` (Sources/BridgeDemux/Types.swift). Concrete
implementations: `Demuxer` (magic-byte dispatch), `MP4Demuxer`,
`MKVDemuxer`.

- `DemuxTrack.id` is the 0-based stream index in file order, matching the
  ffprobe `stream_index` used by the oracle.
- `DemuxTrack.kind` / `codec` use ffprobe vocabulary (`video`/`audio`,
  `h264`/`aac`/`pcm_s16le`, ...).
- `RationalTime(value:scale)` carries `seconds = value/scale`; `scale` is
  the positive stream time-base denominator (e.g. 12288, 48000, 1000).
- Missing timestamps are `nil`, never zero. `next()` returns `nil` only at
  EOF. Empty or truncated input throws `DemuxError`; there are no unsafe
  reads, so malformed bytes cannot crash the parser.

## Timestamp semantics (oracle: ffprobe 4.4.2)

MP4, per sample, in decode order:
- DTS starts at `-(media_time)` of the first non-empty edit-list entry
  (minus `dts_shift`, the magnitude of the most negative CTTS v1 offset).
  This reproduces ffmpeg's classic edit-list handling, including the AAC
  priming edit (`media_time = 1024`): the first AAC packet of a1-av24.mp4
  is pts = dts = -1024/48000.
- PTS = DTS + dts_shift + CTTS offset (DTS when no CTTS). B-frame reorder
  is preserved: a1-bframes.mp4 starts dts = -1024/12288, pts = 0/12288.
- Duration = the sample's STTS delta. Equal to ffmpeg's generic fill for
  the constant-frame-rate tracks in this fixture set.
- Cross-track emission order: smallest pending DTS compared exactly as
  rational seconds, ties to the lower stream index (matches ffmpeg
  `mov_next_stream`).

Matroska, per block, in file order:
- Stream time base = TimestampScale / 1e9 s, reduced (default
  TimestampScale 1000000 ns -> 1/1000 s). Timestamps keep millisecond
  rounding exactly (0, 42, 83, ... ms for 24 fps).
- PTS = DTS = cluster Timestamp + block timecode, minus CodecDelay /
  TimestampScale. A cluster without a Timestamp element yields nil.
- Duration: BlockDuration, else DefaultDuration * laces / TimestampScale
  (truncating integer division, matching ffmpeg: 41666666/1000000 = 41),
  else 0. Zero duration on PCM audio is filled as
  floor(frame_samples * tb_den / (sample_rate * tb_num)), matching
  ffmpeg's generic audio fill (1024 samples @48k -> 21 ms).
- Xiph and fixed-size lacing supported; EBML lacing and unknown-size
  elements throw `DemuxError.unsupported`.

## Verified coverage (16 XCTest cases, all consuming the saved oracle)

- Track count/kind/codec/time base vs ffprobe for all 6 fixtures.
- Total and per-track packet counts vs ffprobe (no invented counts).
- Full emitted order and every pts/dts/duration as exact rationals vs the
  ffprobe integers x stream time_base, for all 525 packets.
- Every packet payload SHA-256 vs `ffprobe -show_packets -show_data`.
- Edit list + AAC priming, B-frame CTTS reorder, MKV millisecond time base.
- Missing cluster timestamp -> nil (surgical fixture edit), never zero.
- Empty input and 11 truncation points per fixture (all 11 files) throw, no crash.
- Fragmented MP4: oracle parity as described in the addendum section,
  multi-fragment continuity, offset-mode equivalence, faithful 775 quirk.
- Deterministic repeated demux; MP4/MKV type dispatch rejects the other
  container.

## P-A1-FMP4 addendum: fragmented MP4

moof/mdat fragments are supported: tfhd (base data offset, defaults),
tfdt (base decode time, minus the track's moov edit-list offset), trun
(per-sample duration/size/flags/CTS, v0/v1; multiple truns per traf with
implicit offsets), trex defaults, both base-data-offset and
default-base-moof addressing, and multi-fragment files. Fragment DTS
accumulates per track; PTS = DTS + CTS. The original progressive
fixtures and tests are unchanged and still pass with the same code path
for emission order, which now follows ffmpeg mov_find_next_sample
exactly: smallest pending DTS, with file position deciding ties inside a
one-second DTS window (DTS converted to microseconds, round-to-nearest).

Addendum fixtures: f1-v24.mp4, f1-av24.mp4, f1-bframes.mp4,
f1-av24-bm.mp4 (default_base_moof), f1-av24-g12.mp4 (4 fragments).
Generated locally with the recorded commands (same ffmpeg, LC_ALL=C),
oracled the same way.

Two ffprobe 4.4.2 reader-side artifacts on fmp4 are documented and
enumerated in tests rather than reproduced, because they are not
container data:

1. Parser-warmup duration dropout: ffprobe shows no duration for the
   first 21-24 video packets and sometimes the first audio packet of
   these fmp4 files (the count varies with parser state for identical
   content). We always report the fragment-table duration; tests assert
   exact equality wherever the oracle reports one and assert our value
   survives where it does not.
2. Trailing partial AAC frame: the container records the true duration
   (768/48000), ffprobe reports the codec's full frame size (1024/48000)
   from its generic fill. We report the container value; the test pins
   this single divergence (last audio packet only).

Notable faithful quirk: movenc records the first video sample of the
first fragment with duration 775 (its delay-compensation bookkeeping);
we surface 775/12288, not a synthesized 512. ffprobe masks it under
artifact 1, so no oracle conflict arises.

## Limits (explicit, throw not silently wrong)

- MKV EBML lacing and unknown-size elements throw `unsupported`.
- Containers other than ftyp/EBML throw `unsupported`.
- Multi-entry edit lists with several non-empty edits follow the classic
  (first-edit) rule, like ffmpeg without -advanced_editlist.
- Fragment sample flags are parsed but not surfaced (DemuxPacket carries
  no keyframe flag in the assigned interface).

## Fixtures (generated locally, no downloads, no licensed media)

ffmpeg 4.4.2-0ubuntu0.22.04.1 (libx264, aac, pcm_s16le; synthetic
testsrc2/sine sources). LC_ALL=C. Exact commands: generate_fixtures.sh.
Oracle: `ffprobe -v error -show_streams -show_packets -of json FILE >
FILE.ffprobe.json`; payload hashes: `-show_packets -show_data` piped
through tools/make_payload_oracle.py. Tests consume the saved oracle;
ffprobe is never invoked at test time.

## Provenance / hygiene

All source files are new code written for this packet. No private repo
access, source, identifiers, paths, licensed media, fonts, captures,
credentials, or user data. Reference semantics were checked against
publicly available ffmpeg 4.4.2 source (raw.githubusercontent.com,
libavformat/mov.c, matroskadec.c, utils.c) and against live ffprobe
output; no ffmpeg code is copied. secret scan: clean.

## P-A1-R1: malformed-container safety and reopen-state regression

Public protocols unchanged (`Types.swift` untouched). This revision hardens
the parsers against crafted bytes and fixes reopen state leakage:

Crash vectors closed (probe exit 132 pre-fix, named error post-fix; see
CRASH-EVIDENCE.txt):
- Matroska SimpleBlock with a lace flag but no lace-count byte: the Xiph and
  fixed-lace count reads are now bounds-checked (`truncated: ... lace count`).
- Cluster Timecode / TimestampScale > Int64.max: conversion now guarded
  (`unsupported: ... > Int64.max`).
- Track TimecodeScale NaN/inf: sanitized to 1.0 before use; the cluster
  timecode scale-down is range-checked before Int64 conversion.
- ctts run-length expansion is bounded by the stts sample count as it grows
  (`malformed: ctts entry count ...`), so a crafted count cannot drive
  unbounded allocation.
- stts sample-count sum is overflow-checked and capped at the file size
  (every sample occupies at least one media byte), bounding every downstream
  table expansion and reserveCapacity.
- stsz/stsc entry counts are checked against their box's remaining bytes
  before reading.
- Box size arithmetic (`boxStart + size`, EBML `bodyStart + size`), chunk
  offset accumulation, tfdt/edit-list offset math, fragment running DTS and
  PTS addition, lace duration splitting, PCM duration fill, and the
  microsecond rescale in the interleave comparator are all overflow-safe
  (reporting-overflow checks or saturation; never a trap).

Reopen-state fix:
- `Demuxer.open` now drops the previous session's demuxer up front. After a
  failed reopen, `next()` throws `malformed: next() before open()` instead
  of leaking stale packets from the earlier stream. A later successful open
  behaves exactly like a fresh demuxer (packet-for-packet identical).

Documented limit: a sample count larger than the file size (e.g. zero-byte
samples) is rejected as malformed.

Regression coverage (Tests/BridgeDemuxTests/MalformedSafetyTests.swift,
6 tests, all green):
- In-process named-error assertions for all 7 crafted fixtures.
- Subprocess probe runs (Sources/BridgeDemuxProbe, built by swift test)
  under `ulimit -v` containment: each malformed fixture must exit 0 with a
  named "ERROR ..." line - a trap or OOM kill fails the test.
- Subprocess and in-process reopen regressions over both containers:
  good open, drained packets, failed reopen -> named error, and next()
  throws with no stale packet leakage.
- Post-failure successful open matches a fresh demuxer packet-for-packet.

Fixtures in Tests/BridgeDemuxTests/Fixtures/malformed/ are derived from the
package's own generated a1-* media by tools/make_malformed.py (public,
synthetic bytes; no captured or licensed content).
