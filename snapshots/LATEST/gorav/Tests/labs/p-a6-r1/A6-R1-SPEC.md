# P-A6-R1: HEVC reorder, EAC3 duration, nonzero CodecDelay

Status: 31 XCTest tests pass, zero failures or skips. The unchanged public P-A1
protocol remains in Types.swift. Separate package: original delivered P-A6 and
P-A1-R2 archives are not modified. This revision changes MKVDemuxer.swift, adds
HEVCReorder.swift, extends A6OracleTests, and adds parser safety tests plus a
synthetic nonzero CodecDelay derivative and saved ffprobe oracle.

## Failing-first evidence and measured repair

A6R1Evidence/failing-first.log and failing-first.comparison.json retain the prior
actual failing run: 96 mismatches, 32 HEVC DTS, 1 EAC3 CodecID, 63 EAC3 durations.
The repaired three exact comparisons have zero mismatches, no exemptions:

| Fixture | Video packets | Audio packets | Total |
| --- | ---: | ---: | ---: |
| a6-h264-aac.mp4 | 48 | 95 | 143 |
| a6-hevc-eac3.mkv | 48 | 63 | 111 |
| a6-hevc-eac3-delay.mkv | 48 | 63 | 111 |

Counts come from actual demux output and saved oracle JSON. Exact rational
PTS/DTS/duration, missing values, per-track emitted order, track kind/codec and
packet sizes are compared. The MP4 path stays unchanged; AAC priming is negative
-1024/48000, not zero. Old original regressions continue to pass.

## HEVC DTS

The new clean-room bounded hvcC/SPS reader gets sps_max_num_reorder_pics from
CodecPrivate, rather than hardcoding the fixture's depth of 2 or reading oracle
values at runtime. It parses profile-tier-level lengths, optional sub-layer flags,
Exp-Golomb values, chroma/conformance syntax and sub-layer ordering. Emulation
prevention bytes are removed. Malformed or unsupported configuration throws a
named DemuxError. Unit-generated SPS tests exercise depths 0, 1, 2, 4 and 16,
every truncated prefix of a valid hvcC, missing SPS, and excessive reorder depth.

For each HEVC track, a sorted buffer retains up to reorder-depth pending PTS
values. Insert current PTS; while the count has not exceeded depth, DTS is nil.
Once it exceeds depth, remove and emit the smallest buffered timestamp as DTS.
The packet itself remains in file/decode order. The first two DTS values in the
provided depth-2 fixtures are genuinely nil, and every subsequent value matches
ffprobe's saved oracle, including nonzero-delay values. EOF does not fabricate
extra packets or flush timestamps into nonexistent packets.

This is bounded fixture-matrix evidence, not a claim of full HEVC bitstream
support. Only hvcC CodecPrivate with consistent parsed SPS reorder depths is
supported; midstream SPS switches, temporal-layer operating-point selection,
random-access state resets and arbitrary HEVC containers are not validated here.
No codec decoder or ffprobe subprocess is used by the library.

Public syntax grounding, not copied implementation:
https://hevc.hhi.fraunhofer.de/trac/hevc/ticket/862
https://webrtc.googlesource.com/src/+/refs/heads/main/common_video/h265/h265_sps_parser.cc

## EAC3

Matroska A_EAC3 maps to ffprobe codec name eac3. A valid syncword 0x0b77 allows
reading fscod and numblkscod at header byte 4. Block counts are [1,2,3,6], or 6
when fscod is 3, with 256 new samples per block. Duration remains the existing
integer floor(samples * tb_den / (sampleRate * tb_num)), not a hardcoded 32/1000.
The generated 48 kHz, six-block frames therefore yield 1536/48000 seconds,
represented by MKV timebase as 32/1000. Missing/invalid syncframe headers cannot
produce an inferred duration; nonfixture EAC3 layouts are not broadly validated.
Public format grounding: ETSI TS 102 366, sections E.1.2.2 and E.1.3.1.4-5:
https://www.etsi.org/deliver/etsi%5Fts/102300%5F102399/102366/01.04.01%5F60/ts%5F102366v010401p.pdf

## Nonzero CodecDelay fixture

The original prescribed MKV contains no CodecDelay. tools/make_a6_delay.py
reconstructs its public/generated EBML track metadata to add video delay
10,000,000 ns and audio delay 32,000,000 ns. It removes SeekHead/Cues offset tables
and CRCs to avoid stale indices/checksums, recalculates enclosing lengths, and
preserves compressed payloads. This is a synthetic demux metadata test, not an
encoder or playback claim. See generate-a6-r1-delay.sh for exact commands.

The structural inspector proves nonzero values. A new test verifies equal
compressed payloads and durations between original/delayed packets, PTS and known
DTS shifted by 10/1000 video and 32/1000 audio, with missing DTS still nil. Both
original and delayed MKV are asserted independently against saved ffprobe.
The pre-existing CodecDelay subtraction logic did not need modification.
Fractional-tick CodecDelay rounding is outside this integer-tick test.

## Reproduce

Swift 5.9+; tested Swift 6.0.3 Linux x86_64. FFmpeg/ffprobe 4.4.2, LC_ALL=C;
original exact ffmpeg commands/versions are inherited in generate-a6-fixtures.sh
and A6Evidence. Delay generation is deterministic and uses no external media.

```sh
export LC_ALL=C
bash generate-a6-r1-delay.sh  # optional: regenerate derivative and its oracle
mkdir -p A6R1Evidence
A6_EVIDENCE_DIR="$PWD/A6R1Evidence" swift test -j 1
sha256sum -c SHA256SUMS
```

Tests consume saved oracle JSON and never run ffprobe as implementation.
Historical A6Evidence and A6-SPEC remain as failing-first history, not current
status. Historical manifests are renamed P-A6-BASE-SHA256SUMS and
P-A1-R2-BASE-MANIFEST.sha256: they describe earlier payloads, not this revision.
SHA256SUMS is this revision's full manifest; it covers all payload except itself.
The separate archive hash covers the manifest too. SHA-256 verification passes
with GNU sha256sum, including after archive extraction. No toolchain/build cache
is included. Re-running a test log changes its digest, not the pinned input data.

secret scan: clean

Pattern scan of text/source/JSON and provenance inspection found no credentials,
user data or licensed media. It is bounded, not a guarantee for arbitrary secret
encodings. No remaining named packet field failure or unmeasurable oracle field;
all three fixtures have exact passing comparisons. Broader codec/runtime limits
above remain, and no host/device playback acceptance is claimed.
