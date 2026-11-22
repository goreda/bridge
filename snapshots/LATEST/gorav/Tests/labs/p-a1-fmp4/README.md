# BridgeDemux (P-A1)

Self-contained Swift package: MP4/MKV demux to tracks + compressed packets
with stable rational timestamps. This tree is the P-A1-FMP4 addendum state:
the original P-A1 package plus fragmented-MP4 (moof/mdat) support and five
f1-* fixtures; all original P-A1 fixtures and tests are unchanged and green.

    swift build
    swift test

Layout:
- Sources/BridgeDemux/    library (Types, Cursor, MP4Demuxer, MKVDemuxer, Demuxer)
- Tests/BridgeDemuxTests/ XCTest suite + Fixtures/ (media, ffprobe oracle, payload hashes)
- generate_fixtures.sh    fixture + oracle regeneration (ffmpeg/ffprobe, LC_ALL=C)
- tools/make_payload_oracle.py
- SPEC.md                 semantics, coverage, limits, provenance
- TEST-LOG.txt            recorded `swift test` run
- MANIFEST.sha256         sha256 of every packaged file

Developed and tested with Swift 5.9.2 (swift-5.9.2-RELEASE-ubuntu22.04,
x86_64) and ffmpeg 4.4.2-0ubuntu0.22.04.1.
