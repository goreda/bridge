# W-0111 - gorav line, G5 item B: fixture/oracle generation + bounded gapped-suite reruns (LAB packet)
Base: ohal/gorav @f937ee76 (PR1 head; tree identical for these suites to b3a2c4d). Integrator-qualified expectations.

SCOPE: this is ITEM B ONLY. ITEM A (gorav-first-frame / trace-dump providerFailed(code: -21) root cause) is LOCAL writer work (VDV4), NOT lab work: do not investigate -21 and do not settle it as a fixture gap. trace-dump and gorav-first-frame stay BLOCKED on that local resolution. oracles/trace-snapshot-route.json and oracles/trace-path-route.json DO NOT EXIST as inputs - they are trace-dump OUTPUTS produced only after the local fix; do not fabricate them, and do not claim all 6 gapped suites unblocked.

## Task (two generations, provenance required, no fabricated oracles)
1. oracles/k3-oracle.txt (unblocks seek-test, coexist-test, isolation-test). Format: one line per decoded frame of kit/fixtures/fixture-k3.mp4, "<index> <digest>" (suites read field 2). Digest = FFmpegSoftwareDecoder.frameDigest per frame, the same call real-seek-tests uses. Generator: a small swift driver on the CURRENT adapter doing a sequential decode of the pinned fixture-k3.mp4. Ship generator source + fixture pin + run log as provenance.
2. fixtures/seekcheck-src.mp4 (unblocks real-seek-tests). The suite is SELF-CONSISTENT (its sequential pass builds its own reference). Requirements: mp4/mov demuxable by the minimal kit, mpeg4 video, >12 frames, real keyframes (isKeyFrame asserted), seekable. Generate with a full ffmpeg CLI (the minimal kit has no programs); record the exact generation command as provenance.

## Sources in this packet
- src/: full Sources tree + Package.swift @f937ee76 (the suites live under src/Sources/).
- build-g1.sh: the integrator's fresh-used Linux direct gcc/swiftc build recipe (sha256 9227e813514ccc0a0e472b9dece74376927dfae82647107b4c6984702b3238fa).
- kit/: the known-good card720 v6 payload files the suites read, pinned in kit/MANIFEST.sha256: fixtures/fixture-k3.mp4 (aa2ce163..., 75205 B), fixtures/fixture-k4.wav (7c06a95a..., 176444 B), fixtures/first-ppm-rgb24-17x11.ppm (009889e2..., 574 B). Only these sha256-pinned files are valid inputs; a 17-byte fake mp4 decoy circulates - never use it.
- PKT-G5-evidence.md: the integrator's 2026-10-26 Linux sweep matrix and conventions, verbatim (its local /tmp kit path is superseded by this packet's kit/ dir).
- PKT-VDV4-items.md: the item A/B split and format/provenance grounding, verbatim.

## Run
- GORAV_KIT = this packet's kit/ plus your generated files (suites read $GORAV_KIT/oracles/... and $GORAV_KIT/fixtures/...).
- After generation, the runnable target set is: seek-test, coexist-test, isolation-test, real-seek-tests (4 suites). trace-dump and gorav-first-frame remain BLOCKED (local, above).
- Conventions from the integrator sweep: seek-ring-reset-tests compiles WITHOUT -parse-as-library; audio-seek-tests/audio-baseline-tests are DESIGN-SKIP unless their env-named files exist - NOT_RUN is correct behavior there; do not invent those files.

## Bounds
- No production provider API change for test green.
- Credential-free, offline; no Mac/native claims; label claims Linux-sandbox.
- Return patch or full files on your files page; the integrator applies them on ohal/gorav, re-runs, and merges like any writer's work. No push/merge/deploy by labs.
- DONE-WHEN: the 2 generated files exist with full provenance (generator source + exact command + run log + hashes) and seek-test, coexist-test, isolation-test, real-seek-tests exit 0 on a fresh chain from f937ee76; logs + object hashes pinned.
