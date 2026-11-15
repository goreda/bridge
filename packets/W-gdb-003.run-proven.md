# W-gdb-003 WindowModePlan edge tests
state: candidate
solver lab: unclaimed
reviewer lab: unclaimed
id: W-gdb-003

```packet-json
{
  "packet_id": "W-gdb-003",
  "writer": "gdb",
  "code_owner": "gdb integrator (gorav lane)",
  "product_repo": "goreda/gorav",
  "product_sha": "91a8b69abe9ce61e31188e3d426477a3f8528ede",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/WindowModePlan.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "transition(to: WindowMode, currentWindowedFrame: WindowFrame?, contentSize: (width: Double, height: Double)?) -> Result<WindowModeDecision, WindowModeRefusal>; PipSize.fit(contentWidth:contentHeight:maxWidth:maxHeight:) -> Result<PipSize, WindowModeRefusal>",
    "types": "WindowMode { windowed, fullscreen, pictureInPicture }; WindowModeRefusal { alreadyInMode, requiresWindowedFirst, noRestoreFrame, degenerateContentSize }; WindowModeDecision 4 cases; WindowFrame; PipSize max 480x270",
    "ownership_lifetime": "value types only; no window server objects cross the seam",
    "caller": "WindowModeController (AppKit shell, Darwin-only) calling WindowModeState.transition",
    "callee": "WindowModeState.transition(to:currentWindowedFrame:contentSize:) + PipSize.fit (WindowModePlan.swift)"
  },
  "test": {
    "command": "swift run window-mode-tests",
    "expected": "exit 0; final line 'window-mode-tests: N PASS, 0 FAIL' with N >= 21 (existing W1-W21) + the new edge rows; any failed check prints one 'FAIL <label>' line",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "main",
    "paths": [
      "Sources/window-mode-tests/",
      "Sources/GorAVPlaybackCore/WindowModePlan.swift"
    ],
    "return_form": "patch"
  },
  "run_recipe": {
    "inline_files": [
      {
        "path": "Sources/window-mode-tests/main.swift",
        "block": "rf0",
        "content": "// G3 (arch-195l, dispatch L6) window-mode policy tests. Pure Swift, runs on\n// Linux. One check() counter style like crop-tests / audio-delay-tests.\nimport Foundation\nimport GorAVPlaybackCore\n\nvar pass = 0, fail = 0\nfunc check(_ cond: Bool, _ name: String) {\n    if cond { pass += 1; print(\"PASS \\(name)\") }\n    else { fail += 1; print(\"FAIL \\(name)\") }\n}\n\nlet frame = WindowFrame(x: 200, y: 200, width: 640, height: 480)\n\n// W1-W3: windowed -> fullscreen saves the restore frame and enters.\nvar s = WindowModeState()\nlet w1 = s.transition(to: .fullscreen, currentWindowedFrame: frame)\ncheck({ if case .success(.enterFullscreen(let f)) = w1 { return f == frame } else { return false } }(),\n      \"W1 windowed->fullscreen returns enterFullscreen with the saved frame\")\ncheck(s.mode == .fullscreen, \"W2 state advances to fullscreen\")\ncheck(s.windowedRestore == frame, \"W3 restore frame recorded\")\n\n// W4-W5: fullscreen -> windowed restores.\nlet w4 = s.transition(to: .windowed, currentWindowedFrame: nil)\ncheck({ if case .success(.exitFullscreen(let r)) = w4 { return r == frame } else { return false } }(),\n      \"W4 fullscreen->windowed returns exitFullscreen with the recorded frame\")\ncheck(s.mode == .windowed, \"W5 state back to windowed\")\n\n// W6: same-mode request is a typed no-op refusal, state untouched.\nvar s6 = WindowModeState()\nlet w6 = s6.transition(to: .windowed, currentWindowedFrame: nil)\ncheck({ if case .failure(.alreadyInMode(.windowed)) = w6 { return true } else { return false } }(),\n      \"W6 windowed->windowed refused as alreadyInMode\")\n\n// W7-W8: fullscreen <-> PiP direct hops are refused, state untouched.\nvar s7 = WindowModeState()\n_ = s7.transition(to: .fullscreen, currentWindowedFrame: frame)\nlet w7 = s7.transition(to: .pictureInPicture, currentWindowedFrame: nil,\n                       contentSize: (1920, 1080))\ncheck({ if case .failure(.requiresWindowedFirst(.fullscreen, .pictureInPicture)) = w7 { return true } else { return false } }(),\n      \"W7 fullscreen->pip refused requiresWindowedFirst\")\ncheck(s7.mode == .fullscreen, \"W8 state stays fullscreen after refusal\")\n\n// W9: PiP -> fullscreen refused the other way.\nvar s9 = WindowModeState()\n_ = s9.transition(to: .pictureInPicture, currentWindowedFrame: frame, contentSize: (1920, 1080))\nlet w9 = s9.transition(to: .fullscreen, currentWindowedFrame: nil)\ncheck({ if case .failure(.requiresWindowedFirst(.pictureInPicture, .fullscreen)) = w9 { return true } else { return false } }(),\n      \"W9 pip->fullscreen refused requiresWindowedFirst\")\n\n// W10-W12: windowed -> PiP fits 16:9 into the 480x270 box exactly.\nvar s10 = WindowModeState()\nlet w10 = s10.transition(to: .pictureInPicture, currentWindowedFrame: frame,\n                         contentSize: (1920, 1080))\ncheck({ if case .success(.enterPiP(let p, let f)) = w10 {\n            return p.width == 480 && p.height == 270 && f == frame }\n        else { return false } }(),\n      \"W10 16:9 content fits the 480x270 PiP box\")\ncheck(s10.mode == .pictureInPicture, \"W11 state advances to pictureInPicture\")\ncheck(s10.windowedRestore == frame, \"W12 restore frame recorded at PiP entry\")\n\n// W13: PiP -> windowed restores.\nlet w13 = s10.transition(to: .windowed, currentWindowedFrame: nil)\ncheck({ if case .success(.exitPiP(let r)) = w13 { return r == frame } else { return false } }(),\n      \"W13 pip->windowed returns exitPiP with the recorded frame\")\n\n// W14: leaving windowed without a current frame is a typed refusal.\nvar s14 = WindowModeState()\nlet w14 = s14.transition(to: .fullscreen, currentWindowedFrame: nil)\ncheck({ if case .failure(.noRestoreFrame) = w14 { return true } else { return false } }(),\n      \"W14 fullscreen without a current frame refused noRestoreFrame\")\n\n// W15: PiP entry without content size is a typed refusal.\nvar s15 = WindowModeState()\nlet w15 = s15.transition(to: .pictureInPicture, currentWindowedFrame: frame, contentSize: nil)\ncheck({ if case .failure(.noRestoreFrame) = w15 { return true } else { return false } }(),\n      \"W15 pip without content size refused\")\n\n// W16: degenerate content size is a typed refusal, never a guessed size.\nvar s16 = WindowModeState()\nlet w16 = s16.transition(to: .pictureInPicture, currentWindowedFrame: frame,\n                         contentSize: (0, 1080))\ncheck({ if case .failure(.degenerateContentSize) = w16 { return true } else { return false } }(),\n      \"W16 zero-width content refused degenerateContentSize\")\n\n// W17: 4:3 content fits by height, width follows aspect.\nif case .success(let p) = PipSize.fit(contentWidth: 1440, contentHeight: 1080) {\n    check(p.height == 270 && abs(p.width - 360) < 0.01, \"W17 4:3 content fits to 360x270\")\n} else { check(false, \"W17 4:3 content fits to 360x270\") }\n\n// W18: content already at the box aspect fills the box exactly.\nif case .success(let p) = PipSize.fit(contentWidth: 160, contentHeight: 90) {\n    check(p.width == 480 && p.height == 270, \"W18 box-aspect content fills the PiP box\")\n} else { check(false, \"W18 box-aspect content fills the PiP box\") }\n\n// W19: very tall content is capped by height, narrow width, aspect kept\n// (no minimum-width bump - it would either overflow the box or be\n// unreachable under max-bounds scaling).\nif case .success(let p) = PipSize.fit(contentWidth: 90, contentHeight: 1600) {\n    let aspect = p.width / p.height\n    check(p.height == 270 && abs(aspect - (90.0 / 1600.0)) < 0.01,\n          \"W19 tall content capped by height, aspect kept\")\n} else { check(false, \"W19 tall content capped by height, aspect kept\") }\n\n// W20: non-finite content refused.\nif case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: .nan, contentHeight: 100) {\n    check(true, \"W20 NaN content refused\")\n} else { check(false, \"W20 NaN content refused\") }\n\n// W21: rounding is stable to 3 decimals (480.0 not 479.9999...).\nif case .success(let p) = PipSize.fit(contentWidth: 1920, contentHeight: 1080) {\n    check(p.width * 1000 == (p.width * 1000).rounded(), \"W21 pip size rounded to 3 decimals\")\n} else { check(false, \"W21 pip size rounded to 3 decimals\") }\n\nprint(\"window-mode-tests: \\(pass) PASS, \\(fail) FAIL\")\nexit(fail == 0 ? 0 : 1)\n"
      }
    ]
  },
  "run_proof": {
    "version": 1,
    "product_sha": "91a8b69abe9ce61e31188e3d426477a3f8528ede",
    "command": "swift run window-mode-tests",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-15T23:01:34.586684+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "window-mode-tests: 21 PASS, 0 FAIL",
    "inline_files": [
      {
        "path": "Sources/window-mode-tests/main.swift",
        "block": "rf0",
        "sha256": "09640617ae9065cf34ce0f0c42b44fdb92c59e69e1dbc16aca0aaf430b1b5a20"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "1c985eef41392d6bfdeacaee78e20038b3ad244de2d5b58c44bcf42829781783",
    "last_5_lines": [
      "PASS W18 box-aspect content fills the PiP box",
      "PASS W19 tall content capped by height, aspect kept",
      "PASS W20 NaN content refused",
      "PASS W21 pip size rounded to 3 decimals",
      "window-mode-tests: 21 PASS, 0 FAIL"
    ],
    "receipt_sha256": "780396f0c84edc2ca5ced9296b84de3b73843e5a79d8636bb3f160c5f7d54489"
  }
}
```

