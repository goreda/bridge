# BridgeVTDecode (P-A5)

Self-contained Swift package: the P-A5 protocol surface (FrameDecoder,
DecodedFrame, DecoderError), SoftwareStubDecoder (typed .unsupportedBackend
everywhere - a non-Mac run is typed, never green), PixelDigest, and the 3
generated fixtures + ffprobe oracles with the demux->decoder pipeline
tests. Owner split: VTFrameDecoder and the avcC/hvcC extraction helper live
in the sibling worker's package; the frozen protocol files were handed over
verbatim.

    swift build
    swift test            # 5 tests, debug
    swift test -c release # 5 tests, release

Layout:
- Sources/BridgeDemux/      vendored P-A1-R2 sources (byte-identical, manifest-pinned)
- Sources/BridgeVTDecode/   FrameDecoder, DecodedFrame, DecoderError,
                            SoftwareStubDecoder, PixelDigest (SHA-256)
- Tests/BridgeVTDecodeTests/ XCTest suite + Fixtures/ (media, ffprobe oracles,
                            GENERATION.txt with exact ffmpeg/ffprobe commands)
- SPEC.md                   contract mapping, coverage, limits, provenance
- TEST-LOG.txt              recorded debug + release runs
- MANIFEST.sha256           sha256 of every packaged file

Developed and tested with Swift 5.9.2 (swift-5.9.2-RELEASE-ubuntu22.04,
x86_64) and ffmpeg 4.4.2-0ubuntu0.22.04.1. No VideoToolbox code ships here;
no native green is claimed.
