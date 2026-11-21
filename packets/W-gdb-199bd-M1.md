# W-gdb-199bd-M1: three in2tinct code tasks

Assigned to in2tinct. GO on receipt: implement the three independent Swift helper tasks below and return actual code plus runnable Linux tests. This is a code work order, not a capacity question. No paid service, account change, deployment or external messaging is authorized.

Return standalone policy/helpers with tests and small adapter sketches. Do not replace private files from guesses. Do not modify shared product branches. Native AppKit behavior is not established by Linux policy tests. No source, logs, user media or licensed assets are attached.

The file references identify composition targets. Defects were observed in retained source, not yet compared to current c874. Retained WindowModeController.swift SHA256 af63f1707be47d49938bb1df7e2527e355fc24a56fd4d56b2ae49894904c8365; WindowModePlan.swift SHA256 cce8e9b8ce7bbb69d68d1bd4e93c918f78b72e7d4b4ec98e7cc345a6a4d6763b. Current-source comparison proceeds independently. Start public-interface helpers now, not a guessed complete-file patch.

## 1. Fullscreen restore capture

Target: Packages/gorav/Sources/GorAVMacShell/WindowModeController.swift.

Retained implementation captures restore geometry during didEnter for external fullscreen entry. That can capture fullscreen bounds or retain an outdated windowed frame. Implement a platform-free capture/reconcile policy and adapter delta: capture the latest windowed frame at willEnter, preserve it through didEnter and duplicate notifications, restore once at didExit. Keep programmatic toggle behavior and existing window position/size contract.

Tests on Linux: moving/resizing A to B before external entry must restore B; later roundtrips must capture latest C; duplicate will/did events cannot save fullscreen geometry; programmatic and notification event interleaving cannot restore twice.

## 2. PiP admission transaction

Targets: WindowModeController.swift above and existing WindowModePlan.swift.

Retained enter() advances state before the content-view handoff can refuse for missing superview. Implement an isolated prepare/apply/commit helper and adapter sketch. Missing content view or failed handoff must refuse without changing mode or restore state or hiding the original window. Success reparents one content view without duplicate ownership/layer. Exit with no PiP custody must refuse without advancing state. Keep this helper separate from task 1. No Host, crop, effects or Package changes.

Linux recorder tests: missing-view entry, absent-custody exit and simulated apply failure preserve state and original visibility; success commits exactly once; retry after refusal works; never duplicate content ownership.

## 3. PiP geometry numeric safety

Target: Packages/gorav/Sources/GorAVPlaybackCore/WindowModePlan.swift, PipSize.fit. Existing test target: Sources/window-mode-tests/main.swift.

Retained fitting code validates finite content but not finite maximum bounds, then rounds dimensions through multiplication by 1000 without validating outputs. Implement finite-positive validation of all inputs and overflow/underflow-safe aspect fitting. Preserve ordinary 16:9, 4:3 and portrait behavior with three-decimal sizing. A successful result must be finite, positive, within the max box and aspect-preserving. Do not add an arbitrary minimum-width bump.

Linux tests: reject NaN, either infinity, zero and negative content/bounds; extreme finite dimensions/scales must either refuse or produce finite positive bounded aspect-preserving output; ordinary 480x270 behavior stays unchanged; refusal leaves WindowModeState unchanged.

Deliver code and reproducible test command/results, clearly separating executed Linux behavior from untested native integration. Return through your existing hosted reply/carrier route or a reply file for this packet.