## problem (what fails for the user)
window-mode transitions (windowed/fullscreen variants) are planned by WindowModeState.transition (GorAVPlaybackCore, Linux-testable) and only applied to AppKit by WindowModeController; edge inputs - toggle storms, display disconnect mid-fullscreen, zero-size/minimized source, multi-screen move, stale plan applied after abort - have no fixture coverage, so a bad plan ships as a lost or flickering window.

## reproducer
- repo: goreda/gorav @ 91a8b69abe9ce61e31188e3d426477a3f8528ede (branch main).
- real source: Sources/GorAVPlaybackCore/WindowModePlan.swift (sha256 cce8e9b8, 163 lines) - WindowModeState.transition, the planner; Sources/window-mode-tests/main.swift (sha256 09640617, 6136B) - the existing suite to extend.
- real test command: swift run window-mode-tests (macOS target; Linux runs the portable model below).

## expected behaviour
an edge-case suite over a deterministic synthetic display model: the five input classes above, asserting exact plan sequences and terminal states; no real window server. the suite is portable so it runs on Linux against the plan logic, with the macOS leg riding the existing executable.

## exact call site and interface
WindowModeState.transition (pinned excerpt) and the window-mode-tests executable entry point; fixtures + expected tables + runner are the deliverable.

## pinned ABI decisions (integrator, 2026-11-15)
the plan/state API lives in Sources/GorAVPlaybackCore/WindowModePlan.swift (same pin; platform-free, Linux-tested by window-mode-tests W1-W21) - NOT in the Darwin-only controller excerpt above, which only APPLIES decisions to AppKit:
- public struct WindowFrame { x, y, width, height: Double }
- public enum WindowMode: String, CaseIterable { windowed, fullscreen, pictureInPicture }
- public enum WindowModeRefusal: Error { alreadyInMode(WindowMode), requiresWindowedFirst(from: WindowMode, to: WindowMode), noRestoreFrame, degenerateContentSize }
- public enum WindowModeDecision { enterFullscreen(saveRestore: WindowFrame), exitFullscreen(restore: WindowFrame?), enterPiP(pipFrameSize: PipSize, saveRestore: WindowFrame), exitPiP(restore: WindowFrame?) }
- public struct PipSize { width, height: Double; static defaultMaxWidth = 480.0; static defaultMaxHeight = 270.0; static fit(contentWidth:contentHeight:maxWidth:maxHeight:) -> Result<PipSize, WindowModeRefusal> } - aspect-preserving fit, .degenerateContentSize refusal, never a guessed size
- public struct WindowModeState { mode: WindowMode; windowedRestore: WindowFrame?; mutating transition(to: WindowMode, currentWindowedFrame: WindowFrame?, contentSize: (width: Double, height: Double)? = nil) -> Result<WindowModeDecision, WindowModeRefusal> } - state advances only on success; a refusal leaves it untouched
- direct fullscreen<->pictureInPicture hops are REFUSED (.requiresWindowedFirst): the edge atlas asserts this refusal, never expects a hop.

