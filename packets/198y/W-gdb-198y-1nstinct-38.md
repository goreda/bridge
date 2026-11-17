# W-gdb-198y-1nstinct-38
state: OPEN / unclaimed
lab: 1nstinct

Build a new independent scope-aware source/move characterization test for this exact file. Parse lexical nominal ownership including nesting, ignore comments/strings, and compare fully qualified declaration owners across the entire pinned Sources tree. Do not confuse nested names in unrelated owners with duplicates. Preserve pinned bytes. Check old and mapped station, renamed copies, valid overload/nested-name controls, and real duplicate mutants. Use explicit failure paths that remain active under python3 -O. Run normal and optimized positive plus on-disk external negative/restore controls. The existing 01..20 returns are evidence only and may not be copied unchanged.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-38.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-38",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/PanelFocus.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-38.py checks archive/gor/Sources/gor/PanelFocus.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: GORInputPanel, registerKeyOwnership, releaseKeyOwnership, logFocus, rememberFocus, firstEditable, restorePanelFocus, closeAllForQuit",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-38.py",
    "callee": "archive/gor/Sources/gor/PanelFocus.swift owning station GorPlatformMac"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-38.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-38.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-38.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:16.143103+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/PanelFocus.swift",
        "block": "source1",
        "sha256": "617b617586a9f12900bed807f162cd0000d86bd082fa06fa3754a91ffe3374a5"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-38.py",
        "block": "fixtures1",
        "sha256": "49ed93f0b3b537da41e32e3738fd2ac650423866250d09c25f0f0a79306c23d1"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "47b6689565db8b0561f80bc47b851ff6e6effecce85d4645885e3a07c4d21571",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-38: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "3b104b1c467118ce030c94ca79e99b9002b414aa06e3136c248fa4387adf55b5"
  }
}
```

```swift id=source1
import AppKit

/// One focus lifecycle for native gor panels. No activation polling or app-wide focus stealing.
/// A panel only claims activation on a click addressed to itself or an explicit open/refocus call.
class GORInputPanel: NSPanel {
    private weak var savedControl:NSView?
    private var savedSelection:NSRange?
    override var canBecomeKey:Bool {!NoActivate.active}
    override var canBecomeMain:Bool {false}
    var hasMarkedText:Bool {(firstResponder as? NSTextView)?.hasMarkedText() == true}
    // Key-window ownership: while this panel is open it owns the key window; automatic
    // player re-keys (activation recovery, overlay click, un-minimize) stand down.
    private func registerKeyOwnership() {PanelKeyOwnership.shared.register(ObjectIdentifier(self))}
    private func releaseKeyOwnership() {PanelKeyOwnership.shared.unregister(ObjectIdentifier(self))}
    override func makeKeyAndOrderFront(_ sender:Any?) {
        registerKeyOwnership()
        super.makeKeyAndOrderFront(sender)
        GORInputPanel.logFocus("open-assert",panel:self)
    }
    override func orderFront(_ sender:Any?) {registerKeyOwnership();super.orderFront(sender)}
    override func close() {releaseKeyOwnership();super.close()}
    override func orderOut(_ sender:Any?) {releaseKeyOwnership();super.orderOut(sender)}
    deinit {PanelKeyOwnership.shared.unregister(ObjectIdentifier(self))}
    /// Focus diagnostic: one line at open/key-gain/key-loss naming the key window and its
    /// first responder, so an owner capture shows who holds key and who took it.
    static func logFocus(_ phase:String,panel:NSWindow?) {
        let key=NSApp.keyWindow
        let keyDesc=key.map {"\(type(of:$0))"} ?? "none"
        let firstDesc=key?.firstResponder.map {"\(type(of:$0))"} ?? "none"
        let panelDesc=panel.map {"\(type(of:$0))"} ?? "none"
        print("[panel-focus] \(phase) panel=\(panelDesc) keyWindow=\(keyDesc) firstResponder=\(firstDesc)")
    }
    func rememberFocus(_ view:NSView) {if view.window === self {savedControl=view;savedSelection=nil}}
    private func firstEditable(in view:NSView)->NSTextField? {
        PanelFocusTraversal.first(in:view,children:{$0.subviews},visible:{!$0.isHidden && $0.alphaValue>0.01},accept:{
            guard let field=$0 as? NSTextField,field.isEditable,field.isEnabled else{return nil};return field
        })
    }
    func restorePanelFocus() {
        guard isVisible,isKeyWindow else{return}
        // Preserve the active field editor/IME and selection. A non-text control keeps focus too.
        if let responder=firstResponder as? NSView,responder !== contentView,
           responder.window === self {
            if responder is NSTextView {return}
            if responder is NSControl && !(responder is NSTextField) {return}
        }
        let target=(savedControl?.window === self ? savedControl:nil) ?? contentView.flatMap {firstEditable(in:$0)}
        guard let target else{return}
        if let field=target as? NSTextField,let editor=field.currentEditor(),firstResponder === editor{return}
        _=makeFirstResponder(target)
        if let field=target as? NSTextField,let editor=field.currentEditor() as? NSTextView,let range=savedSelection {
            let length=(field.stringValue as NSString).length
            editor.setSelectedRange(NSRange(location:min(range.location,length),length:min(range.length,max(0,length-min(range.location,length)))))
        }
    }
    override func resignKey() {
        if let editor=firstResponder as? NSTextView,let field=editor.delegate as? NSTextField {
            savedControl=field;savedSelection=editor.selectedRange()
        }
        else if let view=firstResponder as? NSView,view.window === self,view is NSControl {savedControl=view}
        super.resignKey()
        GORInputPanel.logFocus("resigned-key",panel:self)
        // The new key window is only settled a beat later; log it then to name any stealer.
        DispatchQueue.main.async {GORInputPanel.logFocus("post-loss",panel:nil)}
    }
    override func becomeKey() {registerKeyOwnership();super.becomeKey();restorePanelFocus();GORInputPanel.logFocus("became-key",panel:self)}
    override func sendEvent(_ event:NSEvent) {
        if event.type == .leftMouseDown,attachedSheet == nil,NSApp.modalWindow == nil {
            if !NSApp.isActive && !NoActivate.active {NSApp.activate(ignoringOtherApps:true)}
            if !isKeyWindow {makeKeyAndOrderFront(nil)}
            restorePanelFocus()
        }
        super.sendEvent(event)
    }
    /// Synchronous first quit beat. No editor validation, fades, network or child waits.
    static func closeAllForQuit() {
        for panel in NSApp.windows.compactMap({ $0 as? GORInputPanel }) {
            panel.orderOut(nil)
            panel.close()
        }
    }
    override func cancelOperation(_ sender:Any?) {performClose(sender)}
    override func keyDown(with event:NSEvent) {
        // Existing text delegates and panel monitors retain first refusal. This fallback is for
        // a panel with no editor/control owning Escape, and closes through its ordinary lifecycle.
        if event.keyCode==53 {cancelOperation(nil);return}
        super.keyDown(with:event)
    }
}

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/PanelFocus.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='617b617586a9f12900bed807f162cd0000d86bd082fa06fa3754a91ffe3374a5', 'pinned source changed: rebase and review, never bless silently'
for token in ['GORInputPanel', 'registerKeyOwnership', 'releaseKeyOwnership', 'logFocus', 'rememberFocus', 'firstEditable', 'restorePanelFocus', 'closeAllForQuit']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='617b617586a9f12900bed807f162cd0000d86bd082fa06fa3754a91ffe3374a5'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-38: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-38: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
