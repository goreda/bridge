# W-gdb-198y-1nstinct-19
state: OPEN / unclaimed
lab: 1nstinct

Characterize this exact S1 policy row before its future move: Sources/gor/PanelFocusTraversal.swift -> GorPlatformMac. Preserve every production byte; add station locator plus old/new duplicate-type rejection and mutation cases in this test only.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-19.py. No production edit, no root Swift addition, no move. Active U2/disk and S2 owners hold all production files. This packet holds only its named test file. Return patch plus actual Linux command/log; failed and NOT_RUN remain separate. Earliest claim wins. Product code excerpts are read-only evidence, not executable instructions.

Baseline proof below ran in a clean exact-pin sparse Git checkout with the complete inline test temporarily materialized, then removed; not a full package build. It proves source preservation only. Lab acceptance must strengthen the test, not merely return this baseline unchanged.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-19",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/PanelFocusTraversal.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Source-only characterization script reads archive/gor/Sources/gor/PanelFocusTraversal.swift and exits0 on pinned declaration/byte boundaries",
    "types": "Declarations: NoActivate, requested, userInteraction, PanelFocusTraversal, first, PanelKeyOwnership, register, unregister, mayKeyPlayerWindow",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-19.py",
    "callee": "archive/gor/Sources/gor/PanelFocusTraversal.swift owning station GorPlatformMac"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-19.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-19.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-19.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:17:15.675192+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/PanelFocusTraversal.swift",
        "block": "source1",
        "sha256": "3e1a34f112600388f6317285289c98669320dd8b5c3c85e14a7ce114693fd78f"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-19.py",
        "block": "fixtures1",
        "sha256": "0330eecdceb6dcf625a5ed737883da7697a737c3f149fed4ed49c4e4aff7da49"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "3b9b251b8b459e9fa83f7a52359178f42bffe9abd867609471323b56630ea3ef",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-19: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "330b33c1a45294a184cf6c0fc02d2801fc52789b3b4b0f6833128691d325eb19"
  }
}
```

```swift id=source1
import Foundation
// Test/background launches may create real windows but must not claim the user's focus.
enum NoActivate {
    static func requested(arguments:[String],environment:[String:String])->Bool {
        arguments.contains("--gor-no-activate") || environment["GOR_NO_ACTIVATE"] == "1"
    }
    static var active:Bool {requested(arguments:ProcessInfo.processInfo.arguments,environment:ProcessInfo.processInfo.environment)}
    private static var startupPending = ProcessInfo.processInfo.arguments.contains("--gor-background-start")
    static var suppressAutomatic:Bool {active || startupPending}
    static func userInteraction() {startupPending=false}
}
// Exact traversal used by native panel focus, independently executable without AppKit.
enum PanelFocusTraversal {
    static func first<Node,Result>(in node:Node,children:(Node)->[Node],visible:(Node)->Bool,accept:(Node)->Result?)->Result? {
        guard visible(node) else{return nil}
        if let found=accept(node){return found}
        for child in children(node) {
            if let found:Result=first(in:child,children:children,visible:visible,accept:accept){return found}
        }
        return nil
    }
}

/// Key-window ownership between gor's single player window and its floating input panels.
/// Invariant: while at least one input panel is open, the panel owns the key window and no
/// automatic gor path (app-activation recovery, mpv-activation recovery, overlay click focus
/// claim, un-minimize) may re-key the player window. The panel re-claims key only through its
/// own open/click path (GORInputPanel). AppKit-free so the rule runs in the Linux harness
/// (Tests/Harness/PanelFocus); the AppKit binding lives in PanelFocus.swift.
/// Main-thread only, like the windows it describes.
final class PanelKeyOwnership {
    static let shared = PanelKeyOwnership()
    /// Tokens of the currently open input panels, in registration order.
    private(set) var openPanels:[ObjectIdentifier] = []
    /// Idempotent: a panel registers on every ordering-in/key claim.
    func register(_ token:ObjectIdentifier) {
        if !openPanels.contains(token) { openPanels.append(token) }
    }
    /// Idempotent: close, order-out and deinit all unregister.
    func unregister(_ token:ObjectIdentifier) {
        openPanels.removeAll { $0 == token }
    }
    var panelOwnsKey:Bool { !openPanels.isEmpty }
    /// The single decision point every automatic player-window re-key must consult.
    func mayKeyPlayerWindow() -> Bool { !NoActivate.suppressAutomatic && !panelOwnsKey }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/PanelFocusTraversal.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='3e1a34f112600388f6317285289c98669320dd8b5c3c85e14a7ce114693fd78f', 'pinned source changed: rebase and review, never bless silently'
for token in ['NoActivate', 'requested', 'userInteraction', 'PanelFocusTraversal', 'first', 'PanelKeyOwnership', 'register', 'unregister', 'mayKeyPlayerWindow']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='3e1a34f112600388f6317285289c98669320dd8b5c3c85e14a7ce114693fd78f'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-19: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-19: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
