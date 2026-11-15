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
 "product_sha": "2112af0d60df16c5473173b664903f76ce54173e",
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
  "branch": "ohal/gorav",
  "paths": [
   "Sources/window-mode-tests/",
   "Sources/GorAVPlaybackCore/WindowModePlan.swift"
  ],
  "return_form": "patch"
 }
}
```

## problem (what fails for the user)
window-mode transitions (windowed/fullscreen variants) are planned by WindowModeState.transition (GorAVPlaybackCore, Linux-testable) and only applied to AppKit by WindowModeController; edge inputs - toggle storms, display disconnect mid-fullscreen, zero-size/minimized source, multi-screen move, stale plan applied after abort - have no fixture coverage, so a bad plan ships as a lost or flickering window.

## reproducer
- repo: ohal/gorav @ 2112af0d60df16c5473173b664903f76ce54173e (branch ohal/gorav).
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
