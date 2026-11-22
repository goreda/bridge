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

## Verified coverage (11 XCTest cases, all consuming the saved oracle)

- Track count/kind/codec/time base vs ffprobe for all 6 fixtures.
- Total and per-track packet counts vs ffprobe (no invented counts).
- Full emitted order and every pts/dts/duration as exact rationals vs the
  ffprobe integers x stream time_base, for all 525 packets.
- Every packet payload SHA-256 vs `ffprobe -show_packets -show_data`.
- Edit list + AAC priming, B-frame CTTS reorder, MKV millisecond time base.
- Missing cluster timestamp -> nil (surgical fixture edit), never zero.
- Empty input and 11 truncation points per fixture throw, no crash.
- Deterministic repeated demux; MP4/MKV type dispatch rejects the other
  container.

## Limits (explicit, throw not silently wrong)

- Fragmented MP4 (moof/mvex) throws `unsupported`.
- MKV EBML lacing and unknown-size elements throw `unsupported`.
- Containers other than ftyp/EBML throw `unsupported`.
- Multi-entry edit lists with several non-empty edits follow the classic
  (first-edit) rule, like ffmpeg without -advanced_editlist.

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
