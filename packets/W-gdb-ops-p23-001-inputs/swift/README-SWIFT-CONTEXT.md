# vr180-look family — GorAVPlaybackCore control/parameter sources (1nstinct G0854 claim)

Source: goreda/gorav lane/gdb-m3-render @ 47f8a39c7941e483d99b95f7ea4fac94eae56a84
(arch-196z item 3 P23(b), 2026-11-16). Extracted verbatim, no edits.

## Files (sha256)
f03547a8b418d440b0d79de36b68becd1d99b0461cc6b19b00da1c92010e4dbe  LookParameterBlock.swift
eded915407feb11e4e2c57245b2f7a58b0fcc255e6cc6c8fe35f6c4cbd615eb3  ControlBus.swift
24d8e9f53b044811f39268299767fad5a2bf788982133439138f5269c5678c31  AudioTrackPlan.swift
2f92e561c99bfeaf42c1bbd7c99d62213b965af19049212a74b0be3af65722d9  main.swift

- LookParameterBlock.swift (Sources/GorAVPlaybackCore/) — typed look parameter block, LookUniformABI wire format, LookUniformConsumer. import Foundation only.
- ControlBus.swift (Sources/GorAVPlaybackCore/) — G5/P24 typed control surface + G6/P25 presentation-receipt consumer. No imports (pure stdlib).
- AudioTrackPlan.swift (Sources/GorAVPlaybackCore/) — REQUIRED dependency of ControlBus (AudioTrackSelector, R6 arch-195l). import Foundation only.
- main.swift (Sources/controlbus-tests/) — Linux test harness (35 assertions, exit 0 = pass).

## Build contract
- Toolchain: Swift 6.1.2 RELEASE (verified on swift-6.1.2-RELEASE-ubuntu22.04, x86_64-unknown-linux-gnu). Package manifest at that commit: swift-tools-version 5.9. Mac target: macOS 13+ (package platforms).
- Library compile:
    swiftc -module-name GorAVPlaybackCore -emit-library -emit-module       LookParameterBlock.swift ControlBus.swift AudioTrackPlan.swift -o libGorAVPlaybackCore.so
- Test harness compile + run:
    swiftc -I . -L . -lGorAVPlaybackCore main.swift -o controlbus-tests
    LD_LIBRARY_PATH=. ./controlbus-tests   # -> "controlbus-tests: all pass", exit 0
- In the gorav package the three sources are files of the GorAVPlaybackCore target and
  controlbus-tests is an executableTarget depending on it (Package.swift @ 47f8a39c).

## Verification as-run (Linux, 2026-11-16 23:10 +03)
lib + harness compiled clean with the commands above; ./controlbus-tests printed
35x PASS ... "controlbus-tests: all pass", rc=0. Mac/Metal: NOT_TESTED.
