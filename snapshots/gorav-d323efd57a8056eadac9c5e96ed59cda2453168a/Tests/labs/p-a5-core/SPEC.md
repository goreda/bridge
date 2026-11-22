# P-A5 BridgeVTDecode spec

Clean-room h264/hevc decode wrapper over VideoToolbox behind the published
FrameDecoder protocol, with a software fallback stub, consuming the P-A1
demux packet stream. Foundation + VideoToolbox/CoreMedia/CoreVideo (macOS
only) ; no third-party code.

Package layout: target `BridgeDemux` is a vendored, byte-identical copy of
the P-A1-R2 sources (the original P-A1/P-A1-FMP4/P-A1-R1/P-A1-R2 packages
are unchanged; MANIFEST pins every file). Target `BridgeVTDecode` holds
DecodedFrame / DecoderError / FrameDecoder / SoftwareStubDecoder /
PixelDigest.

OWNER SPLIT (P-A5, two workers): this package owns the protocol surface,
the software stub, the fixtures/oracles, the demux->decoder pipeline tests,
and the digest assertions. VTFrameDecoder, the avcC/hvcC configuration
extraction helper and the .missingConfiguration refusal belong to the
sibling worker's package; the protocol files (FrameDecoder.swift,
PixelDigest.swift) were passed to them verbatim and frozen. Their
decoder must consume RationalTime/DemuxPacket from BridgeDemux (P-A1-R2)
and produce digests via PixelDigest.hex so digests stay comparable.

## Contract points and how each is met

- Protocol exactly as published: `open(codec:)`, `decode(_:) -> [DecodedFrame]`
  (packets in decode order), `flush() -> [DecodedFrame]` (drains reorder,
  EOS after). DecodedFrame carries pts as the P-A1 RationalTime (nil
  preserved), width, height, and a deterministic pixel digest.
- SoftwareStubDecoder (every platform): open throws a typed
  `.unsupportedBackend` for ANY codec; decode/flush also throw
  `.unsupportedBackend`. It never fabricates frames: a non-Mac run is
  typed, not green.
- VTFrameDecoder and the avcC/hvcC configuration extraction: sibling
  worker's scope (owner split above). Named contract gap, recorded here
  because it shapes both packages: the published protocol transports only a
  codec name in open(codec:), while MP4 keeps h264/hevc parameter sets in
  the stsd avcC/hvcC box, never in the packet stream (the mandated fixtures
  included). The DecoderError taxonomy shipped here already carries the
  typed `.missingConfiguration` case for that refusal, and
  `.unsupportedBackend` for non-Mac and session-create failure - so the
  sibling's backend refuses typed, never fabricates, never claims green.
- Reorder grounding, asserted decoder-free on this host: the sorted demux
  packet pts sequence equals the ffprobe frames' presentation pts sequence
  as exact rationals, and both reorder fixtures (hevc default bf=4, h264
  -bf 2) are verified to genuinely reorder. Presentation order out of the
  sibling's VT backend after flush is asserted in their Mac tests.

## Fixtures (generated, no downloads, LC_ALL=C)

ffmpeg 4.4.2-0ubuntu0.22.04.1; exact commands in Fixtures/GENERATION.txt:
- a5-h264-24fps.mp4 (testsrc2 64x64 rate 24, -t 2, libx264 -bf 0 yuv420p)
- a5-hevc-24fps.mp4 (same geometry/duration, libx265; default bf=4 -> reorders)
- a5-h264-bframes.mp4 (libx264 -bf 2 -g 24 -> reorders)
Oracles per file: .ffprobe.json (streams+packets) and .ffprobe-frames.json
(streams+frames), recorded exactly as P-A1 records them. 48 packets / 48
frames / 64x64 each; tests consume the saved oracles, never ffprobe as
implementation.

## Assertions (5 tests, green debug AND release on this host)

1. Stub refusal everywhere (open h264/hevc/unknown/empty, decode, flush).
2. Demux of all 3 fixtures vs packet oracle: track/kind/codec, per-packet
   pts/dts/duration as exact rationals.
3. Frame oracle: 48 frames at 64x64, monotonic presentation pts; sorted
   packet pts == frame pts sequence (exact rationals); reorder fixtures
   verified non-trivial.
4. Pipeline boundary: all 48 packets per fixture fed to the decoder port,
   each a typed refusal; flush a typed refusal.
5. PixelDigest determinism: sha256 golden vectors + two-run stability.

## Limits

- Packets from the fixtures are 4-byte length-prefixed (avcC
  nalLengthSize 4, verified); other layouts are the sibling backend's
  typed-refusal call.
- Digests (PixelDigest.hex over the backend's pixel bytes): stable per
  host, explicitly not compared across hosts (decoder implementation
  detail). Recording happens in the sibling's Mac run; the function itself
  is pinned here by golden vectors.
