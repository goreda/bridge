# BridgeDemux (P-A1)

Self-contained Swift package: MP4/MKV demux to tracks + compressed packets
with stable rational timestamps. This tree is the P-A1-R2 state: the
P-A1-R1 revision plus fully-checked lace-duration splitting and
rounding-addition checks in the microsecond rescale (the two defects
alleged in P-A4 E2, both verified real failing-first - DEFECT-EVIDENCE.txt);
all earlier fixtures and tests are unchanged and green, 22 tests total in
debug and release.

    swift build
    swift test

Layout:
- Sources/BridgeDemux/    library (Types, Cursor, MP4Demuxer, MKVDemuxer, Demuxer)
- Sources/BridgeDemuxProbe/ crash-regression probe executable (demux/reopen modes)
- Tests/BridgeDemuxTests/ XCTest suite + Fixtures/ (media, ffprobe oracle, payload hashes)
- generate_fixtures.sh    fixture + oracle regeneration (ffmpeg/ffprobe, LC_ALL=C)
- tools/make_payload_oracle.py, tools/make_malformed.py (R1), make_r2_fixtures.py (R2)
- SPEC.md                 semantics, coverage, limits, provenance
- TEST-LOG.txt            recorded `swift test` run
- CRASH-EVIDENCE.txt      R1 pre-fix trap/kill evidence vs post-fix named errors
- DEFECT-EVIDENCE.txt     R2 failing-first verification of the two P-A4 E2 allegations
- MANIFEST.sha256         sha256 of every packaged file

Developed and tested with Swift 5.9.2 (swift-5.9.2-RELEASE-ubuntu22.04,
x86_64) and ffmpeg 4.4.2-0ubuntu0.22.04.1.
