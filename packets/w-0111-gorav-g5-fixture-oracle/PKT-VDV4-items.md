PKT-VDV4 (owner: VDV4 via Main; bounded; integrator re-runs before landing). Base: ohal/gorav @f937ee76.
TWO NON-OVERLAPPING ITEMS. Neither authorizes a production provider API change for test green.

ITEM A - gorav-first-frame / trace-dump providerFailed(code: -21): LOCAL CODE INVESTIGATION.
Cause is UNKNOWN - do not settle it as a fixture gap. Established facts (integrator):
- first-frame is SELF-CONTAINED: 574-byte 17x11 PPM pinned in FirstFrame.swift (sha256 009889e2...,
  verified), fed via openSnapshot; fails at openSnapshot with providerFailed(code: -21), exit 67
  (log attached: first-frame-run2.log).
- trace-dump needed fixtures/first-ppm-rgb24-17x11.ppm - RECOVERED from those exact pinned bytes
  (hash-verified) and written to the kit; it then progressed to the SAME -21 at its K13 open
  (log attached: trace-dump-run4.log). Two independent paths fail at -21 on the ppm/snapshot route.
- Working hypothesis to VERIFY, not assume: the minimal FFmpeg kit (configure flags sent earlier:
  demuxers mov+wav, decoders mpeg4+pcm_s16le only) cannot open a ppm/ppm_pipe route at all.
  Pin what code -21 actually is in the adapter's error mapping (openSnapshot path), confirm against
  the kit configure, and report the true cause. If the fix is kit capability (add image2/ppm demuxer
  + ppm decoder to the KIT build), that is a KIT configure decision for Main, not your code change.

ITEM B - 5 fixture/oracle generations (lab G5 remainder; no fabricated oracles; provenance required):
1. oracles/k3-oracle.txt (unblocks seek-test, coexist-test, isolation-test). Format: one line per
   decoded frame of fixtures/fixture-k3.mp4, "<index> <digest>" (suite reads field 2). Digest =
   FFmpegSoftwareDecoder.frameDigest per frame (same call real-seek-tests uses). Generator: small
   swift driver on the CURRENT adapter, sequential decode of the pinned fixture-k3.mp4; ship the
   generator source + fixture pin + run log as provenance.
2. fixtures/seekcheck-src.mp4 (unblocks real-seek-tests). The suite is SELF-CONSISTENT (sequential
   pass builds its own reference). Requirements: mp4/mov demuxable by the minimal kit, mpeg4 video,
   >12 frames, real keyframes (isKeyFrame asserted), seekable. Generate with a full ffmpeg CLI
   (minimal kit has no programs); record the exact generation command as provenance.
DONE-WHEN: A reports the true -21 cause with evidence (and green only if the resolution is
test/kit-level and Main approves any kit change); B files exist with provenance and the 5 suites
exit 0 on a fresh chain from f937ee76; logs + hashes pinned; claims labeled Linux-sandbox.
