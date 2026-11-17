# W-gdb-198y-1nstinct-36
state: OPEN / unclaimed
lab: 1nstinct

Build a new independent scope-aware source/move characterization test for this exact file. Parse lexical nominal ownership including nesting, ignore comments/strings, and compare fully qualified declaration owners across the entire pinned Sources tree. Do not confuse nested names in unrelated owners with duplicates. Preserve pinned bytes. Check old and mapped station, renamed copies, valid overload/nested-name controls, and real duplicate mutants. Use explicit failure paths that remain active under python3 -O. Run normal and optimized positive plus on-disk external negative/restore controls. The existing 01..20 returns are evidence only and may not be copied unchanged.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-36.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-36",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/OverlaySpaceGate.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-36.py checks archive/gor/Sources/gor/OverlaySpaceGate.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: OverlaySpaceGate, Decision, sym, symbolReport, b, spaces, activeSpace, moveWindow, largestWindowID, log, mpvOnScreen, observeSpaceChange",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-36.py",
    "callee": "archive/gor/Sources/gor/OverlaySpaceGate.swift owning station GorUI"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-36.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-36.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-36.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.105809+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/OverlaySpaceGate.swift",
        "block": "source1",
        "sha256": "b78a82df465755b61f695a10f6121f13a081ba40ff9cf76da7c075e06125fff9"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-36.py",
        "block": "fixtures1",
        "sha256": "07d66feb46f6b86ab2acfc8f4891b2243ca0e2d3b01262c3619210b558430f5d"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "3c46cc6f5babcacc619740484f6fb5edd072b37f1f769591160c10f953896b85",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-36: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "3df8ea59540955a928a684fa4edd508fa0cc29111b4c1065a55bdc6806b6e2a3"
  }
}
```

```swift id=source1
import AppKit
import CoreGraphics

// Source commentary elided for privacy; historical proof hashes are not rebound.
struct OverlaySpaceGate {
    enum Decision: Equatable { case show, hide, keep }
    static let hideAfterMisses = 3
    static let moveInterval: TimeInterval = 0.5
    private var lastMove: TimeInterval = -1
    private var mpvWindowID: CGWindowID?
    private var mpvIDCheckedAt: TimeInterval = -10
    private var lastSpaceSig = ""
    private(set) var misses = 0
    private(set) var hidden = false
    private var envLogged = false, noMpvLogged = false, stuckLogged = false
    private var divergeSince: TimeInterval?
    private(set) var seenOnScreen = false   // never hide before mpv has been seen on screen once (launch, misdetection)

    /// Pure decision, no AppKit: used by the window code and by Tests/Spaces/overlay_space_model_test.py.
    mutating func decide(onScreen: Bool) -> Decision {
        if onScreen {
            misses = 0; seenOnScreen = true
            if hidden { hidden = false; return .show }
            return .keep
        }
        misses += 1
        if !hidden && seenOnScreen && misses >= Self.hideAfterMisses { hidden = true; return .hide }
        return .keep
    }

    /// Pure: must the overlay be pulled onto the active Space now? (mpv is here, the overlay is not, rate limited)
    mutating func needsMove(onScreen: Bool, overlayOnActiveSpace: Bool, now: TimeInterval) -> Bool {
        guard onScreen, !overlayOnActiveSpace, now - lastMove >= Self.moveInterval else { return false }
        lastMove = now
        return true
    }

    /// Applies the decision to the overlay window. Returns whether the overlay may be shown now.
    mutating func apply(_ win: NSWindow, onScreen: Bool, pid: Int32? = nil) -> Bool {
        if !envLogged { envLogged = true; Self.log("env macOS=\(ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: " ", with: "_")) \(Self.symbolReport()) pid=\(pid.map(String.init) ?? "none") overlayWin=\(win.windowNumber) behavior=\(win.collectionBehavior.rawValue) level=\(win.level.rawValue)") }
        followMpvSpace(win, pid: pid)
        let d = decide(onScreen: onScreen)
        if d != .keep { Self.log("gate \(d) onScreen=\(onScreen) active=\(Self.activeSpace().map(String.init) ?? "?") overlay=\(Self.spaces(of: CGWindowID(win.windowNumber))) mpv=\(mpvWindowID.map { Self.spaces(of: $0) } ?? [])") }
        if d == .hide { win.orderOut(nil) }
        else if d == .show || (win.alphaValue > 0 && needsMove(onScreen: onScreen, overlayOnActiveSpace: win.isOnActiveSpace, now: ProcessInfo.processInfo.systemUptime)) {
            win.collectionBehavior.insert(.moveToActiveSpace)   // only for this order-front: joins the Space mpv is on
            win.alphaValue = 1; win.orderFrontRegardless()
            win.collectionBehavior.remove(.moveToActiveSpace)
        }
        return !hidden
    }