## behaviour that must not change
the planner's current accepted behavior on non-edge inputs; Package.swift target graph; no new dependency.

## acceptance test (from the product repo)
swift run window-mode-tests stays green AND the new edge fixtures pass; a seeded wrong plan (negative control) fails the suite.

## pinned excerpts (gorav-src @ 2112af0d60df16c5473173b664903f76ce54173e)
### Sources/GorAVPlaybackCore/WindowModePlan.swift (sha256 cce8e9b8, lines 104-161 of 163)
```swift id=source1
public struct WindowModeState: Equatable, Sendable {
    public private(set) var mode: WindowMode
    /// The windowed frame captured on the last exit from .windowed; restored
    /// when returning to .windowed. nil until the first transition away.
    public private(set) var windowedRestore: WindowFrame?

    public init(mode: WindowMode = .windowed, windowedRestore: WindowFrame? = nil) {
        self.mode = mode
        self.windowedRestore = windowedRestore
    }

    /// Request a transition. currentWindowedFrame is the window's frame NOW,
    /// required when leaving .windowed so it can be restored later; content
    /// size is required when entering PiP. The state only advances on
    /// success; a refusal leaves it untouched.
    public mutating func transition(to target: WindowMode,
                                    currentWindowedFrame: WindowFrame?,
                                    contentSize: (width: Double, height: Double)? = nil
    ) -> Result<WindowModeDecision, WindowModeRefusal> {
        if target == mode { return .failure(.alreadyInMode(mode)) }
        // Direct fullscreen <-> PiP hops are refused (documented choice).
        if (mode == .fullscreen && target == .pictureInPicture) ||
           (mode == .pictureInPicture && target == .fullscreen) {
            return .failure(.requiresWindowedFirst(from: mode, to: target))
        }
        switch target {
        case .fullscreen:
            guard mode == .windowed else {
                return .failure(.requiresWindowedFirst(from: mode, to: target))
            }
            guard let frame = currentWindowedFrame else { return .failure(.noRestoreFrame) }
            mode = .fullscreen
            windowedRestore = frame
            return .success(.enterFullscreen(saveRestore: frame))
        case .pictureInPicture:
            guard mode == .windowed else {
                return .failure(.requiresWindowedFirst(from: mode, to: target))
            }
            guard let frame = currentWindowedFrame else { return .failure(.noRestoreFrame) }
            guard let size = contentSize else { return .failure(.noRestoreFrame) }
            let fit = PipSize.fit(contentWidth: size.width, contentHeight: size.height)
            switch fit {
            case .failure(let r): return .failure(r)
            case .success(let pip):
                mode = .pictureInPicture
                windowedRestore = frame
                return .success(.enterPiP(pipFrameSize: pip, saveRestore: frame))
            }
        case .windowed:
            let previous = mode
            mode = .windowed
            let restore = windowedRestore
            switch previous {
            case .fullscreen: return .success(.exitFullscreen(restore: restore))
            case .pictureInPicture: return .success(.exitPiP(restore: restore))
            case .windowed: return .failure(.alreadyInMode(.windowed))  // unreachable
            }
        }
```

