# BridgeDemux (P-A1)

Self-contained Swift package: MP4/MKV demux to tracks + compressed packets
with stable rational timestamps. This tree is the P-A1-R1 state: the
P-A1-FMP4 addendum plus malformed-container hardening and the reopen-state
fix; all P-A1 and FMP4 fixtures and tests are unchanged and green, and 6
new safety regressions (22 tests total) run green.

    swift build
    swift test

Layout:
- Sources/BridgeDemux/    library (Types, Cursor, MP4Demuxer, MKVDemuxer, Demuxer)
- Sources/BridgeDemuxProbe/ crash-regression probe executable (demux/reopen modes)
- Tests/BridgeDemuxTests/ XCTest suite + Fixtures/ (media, ffprobe oracle, payload hashes)
- generate_fixtures.sh    fixture + oracle regeneration (ffmpeg/ffprobe, LC_ALL=C)
- tools/make_payload_oracle.py, tools/make_malformed.py (P-A1-R1 fixtures)
- SPEC.md                 semantics, coverage, limits, provenance
- TEST-LOG.txt            recorded `swift test` run
- CRASH-EVIDENCE.txt      pre-fix trap/kill evidence vs post-fix named errors
- MANIFEST.sha256         sha256 of every packaged file

Developed and tested with Swift 5.9.2 (swift-5.9.2-RELEASE-ubuntu22.04,
x86_64) and ffmpeg 4.4.2-0ubuntu0.22.04.1.