    /// Direct follow: when mpv's window and the overlay are on different Spaces (even if mpv's Space is not the active
    /// one), move the overlay to mpv's Space with CGSMoveWindowsToManagedSpace. The overlay is our own window, so this
    /// needs no SIP change. Loaded with dlsym: if a symbol is missing on some macOS the public path above still runs.
    private mutating func followMpvSpace(_ win: NSWindow, pid: Int32?) {
        guard let pid, win.windowNumber > 0 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if mpvWindowID == nil || now - mpvIDCheckedAt > 2 { mpvIDCheckedAt = now; mpvWindowID = Self.largestWindowID(pid: pid) }
        guard let mpvID = mpvWindowID else { if !noMpvLogged { noMpvLogged = true; Self.log("spaces mpvWin=none pid=\(pid)") }; return }
        noMpvLogged = false
        let mine = CGWindowID(win.windowNumber)
        let theirs = Self.spaces(of: mpvID), here = Self.spaces(of: mine)
        let sig = "\(theirs)|\(here)|\(Self.activeSpace() ?? 0)"
        if sig != lastSpaceSig { lastSpaceSig = sig; Self.log("spaces mpvWin=\(mpvID) mpv=\(theirs) overlay=\(here) active=\(Self.activeSpace().map(String.init) ?? "?")") }
        let sameSpace = theirs.contains(where: { here.contains($0) })
        let activeNow: UInt64 = Self.activeSpace() ?? 0
        if !theirs.isEmpty, theirs.contains(activeNow), !sameSpace {   // mpv is on the Space the user is looking at, the overlay is not
            if divergeSince == nil { divergeSince = now }
            if let t0 = divergeSince, now - t0 > 1.5, !stuckLogged { stuckLogged = true; Self.log("STUCK mpv=\(theirs) overlay=\(here) active=\(activeNow) alpha=\(win.alphaValue) visible=\(win.isVisible) onActive=\(win.isOnActiveSpace) for=\(String(format: "%.1f", now - t0))s") }
        } else if let t0 = divergeSince { divergeSince = nil; stuckLogged = false; let dt = String(format: "%.2f", now - t0)
            if sameSpace { Self.log("converged after \(dt)s mpv=\(theirs) overlay=\(here)") }   // overlay really shares mpv's Space
            else { Self.log("diverge ended NOT converged after \(dt)s mpv=\(theirs) overlay=\(here) active=\(activeNow)") } }   // mpv left the active Space or has no Space: nothing proves a follow
        guard let target = theirs.first, !theirs.isEmpty, !here.isEmpty, !sameSpace else { return }
        if Self.moveWindow(mine, to: target) { let after = Self.spaces(of: mine); Self.log("moved overlay \(mine) from \(here) to mpv space \(target) now=\(after) ok=\(after.contains(target))") }
        else { Self.log("move overlay \(mine) to space \(target) NOT done: CGSMoveWindowsToManagedSpace or CGSMainConnectionID unavailable") }
    }