## roles and state
solver lab: unclaimed. reviewer lab: unclaimed. neither approval is product acceptance; the owner's eyes close it.

secret scan: clean

```json id=fixtures1
[{"class":"toggle-storm","ops":["fullscreen","fullscreen","windowed"],"expectTerminal":"windowed","expectRefusals":["alreadyInMode(fullscreen)"]},
 {"class":"fs-pip-hop","ops":["fullscreen","pictureInPicture"],"expectRefusals":["requiresWindowedFirst(from:fullscreen,to:pictureInPicture)"]},
 {"class":"zero-size-pip","ops":["pictureInPicture"],"contentSize":[0,400],"expectRefusals":["degenerateContentSize"]}]
```


```text id=rf0
// G3 (arch-195l, dispatch L6) window-mode policy tests. Pure Swift, runs on
// Linux. One check() counter style like crop-tests / audio-delay-tests.
import Foundation
import GorAVPlaybackCore

var pass = 0, fail = 0
func check(_ cond: Bool, _ name: String) {
    if cond { pass += 1; print("PASS \(name)") }
    else { fail += 1; print("FAIL \(name)") }
}

let frame = WindowFrame(x: 200, y: 200, width: 640, height: 480)

// W1-W3: windowed -> fullscreen saves the restore frame and enters.
var s = WindowModeState()
let w1 = s.transition(to: .fullscreen, currentWindowedFrame: frame)
check({ if case .success(.enterFullscreen(let f)) = w1 { return f == frame } else { return false } }(),
      "W1 windowed->fullscreen returns enterFullscreen with the saved frame")
check(s.mode == .fullscreen, "W2 state advances to fullscreen")
check(s.windowedRestore == frame, "W3 restore frame recorded")

// W4-W5: fullscreen -> windowed restores.
let w4 = s.transition(to: .windowed, currentWindowedFrame: nil)
check({ if case .success(.exitFullscreen(let r)) = w4 { return r == frame } else { return false } }(),
      "W4 fullscreen->windowed returns exitFullscreen with the recorded frame")
check(s.mode == .windowed, "W5 state back to windowed")

// W6: same-mode request is a typed no-op refusal, state untouched.
var s6 = WindowModeState()
let w6 = s6.transition(to: .windowed, currentWindowedFrame: nil)
check({ if case .failure(.alreadyInMode(.windowed)) = w6 { return true } else { return false } }(),
      "W6 windowed->windowed refused as alreadyInMode")

// W7-W8: fullscreen <-> PiP direct hops are refused, state untouched.
var s7 = WindowModeState()
_ = s7.transition(to: .fullscreen, currentWindowedFrame: frame)
let w7 = s7.transition(to: .pictureInPicture, currentWindowedFrame: nil,
                       contentSize: (1920, 1080))
check({ if case .failure(.requiresWindowedFirst(.fullscreen, .pictureInPicture)) = w7 { return true } else { return false } }(),
      "W7 fullscreen->pip refused requiresWindowedFirst")
check(s7.mode == .fullscreen, "W8 state stays fullscreen after refusal")

// W9: PiP -> fullscreen refused the other way.
var s9 = WindowModeState()
_ = s9.transition(to: .pictureInPicture, currentWindowedFrame: frame, contentSize: (1920, 1080))
let w9 = s9.transition(to: .fullscreen, currentWindowedFrame: nil)
check({ if case .failure(.requiresWindowedFirst(.pictureInPicture, .fullscreen)) = w9 { return true } else { return false } }(),
      "W9 pip->fullscreen refused requiresWindowedFirst")

// W10-W12: windowed -> PiP fits 16:9 into the 480x270 box exactly.
var s10 = WindowModeState()
let w10 = s10.transition(to: .pictureInPicture, currentWindowedFrame: frame,
                         contentSize: (1920, 1080))
check({ if case .success(.enterPiP(let p, let f)) = w10 {
            return p.width == 480 && p.height == 270 && f == frame }
        else { return false } }(),
      "W10 16:9 content fits the 480x270 PiP box")
check(s10.mode == .pictureInPicture, "W11 state advances to pictureInPicture")
check(s10.windowedRestore == frame, "W12 restore frame recorded at PiP entry")

// W13: PiP -> windowed restores.
let w13 = s10.transition(to: .windowed, currentWindowedFrame: nil)
check({ if case .success(.exitPiP(let r)) = w13 { return r == frame } else { return false } }(),
      "W13 pip->windowed returns exitPiP with the recorded frame")

// W14: leaving windowed without a current frame is a typed refusal.
var s14 = WindowModeState()
let w14 = s14.transition(to: .fullscreen, currentWindowedFrame: nil)
check({ if case .failure(.noRestoreFrame) = w14 { return true } else { return false } }(),
      "W14 fullscreen without a current frame refused noRestoreFrame")

// W15: PiP entry without content size is a typed refusal.
var s15 = WindowModeState()
let w15 = s15.transition(to: .pictureInPicture, currentWindowedFrame: frame, contentSize: nil)
check({ if case .failure(.noRestoreFrame) = w15 { return true } else { return false } }(),
      "W15 pip without content size refused")

// W16: degenerate content size is a typed refusal, never a guessed size.
var s16 = WindowModeState()
let w16 = s16.transition(to: .pictureInPicture, currentWindowedFrame: frame,
                         contentSize: (0, 1080))
check({ if case .failure(.degenerateContentSize) = w16 { return true } else { return false } }(),
      "W16 zero-width content refused degenerateContentSize")

// W17: 4:3 content fits by height, width follows aspect.
if case .success(let p) = PipSize.fit(contentWidth: 1440, contentHeight: 1080) {
    check(p.height == 270 && abs(p.width - 360) < 0.01, "W17 4:3 content fits to 360x270")
} else { check(false, "W17 4:3 content fits to 360x270") }

// W18: content already at the box aspect fills the box exactly.
if case .success(let p) = PipSize.fit(contentWidth: 160, contentHeight: 90) {
    check(p.width == 480 && p.height == 270, "W18 box-aspect content fills the PiP box")
} else { check(false, "W18 box-aspect content fills the PiP box") }

// W19: very tall content is capped by height, narrow width, aspect kept
// (no minimum-width bump - it would either overflow the box or be
// unreachable under max-bounds scaling).
if case .success(let p) = PipSize.fit(contentWidth: 90, contentHeight: 1600) {
    let aspect = p.width / p.height
    check(p.height == 270 && abs(aspect - (90.0 / 1600.0)) < 0.01,
          "W19 tall content capped by height, aspect kept")
} else { check(false, "W19 tall content capped by height, aspect kept") }

// W20: non-finite content refused.
if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: .nan, contentHeight: 100) {
    check(true, "W20 NaN content refused")
} else { check(false, "W20 NaN content refused") }

// W21: rounding is stable to 3 decimals (480.0 not 479.9999...).
if case .success(let p) = PipSize.fit(contentWidth: 1920, contentHeight: 1080) {
    check(p.width * 1000 == (p.width * 1000).rounded(), "W21 pip size rounded to 3 decimals")
} else { check(false, "W21 pip size rounded to 3 decimals") }

print("window-mode-tests: \(pass) PASS, \(fail) FAIL")
exit(fail == 0 ? 0 : 1)

```

