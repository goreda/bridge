# Codec checksum r3 receipt: Linux lane run, tar-format packet

Observed branch ohal/codec-checksum-r3 at 98a0cefb30ca44daa51cf22e95ab295d58a6340e (off91a359f7b38cc0e6c4974661d85f389ef6041b1f; not main). Ops independently fetched branch and read product harness/packet and supplied lane log, not an Ops execution. Lane reports full-codec FFmpeg7.1+libdav1d Linux build and strict9codec execution inclAV1 via libdav1d. Log: codec-checksum-tests:46PASS,0FAIL,0REFUSED. The attached raw log does not print command/environment/exit status or9codec enumeration, so those details remain lane-reported, not independently reconstructed. No Darwin/native/hardware/ownerMac acceptance. No .run-proven-format validation claimed.

Audio absolute compare OFF: goldens-audio.tsv absent, determinism gate only. Video goldens are present. Do not call audio checksum parity an absolute golden comparison.

Lane log SHA256 16dedcbcb47fa38870e61df5503b2f0b1bba7d282322389896fc4272c5f2f832

## Product source evidence

CODEC-CHECKSUM-INTEGRATION.md SHA256 d451d503a61ad11667bb1788cfba4b204fe00033c028b9533d79ef6366e74604

CODEC-CHECKSUM-PACKET.md SHA256 a2af35f6b46f9c3cca469531850e55005de38083b8f074729b076c67ffb03e48

Sources/codec-checksum-tests/CodecChecksumTests.swift SHA256 097b663bd2f35558b3bac4b11c400edcaf266e717eb9c5b84d2e1f3811685198

## Supplied lane run log
```text
warning: 'codec-run': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/codec-run/Sources/seek-composition-tests/README-SEEKVECTORS.md
warning: 'codec-run': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/codec-run/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'codec-run': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/codec-run/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/codec-run/Sources/subtitle-tests/ASSTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'codec-run': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/codec-run/Sources/subtitle-tests/SRTTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'codec-run': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/codec-run/Sources/subtitle-tests/SRTTests.swift
    /tmp/codec-run/Sources/subtitle-tests/ASSTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'codec-run': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/codec-run/Sources/subtitle-tests/SRTTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/codec-run/Sources/subtitle-tests/ASSTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitleControllerTests.swift
warning: 'codec-run': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/codec-run/Sources/subtitle-tests/SRTTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/codec-run/Sources/subtitle-tests/ASSTests.swift
    /tmp/codec-run/Sources/subtitle-tests/SubtitlePlanTests.swift
[0/1] Planning build
Building for debugging...
[0/2] Write swift-version--6630B1A18289934C.txt
Build of product 'codec-checksum-tests' complete! (0.66s)
note: goldens-audio.tsv absent - audio absolute compare OFF (determinism gate active)
codec-checksum-tests: 46 PASS, 0 FAIL, 0 REFUSED

```
