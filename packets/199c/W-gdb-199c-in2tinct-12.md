# W-gdb-199c-in2tinct-12 - Reject nonfinite PiP bounds
state: OPEN / unclaimed
lab: in2tinct

## Product change
PipSize.fit must refuse NaN/infinite maximum dimensions and any nonfinite or rounded-to-zero result using degenerateContentSize. Retain current three-decimal rounding and all normal mode transitions.

## Grounded gap and boundary
U2 fullscreen/PiP native-check prerequisite. Source inspection at the exact pin below exposes the condition covered by the starter test. This is a prerequisite defect fix only. It does not implement normal U2 menus, native wiring, rendering or runtime parity.

Exactly one production source file may change. Own test paths below are allowed. All other inline source files are READ-ONLY compile inputs, not edit authority. Do not touch Package.swift, existing test consumers, U2 host writers, lane-b overlays, existing lab A leases, or root fixtures/kits cleanup sources. No product/delivery ref changes. Return patch, exact compiler version, test argv/output and a source-change summary for coordinator review.

## PATH-CONTRACT
Top-level fixtures belong at Tests/Fixtures and kits at archive/kits. This packet moves neither directory. Preserve nested test and kit-local fixtures. Tests use temporary data only. No root fixture path replacement is requested.

## Reviewed test argv
`python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-12.py`

Set SWIFTC only if swiftc is not on PATH. Run from an exact-pin materialization with all inline source/test files at their declared paths. The test compiles the actual production source, not a Python model. A missing compiler is NOT_RUN (77), not PASS. The provided starter result is BASELINE_DEFECT_REPRODUCED, exit 1; acceptance requires exit0 after a meaningful production change. No Mac/native/UI/runtime result is claimed. For lab A, b603 is the supplied isolated S2 candidate base, not a claim that it is published on delivery.

```packet-json
{
  "packet_id": "W-gdb-199c-in2tinct-12",
  "lab": "in2tinct",
  "writer": "in2tinct",
  "code_owner": "Claiming lab owns only the one listed production source and its own test paths. Integrator owns shared wiring and composition.",
  "product_repo": "goreda/gorav",
  "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
  "touched_files": [
    {
      "path": "Sources/GorAVPlaybackCore/WindowModePlan.swift",
      "excerpt_block": "source1"
    }
  ],
  "scope": "product",
  "classification": "U2/S2 prerequisite defect fix, not U2 parity",
  "interface": {
    "signatures": "PipSize.fit must refuse NaN/infinite maximum dimensions and any nonfinite or rounded-to-zero result using degenerateContentSize. Retain current three-decimal rounding and all normal mode transitions.",
    "types": "Preserve existing public API except the explicitly additive SRT limits API. Read-only dependencies are not leases.",
    "ownership_lifetime": "One production source per packet. Existing 198z source leases remain untouched. Coordinator resolves claims and expiry.",
    "caller": "U2 fullscreen/PiP native-check prerequisite",
    "callee": "Sources/GorAVPlaybackCore/WindowModePlan.swift"
  },
  "test": {
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-12.py",
    "expected": "After production fix: compile_exit=0, semantic_exit=0, all checks PASS. Extend these tests with the stated edge cases. Starter is deliberately RED and is not product acceptance.",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2"
  },
  "target": {
    "branch": "lane/lab-in2tinct-W-gdb-199c-in2tinct-12",
    "paths": [
      "Sources/GorAVPlaybackCore/WindowModePlan.swift",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-12.py",
      "Tests/Architecture/199c/W-gdb-199c-in2tinct-12.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "cf3e3f1772033dbc8465b19689e93f53c60006ce",
    "command": "python3 Tests/Architecture/199c/W-gdb-199c-in2tinct-12.py",
    "system": "Linux Swift 6.0.3",
    "clean_checkout": false,
    "kind": "semantic-red-starter",
    "expected_exit": 1,
    "exit_code": 1,
    "ran_at": "2026-11-18T00:13:46.486083+00:00",
    "expected_log_contains": "compile_exit=0",
    "log_block": "actual_run_log",
    "log_sha256": "0a4b52e51c22b1132eb31bb41ea6a1fb5e4c488e591cb9f73fe7453c885ce339",
    "last_5_lines": [
      "PASS normal fit",
      "FAIL rounded zero refused",
      "semantic failures=3",
      "",
      ""
    ],
    "inline_files": [
      {
        "path": "Sources/GorAVPlaybackCore/WindowModePlan.swift",
        "block": "source1",
        "sha256": "cce8e9b8ce7bbb69d68d1bd4e93c918f78b72e7d4b4ec98e7cc345a6a4d6763b",
        "read_only_dependency": false
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-12.py",
        "block": "fixtures1",
        "sha256": "e03d358b27bdbfa400e7bd95e500b213ee6b06958a804bc46767d841bd95d8b0"
      },
      {
        "path": "Tests/Architecture/199c/W-gdb-199c-in2tinct-12.json",
        "block": "fixtures2",
        "sha256": "00f1ccb458fc9566b063ef472186e46a104be2d08addbb5a008bf86c09ddfdca"
      }
    ],
    "receipt_sha256": "222e621271328a697aa916b618d31a4e9b663c55f184c55d9ad661ed1e54ed68"
  },
  "starter_status": "BASELINE_DEFECT_REPRODUCED"
}
```

