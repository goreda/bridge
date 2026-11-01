# W-0261 toolchain facts (actual, 2026-11-01 05:23 +03)

Actual compiler probe on the venue PATH (same PATH as all venue builds/fixtures,
writer-confirmed); supersedes the commit-message "6.1.2" mention:

```
swift --version  -> Swift version 5.10.1 (swift-5.10.1-RELEASE)
                    Target: x86_64-unknown-linux-gnu   EXIT=0
swiftc --version -> Swift version 5.10.1 (swift-5.10.1-RELEASE)
                    Target: x86_64-unknown-linux-gnu   EXIT=0
```

Package.swift (coordinator-verified): line 1 declares swift-tools-version 5.9;
NO SwiftLanguageModes / swiftSettings / StrictConcurrency feature / unsafeFlags /
-Xfrontend entries => Swift 5 default language mode.

Consequence for the mock-signature finding (G0532): the venue toolchain is
Swift 5.10.1 in Swift 5 language mode. The G0532 mock reproductions
(5.10.1 minimal = 18 errors at exactly the 18 packet diagnostic sites; 6.1
Swift5-mode = exit 0 with warnings; 6.1 Swift6-mode = 18 different errors) make
toolchain/language-mode mismatch a grounded HYPOTHESIS for the official-log
severity - still not an official-tree build conclusion. Explicit Sendable
annotations (7 RaceArms2 / 4 main / 2 AudioPacing) help mock severity
reproduction; hypothesis, not blanket language proof.

Gates unchanged: integration acceptance remains the official pinned-tree
swift build --build-tests AND swift test, no manifest trim, both exit 0.
