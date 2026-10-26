# W-0110 gor r14 recovery harness - reproduction pack

Result: real Swift compile + run, 49/49 checks pass (exit 0), 26 Oct 2026.

## Contents
- Sources/RecoveryCore.swift - extracted production classifier/recovery code + disclosed injections
- Sources/Fakes.swift - explicitly labeled fakes (update process, gated executors)
- Tests/main.swift - 18-scenario Foundation-only runner (gates/ACK, no sleeps)
- TRANSFORMATIONS.md - every deviation from the pinned source, enumerated
- build-log.txt - toolchain provenance + exact compile command + exit
- run-log.txt - full actual run output (49 PASS lines + summary)
- binding-check.txt - verbatim-fidelity diff output + packet test_update.py result

## Source pin
goreda/bridge @ 91da2e7f2433e712a8b9341b404ffa6ce1fd9964
- packets/w-0110-gor-r14-recovery-harness/AppDelegate.swift
  sha256 3ce05563098bc930d96315f657aa2a71676e6a73a66493278ced6dd9af380a55 (3329 lines)
- packets/w-0110-gor-r14-recovery-harness/test_update.py
  sha256 3b2667a7fe8053af8682d339ffe77a7ece43bc706adf8a3dd0d944a8482c7f3c

## Toolchain
Swift 6.1 (swift-6.1-RELEASE), x86_64-unknown-linux-gnu
https://download.swift.org/swift-6.1-release/ubuntu2204/swift-6.1-RELEASE/swift-6.1-RELEASE-ubuntu22.04.tar.gz
879,139,105 bytes, sha256 7ae2d70dfcd1b36980e71ab68c89e346fd8f1edc81a852b17b5f7eecdda3a866

## Reproduce from a clean copy
```
tar -xzf w0110-repro.tar.gz && cd w0110
<swift-toolchain>/usr/bin/swiftc -O Sources/RecoveryCore.swift Sources/Fakes.swift Tests/main.swift -o /tmp/w0110-harness
/tmp/w0110-harness   # expect: ==== 49 passed, 0 failed ====, exit 0
```
Fixtures are self-created in $TMPDIR by the runner (pristine per-scenario
binaries); no other files are needed. No network, credentials, AppKit or macOS
required. Scope: extracted-logic behavior only - not AppKit/UI/native proof,
no CDN-403-cure claim.
