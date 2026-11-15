# Codec checksum r4 receipt: Linux lane run, tar-format packet

Supersedes r3 audio absolute-compare gap. Exact branch ohal/codec-checksum-r4 at 7c14663e74cc862805c11f47f5aded3194f16f70, off91a359f7b38cc0e6c4974661d85f389ef6041b1f, not main. Ops independently fetched branch, read source+goldens and supplied full lane log. No Ops rerun, Darwin/native/hardware or owner-Mac acceptance claimed. No .run-proven format validation claimed.

Lane execution context, supplied by the executing lane: clean git-archive91a359f + r4 packet + goldens-audio.tsv, Package.swift per INTEGRATION.md; cwd /tmp/codec-run4; Swift6.1.2; CPATH=/tmp/ff-full/ffinstall/include; LIBRARY_PATH=/tmp/ff-full/ffinstall/lib:/tmp/dav1d-install/lib/x86_64-linux-gnu; GORAV_CODEC_KIT unset. Command: swift run -Xlinker -L/tmp/dav1d-install/lib/x86_64-linux-gnu -Xlinker -ldav1d codec-checksum-tests. Lane reports exit0. Supplied log independently inspected: real product compilation and final codec-checksum-tests:50PASS,0FAIL,0REFUSED, no audio-absolute-OFF note. Nine generated-codec fixtures and both audio/video golden files exist in exact branch. Do not mistake lane execution provenance for an independently reproduced Ops run.

Log SHA256 4a44637d79b189c2ef0382d28b8f67ff9179ba2f70208682d223780f763d39e7
Audio goldens SHA256 89ed0863987db1d7299e398b0275b74255d8443ea684d6eb01f3c065636d5833
Harness SHA256 c03250779e6dbda96cb7327aa42a43990c30067e35decf51c8f9eefbfd8abb44

## Lane log tail
```text
r.swift:80:103: warning: code after 'return' will never be executed
 78 |         catch SeekRefusal.stale { return .admissionRefused(reason: .stale) }
 79 |         catch SeekRefusal.closed { return .admissionRefused(reason: .closed) }
 80 |         catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
    |                                                                                                       `- warning: code after 'return' will never be executed
 81 |         catch SeekRefusal.unsupported(let m) { return .admissionRefused(reason: .unsupported(m)) }
 82 |         catch { return .admissionRefused(reason: .unsupported("\(error)")) }
[66/71] Wrapping AST for GorAVPlaybackCore for debugging
[68/79] Emitting module GorAVFFmpegAdapter
[69/85] Compiling GorAVFFmpegAdapter L3PixelConvert.swift
[70/85] Compiling GorAVFFmpegAdapter L3SampleConvert.swift
[71/85] Compiling GorAVFFmpegAdapter MediaInventory.swift
[72/85] Compiling GorAVFFmpegAdapter SnapshotAVIOOwner.swift
[73/85] Compiling GorAVFFmpegAdapter SnapshotInput.swift
[74/85] Compiling GorAVFFmpegAdapter SourceOpenOptions.swift
[75/85] Compiling GorAVFFmpegAdapter ActiveTransportSnapshot.swift
[76/85] Compiling GorAVFFmpegAdapter FFmpegSoftwareAudioDecoder.swift
[77/85] Compiling GorAVFFmpegAdapter FFmpegSoftwareDecoder.swift
[78/85] Compiling GorAVFFmpegAdapter FrameObservation.swift
[79/85] Compiling GorAVFFmpegAdapter L3AVCoordinator.swift
[80/85] Compiling GorAVFFmpegAdapter L3Admission.swift
[81/85] Compiling GorAVFFmpegAdapter L3HardwareDecode.swift
[82/86] Wrapping AST for GorAVFFmpegAdapter for debugging
[84/88] Compiling codec_checksum_tests CodecChecksumTests.swift
[85/88] Emitting module codec_checksum_tests
[86/89] Wrapping AST for codec-checksum-tests for debugging
[87/89] Write Objects.LinkFileList
[88/89] Linking codec-checksum-tests
Build of product 'codec-checksum-tests' complete! (12.48s)
codec-checksum-tests: 50 PASS, 0 FAIL, 0 REFUSED

```