```text id=actual_run_log
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-zto6v8mp/tree/Sources/timing-ledger-tests/ClockScenarioReplay.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/ASSTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 4 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitleTrackTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitleControllerTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SubtitlePlanTests.swift
    /tmp/packet-proof-zto6v8mp/tree/Sources/subtitle-tests/SRTTests.swift
warning: 'tree': found 1 file(s) which are unhandled; explicitly declare them as resources or exclude from the target
    /tmp/packet-proof-zto6v8mp/tree/Sources/seek-composition-tests/README-SEEKVECTORS.md
Building for debugging...
[0/12] Write sources
[4/12] Compiling GorAVCAtomics gorav_atomics.c
[5/12] Write swift-version--9C6B84B6E025C5B.txt
[7/15] Emitting module GorAVCore
[8/15] Compiling GorAVCore AdmissionTable.swift
[9/15] Compiling GorAVCore Boundary.swift
[10/16] Compiling GorAVCore OpenURLRouter.swift
[11/17] Wrapping AST for GorAVCore for debugging
[13/21] Emitting module GorAVNativeProbeKit
[14/23] Compiling GorAVNativeProbeKit NativeProbe.swift
[15/23] Compiling GorAVNativeProbeKit PacketFeedMachine.swift
[16/23] Compiling GorAVNativeProbeKit DemuxerPolicy.swift
[17/23] Compiling GorAVNativeProbeKit GorAVSeekContract.swift
[18/23] Compiling GorAVNativeProbeKit LeaseTable.swift
[19/24] Wrapping AST for GorAVNativeProbeKit for debugging
[21/47] Emitting module GorAVPlaybackCore
[22/68] Compiling GorAVPlaybackCore LabYtdlpAdapter.swift
[23/68] Compiling GorAVPlaybackCore Lane0Contract.swift
[24/68] Compiling GorAVPlaybackCore LifetimeRegistry.swift
[25/68] Compiling GorAVPlaybackCore ObservationSurface.swift
[26/68] Compiling GorAVPlaybackCore PlayArguments.swift
[27/68] Compiling GorAVPlaybackCore PlaybackCore.swift
[28/68] Compiling GorAVPlaybackCore PlayerControlPlane.swift
[29/68] Compiling GorAVPlaybackCore PlayheadObservers.swift
[30/68] Compiling GorAVPlaybackCore PlayheadPosition.swift
[31/68] Compiling GorAVPlaybackCore PreparedAdoption.swift
[32/68] Compiling GorAVPlaybackCore PreparedShotSession.swift
[33/68] Compiling GorAVPlaybackCore PreparedVideoFrameSource.swift
[34/68] Compiling GorAVPlaybackCore ReadinessAnchorSession.swift
[35/68] Compiling GorAVPlaybackCore RenderGraph.swift
[36/68] Compiling GorAVPlaybackCore SPSC.swift
[37/68] Compiling GorAVPlaybackCore ShellSeekBridge.swift
[38/68] Compiling GorAVPlaybackCore StageGeometry.swift
[39/68] Compiling GorAVPlaybackCore TapCropDetector.swift
[40/68] Compiling GorAVPlaybackCore TimingLedger.swift
[41/68] Compiling GorAVPlaybackCore UniformPacking.swift
[42/68] Compiling GorAVPlaybackCore WindowModePlan.swift
[43/68] Compiling GorAVPlaybackCore AudioTrackPlan.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[44/68] Compiling GorAVPlaybackCore ColorStage.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[45/68] Compiling GorAVPlaybackCore ControlBus.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[46/68] Compiling GorAVPlaybackCore CoreSeekDriver.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[47/68] Compiling GorAVPlaybackCore CropStage.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[48/68] Compiling GorAVPlaybackCore DecodeHeartbeat.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[49/68] Compiling GorAVPlaybackCore DecodedFrameLeaseBridge.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[50/68] Compiling GorAVPlaybackCore DecodedFrameTap.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[51/68] Compiling GorAVPlaybackCore DecoderInventory.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[52/68] Compiling GorAVPlaybackCore FrameLeaseStore.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[53/68] Compiling GorAVPlaybackCore FrameUniformABI.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[54/68] Compiling GorAVPlaybackCore HostTransform.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[55/68] Compiling GorAVPlaybackCore LabColorCurves.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[56/68] Compiling GorAVPlaybackCore LabCropEngine.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[57/68] Compiling GorAVPlaybackCore LabHLSPlaylist.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[58/68] Compiling GorAVPlaybackCore LabMarginOracle.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[59/68] Compiling GorAVPlaybackCore LabMusicMode.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[60/68] Compiling GorAVPlaybackCore LabPGSDecoder.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[61/68] Compiling GorAVPlaybackCore LabPTSDuration.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[62/68] Compiling GorAVPlaybackCore LabStereoResolver.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[63/68] Compiling GorAVPlaybackCore LabSwrConverter.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[64/68] Compiling GorAVPlaybackCore LabVobSubDecoder.swift
/tmp/packet-proof-zto6v8mp/tree/Sources/GorAVPlaybackCore/CoreSeekDriver.swift:80:103: warning: code after 'return' will never be executed
        catch SeekRefusal.legacyRejected(let r) { return .admissionRefused(reason: .legacyRejected) ; _ = r }
                                                                                                      ^
[65/69] Wrapping AST for GorAVPlaybackCore for debugging
[67/71] Emitting module window_mode_tests
[68/71] Compiling window_mode_tests main.swift
[69/72] Wrapping AST for window-mode-tests for debugging
[70/72] Write Objects.LinkFileList
[71/72] Linking window-mode-tests
Build complete! (7.15s)
PASS W1 windowed->fullscreen returns enterFullscreen with the saved frame
PASS W2 state advances to fullscreen
PASS W3 restore frame recorded
PASS W4 fullscreen->windowed returns exitFullscreen with the recorded frame
PASS W5 state back to windowed
PASS W6 windowed->windowed refused as alreadyInMode
PASS W7 fullscreen->pip refused requiresWindowedFirst
PASS W8 state stays fullscreen after refusal
PASS W9 pip->fullscreen refused requiresWindowedFirst
PASS W10 16:9 content fits the 480x270 PiP box
PASS W11 state advances to pictureInPicture
PASS W12 restore frame recorded at PiP entry
PASS W13 pip->windowed returns exitPiP with the recorded frame
PASS W14 fullscreen without a current frame refused noRestoreFrame
PASS W15 pip without content size refused
PASS W16 zero-width content refused degenerateContentSize
PASS W17 4:3 content fits to 360x270
PASS W18 box-aspect content fills the PiP box
PASS W19 tall content capped by height, aspect kept
PASS W20 NaN content refused
PASS W21 pip size rounded to 3 decimals
window-mode-tests: 21 PASS, 0 FAIL
```