```swift id=source1
// R8/G3 lane note: this file is the G3 (arch-195l, dispatch L6) pure-Swift
// core. "G3 fullscreen/pip on gorav": the gorav host window owns its own
// mode transitions (PLAN.md P28: gor owns the window and its motion; PLAN.md
// line 51: window fit spring, fullscreen, pip, ontop -> G3). This type is
// platform-free and Linux-tested; the AppKit application of a decision lives
// in GorAVMacShell.WindowModeController (Darwin-only).

/// Host window frame in screen points. Platform-free twin of CGRect so the
/// policy compiles and tests on Linux.
public struct WindowFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The three modes the gorav host window supports in the 195l scope.
/// ontop stays outside this item (listed under G3 window in PLAN line 51 but
/// not in the L6 dispatch text "fullscreen/pip").
public enum WindowMode: String, Equatable, Sendable, CaseIterable {
    case windowed
    case fullscreen
    case pictureInPicture
}

public enum WindowModeRefusal: Error, Equatable, Sendable {
    /// Already in the requested mode; the transition is a no-op, not an
    /// error of intent, but it is reported, never silently swallowed.
    case alreadyInMode(WindowMode)
    /// fullscreen <-> pictureInPicture is refused directly: exiting
    /// fullscreen animates and re-anchors the window, so a direct hop would
    /// move pixels the caller did not ask for. Exit to .windowed first.
    case requiresWindowedFirst(from: WindowMode, to: WindowMode)
    /// A restore was requested with no recorded windowed frame.
    case noRestoreFrame
    /// PiP sizing got a degenerate or non-finite content size or invalid
    /// bounds; no size is guessed.
    case degenerateContentSize
}

public enum WindowModeDecision: Equatable, Sendable {
    /// Enter fullscreen. The windowed frame must be captured by the caller
    /// before applying (AppKit re-anchors the window on enter).
    case enterFullscreen(saveRestore: WindowFrame)
    /// Leave fullscreen back to the recorded windowed frame.
    case exitFullscreen(restore: WindowFrame?)
    /// Enter PiP: the content view moves into a borderless floating
    /// always-on-top window of this size; the windowed frame is kept for
    /// exit. PiP windows are never resizable by the user in this item.
    case enterPiP(pipFrameSize: PipSize, saveRestore: WindowFrame)
    /// Leave PiP: the content view moves back into the main window, restored
    /// to the recorded frame.
    case exitPiP(restore: WindowFrame?)
}

/// Aspect-preserving PiP window size. The PiP window fits the video aspect
/// inside a bounded box; it never letterboxes inside the PiP window itself
/// (the presenter letterboxes inside the view as it already does).
public struct PipSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// Default bounds for the PiP window: at most 480x270 (a quarter of a
    /// 1920x1080 frame). Portrait content gets a narrow window; there is no
    /// minimum-width bump, because any bump either overflows the box or is
    /// unreachable under max-bounds scaling - narrow is honest, guessed is
    /// not.
    public static let defaultMaxWidth = 480.0
    public static let defaultMaxHeight = 270.0

    /// Aspect-preserving fit of a content size inside the max box.
    /// Degenerate or non-finite content sizes are a typed refusal, never a
    /// guessed size.
    public static func fit(contentWidth: Double, contentHeight: Double,
                           maxWidth: Double = defaultMaxWidth,
                           maxHeight: Double = defaultMaxHeight) -> Result<PipSize, WindowModeRefusal> {
        guard contentWidth.isFinite, contentHeight.isFinite,
              contentWidth > 0, contentHeight > 0,
              maxWidth > 0, maxHeight > 0 else {
            return .failure(.degenerateContentSize)
        }
        let scale = min(maxWidth / contentWidth, maxHeight / contentHeight)
        let w = contentWidth * scale
        let h = contentHeight * scale
        return .success(PipSize(width: (w * 1000).rounded() / 1000,
                                height: (h * 1000).rounded() / 1000))
    }
}

/// Window-mode state machine. Value type: the shell holds one per host
/// window and applies the returned decision to AppKit.
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
    }
}

```

