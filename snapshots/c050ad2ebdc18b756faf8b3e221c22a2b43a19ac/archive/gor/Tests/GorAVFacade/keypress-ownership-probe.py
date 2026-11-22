#!/usr/bin/env python3
"""Runs the REAL GorAVHostWindow.holdKeyAdmitted on macOS. Exit 77 = NOT_RUN (no Darwin/swiftc); never a pass."""
import os, platform, shutil, subprocess, sys, tempfile
from pathlib import Path
R = Path(__file__).resolve().parents[2]
sw = os.environ.get('SWIFTC', 'swiftc')
if platform.system() != 'Darwin' or not shutil.which(sw):
    print('NOT_RUN: needs macOS swiftc'); sys.exit(77)
t = Path(tempfile.mkdtemp())
(t/'main.swift').write_text('''import AppKit
func a(_ k: UInt16,_ f: NSEvent.ModifierFlags,_ p: Bool)->Bool{GorAVHostWindow.holdKeyAdmitted(keyCode:k,flags:f,physicalFnDown:p)}
let sf: NSEvent.ModifierFlags=[.shift,.function]
var bad=[String]()
for k:UInt16 in [43,47,115,119,116,121]{ if !a(k,sf,false){bad.append("free \\(k)")} }
for k:UInt16 in [123,124,125,126]{ if a(k,sf,false){bad.append("arrow nofn \\(k)")}; if !a(k,sf,true){bad.append("arrow fn \\(k)")} }
for f in [NSEvent.ModifierFlags.command,.option,.control]{ if a(43,sf.union(f),true){bad.append("mod")} }
if a(43,[.function],true)||a(43,[.shift],true)||a(53,sf,true){bad.append("flags/key")}
if bad.isEmpty{print("PASS probe")}else{print("FAIL",bad);exit(1)}
''')
# GorAVHostWindow names DraggableOverlayWindow (defined in AppDelegate.swift). Minimal stub: only the factory
# call it references; the probe never constructs a host window.
(t/'Stub.swift').write_text('import AppKit\nfinal class DraggableOverlayWindow: NSWindow {\n    static func playerWindow(frame: NSRect) -> NSWindow { NSWindow(contentRect: frame, styleSheetPlaceholder) }\n}\n'.replace('styleSheetPlaceholder', 'styleMask: [.borderless], backing: .buffered, defer: true'))
r = subprocess.run([sw, str(R/'Sources/gor/Engine/GorAVHostMotion.swift'), str(R/'Sources/gor/Engine/GorAVHostWindow.swift'), str(t/'Stub.swift'), str(t/'main.swift'), '-framework', 'AppKit', '-o', str(t/'p')], capture_output=True, text=True)
if r.returncode: print(r.stderr[-800:]); sys.exit(1)
sys.exit(subprocess.run([str(t/'p')]).returncode)