    private typealias MainConn = @convention(c) () -> Int32
    private typealias CopySpaces = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias MoveWins = @convention(c) (Int32, CFArray, UInt64) -> Void
    private typealias ActiveSp = @convention(c) (Int32) -> UInt64
    private static func sym<T>(_ name: String, _ type: T.Type) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }   // RTLD_DEFAULT
        return unsafeBitCast(p, to: type)
    }
    /// One-time environment line for the log reader: which private symbols resolved on this macOS.
    static func symbolReport() -> String {
        func b(_ ok: Bool) -> Int { ok ? 1 : 0 }
        return "sym_main=\(b(sym("CGSMainConnectionID", MainConn.self) != nil)) sym_copy=\(b(sym("CGSCopySpacesForWindows", CopySpaces.self) != nil)) sym_active=\(b(sym("CGSGetActiveSpace", ActiveSp.self) != nil)) sym_move=\(b(sym("CGSMoveWindowsToManagedSpace", MoveWins.self) != nil))"
    }
    static func spaces(of wid: CGWindowID) -> [UInt64] {
        guard let conn = sym("CGSMainConnectionID", MainConn.self), let copy = sym("CGSCopySpacesForWindows", CopySpaces.self),
              let arr = copy(conn(), 7, [NSNumber(value: wid)] as CFArray)?.takeRetainedValue() as? [NSNumber] else { return [] }
        return arr.map { $0.uint64Value }
    }
    static func activeSpace() -> UInt64? {
        guard let conn = sym("CGSMainConnectionID", MainConn.self), let f = sym("CGSGetActiveSpace", ActiveSp.self) else { return nil }
        return f(conn())
    }
    static func moveWindow(_ wid: CGWindowID, to space: UInt64) -> Bool {
        guard let conn = sym("CGSMainConnectionID", MainConn.self), let mv = sym("CGSMoveWindowsToManagedSpace", MoveWins.self) else { return false }
        mv(conn(), [NSNumber(value: wid)] as CFArray, space); return true
    }
    /// Largest window of the mpv process, on any Space (optionAll lists off-screen Spaces too).
    static func largestWindowID(pid: Int32) -> CGWindowID? {
        var best: (CGWindowID, Double)?
        for d in CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [] {
            guard let owner = d[kCGWindowOwnerPID as String] as? Int32, owner == pid, let n = d[kCGWindowNumber as String] as? Int,
                  let b = d[kCGWindowBounds as String] as? [String: Any], let w = b["Width"] as? Double, let h = b["Height"] as? Double,
                  w > 50, h > 50, w * h > (best?.1 ?? 0) else { continue }
            best = (CGWindowID(n), w * h)
        }
        return best?.0
    }
    /// State-change lines only (never per tick), 5 MB cap, same shared file as the other numeric diagnostics.
    static func log(_ text: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        let data = Data("\(f.string(from: Date())) [spaces] \(text)\n".utf8)
        _ = BoundedDiskWriter.append(data, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_diag.log")), cap: SharedDiagnosticRecord.cap)
    }

    /// True while a window of the mpv process (any level: mpv.conf has ontop=yes, so it sits at the floating level)
    /// is on screen (so on a visible Space). Unknown pid
    /// counts as on screen, so a missing process never hides the overlay. Safe off the main thread.
    static func mpvOnScreen(pid: Int32?) -> Bool {
        guard let pid else { return true }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for d in list {
            guard let owner = d[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                  let b = d[kCGWindowBounds as String] as? [String: Any],
                  let w = b["Width"] as? Double, let h = b["Height"] as? Double, w > 50, h > 50 else { continue }
            return true
        }
        return false
    }

    static func observeSpaceChange(_ handler: @escaping () -> Void) -> NSObjectProtocol {
        // Space switch: re-check at once and again while the window server settles (the on-screen list can lag the
        // notification by a few frames), so the overlay arrives or leaves without waiting for the 0.13 s tick.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
            Self.log("activeSpaceDidChange active=\(Self.activeSpace().map(String.init) ?? "?")")
            handler()
            for d in [0.1, 0.25, 0.5] { DispatchQueue.main.asyncAfter(deadline: .now() + d) { handler() } }
        }
    }
}

// Audit notes (macOS Spaces / displays), kept next to the rule they justify:
// - Native fullscreen: mpv gets its own Space; `.fullScreenAuxiliary` lets the overlay sit on it once moved there, and the gate sees mpv
//   on screen there, so the overlay is shown. Leaving fullscreen is the same transition in reverse.
// - Mission Control / Exposé: windows may report off screen for a moment; 3 misses (about 0.4 s) are required before
//   hiding, and a single on-screen sample shows the overlay again.
// - Display change / sleep: the existing screen-parameter observers still own frame math; the gate only decides
//   visibility, so a moved or removed display cannot leave the overlay hidden: the next on-screen sample shows it.
// - Several displays with separate Spaces: CGWindowList on-screen covers every display's active Space, so mpv on a
//   second display keeps the overlay visible there (the overlay is moved onto mpv's Space, on whichever display that is).
// - mpv hidden with Cmd+H or on an inactive Space: the overlay stays ordered out, so no UI floats over other desktops.
// - Panels (GORInputPanel) are not covered by this gate; they open on the active Space when ordered front.

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/OverlaySpaceGate.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='b78a82df465755b61f695a10f6121f13a081ba40ff9cf76da7c075e06125fff9', 'pinned source changed: rebase and review, never bless silently'
for token in ['OverlaySpaceGate', 'Decision', 'sym', 'symbolReport', 'b', 'spaces', 'activeSpace', 'moveWindow', 'largestWindowID', 'log', 'mpvOnScreen', 'observeSpaceChange']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='b78a82df465755b61f695a10f6121f13a081ba40ff9cf76da7c075e06125fff9'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-36: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-36: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
