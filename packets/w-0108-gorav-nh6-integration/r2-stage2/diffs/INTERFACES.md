INTERFACES/CONTEXT for the lab writer (PKT-G2):
TARGET PATHS in ohal/gorav tree:
  contract-candidate.swift  -> Sources/GorAVNativeProbeKit/GorAVSeekContract.swift
  decoder-candidate.swift   -> Sources/GorAVFFmpegAdapter/FFmpegSoftwareDecoder.swift
  suite-candidate-v2.swift  -> Sources/native-hold-tests/main.swift (NEW test dir)
  diag-candidate.swift      -> TEST-BUILD overlay only (never committed as module source);
                               test tree replaces FFmpegSoftwareDecoder.swift with these bytes.
MODULE ORDER (direct swiftc, Linux): GorAVCAtomics(C) -> GorAVCore -> GorAVNativeProbeKit ->
  GorAVFFmpegAdapter -> [GorAVPlaybackCore -> GorAVSeekComposition] -> suite exe.
  Module deps: suite imports GorAVCore, GorAVNativeProbeKit, GorAVFFmpegAdapter.
EXTERNAL DEP: FFmpeg 8.0.1 @894da5ca7d742e4429ffb2af534fcda0103ef593, kit-minimal configure,
  static libavformat/libavcodec/libavutil; CFFmpeg/module.modulemap (in repo) injects link names.
  Fixture for NH6 suite: S5_SEEK_FIXTURE=<fixture.mov> (sha256 397930c3...).
BUILD COMMAND PATTERN: build-commands.txt (from the s5iso isolated validation; adapt paths).
EXPECTED: stage-1 compile green + existing suites green; stage-2 NH6 explicit selector, 41/0,
  zero "gate-timeout" lines (ANY gate-timeout line invalidates the run regardless of exit).
RECEIPT/CLAIM LIMITS: see RECEIPT-NH6v2-recovery.md - carry its section 8/9 verbatim into PR body.
PINS: sha256 of every file is in MANIFEST.sha256; verify before and after placement.