```python id=fixtures1
from pathlib import Path
import os,subprocess,tempfile,sys,json,resource,shutil
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[3]
CFG=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:
 print('NOT_RUN: Swift compiler unavailable'); sys.exit(77)
with tempfile.TemporaryDirectory() as d:
 d=Path(d); main=d/'main.swift'; main.write_text(CFG['test_source']); exe=d/'test'
 args=[swift]+[str(ROOT/p) for p in CFG['sources']]+[str(main),'-o',str(exe)]
 c=subprocess.run(args,capture_output=True,text=True,timeout=90)
 print('compile_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 if c.returncode: sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=15)
 print('semantic_exit='+str(c.returncode)); print(c.stdout); print(c.stderr)
 sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "sources": [
    "Sources/GorAVPlaybackCore/WindowModePlan.swift"
  ],
  "test_source": "import Foundation\n\nvar failures=0\nfunc check(_ ok: Bool,_ name: String) { print((ok ? \"PASS \" : \"FAIL \")+name); if !ok { failures += 1 } }\nfor x in [Double.infinity, -Double.infinity, Double.nan] {\n if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: 16, contentHeight: 9, maxWidth: x, maxHeight: 270) {} else { check(false,\"invalid width refused\") }\n if case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: 16, contentHeight: 9, maxWidth: 480, maxHeight: x) {} else { check(false,\"invalid height refused\") }\n}\nif case .success(let s) = PipSize.fit(contentWidth: 1920, contentHeight: 1080) { check(s.width == 480 && s.height == 270,\"normal fit\") } else { check(false,\"normal fit\") }\nif case .failure(.degenerateContentSize) = PipSize.fit(contentWidth: 1e308, contentHeight: 1, maxWidth: 480, maxHeight: 270) {} else { check(false,\"rounded zero refused\") }\nprint(\"semantic failures=\\(failures)\")\nexit(failures == 0 ? 0 : 1)\n"
}

```

```text id=actual_run_log
compile_exit=0


semantic_exit=1
FAIL invalid width refused
FAIL invalid height refused
PASS normal fit
FAIL rounded zero refused
semantic failures=3



```

Claim lease:2h under the existing earliest-claim workflow, refreshed by verified writer progress. This packet is OPEN/unclaimed; no write authority outside its listed source/test paths.
