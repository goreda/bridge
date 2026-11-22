#!/usr/bin/env python3

# Platform source acquisition only; exact original units via the shared MARK resolver.
import importlib.util as _plat_iu
from pathlib import Path as _PlatPath
_plat_root=next(p for p in _PlatPath(__file__).resolve().parents if (p/'Tests/Structure/platform_source.py').is_file())
_plat_spec=_plat_iu.spec_from_file_location('platform_source_view',_plat_root/'Tests/Structure/platform_source.py')
_plat_view=_plat_iu.module_from_spec(_plat_spec);_plat_spec.loader.exec_module(_plat_view)
_plat_read=_plat_view.read_source
_plat_bytes=_plat_view.read_bytes
_plat_compile_input=_plat_view.compile_input
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
source=_plat_read(root/'Sources/gor/GorPlatformMac/PanelFocus.swift')
a=source.index('    func restorePanelFocus()');b=source.index('    override func becomeKey()',a)
methods=source[a:b].replace('override func resignKey()','func resignKey()').replace('        super.resignKey()','')
prefix='import Foundation\nenum GORInputPanel {static func logFocus(_ phase:String,panel:Panel?) {}}\nclass NSView {var window:Panel?;var isHidden=false;var alphaValue=1.0;var subviews:[NSView]=[]}\nclass NSControl:NSView {}\nclass NSTextView:NSView {var delegate:AnyObject?;var range=NSRange(location:0,length:0);func selectedRange()->NSRange {range};func setSelectedRange(_ r:NSRange){range=r}}\nclass NSTextField:NSControl {var isEditable=true;var isEnabled=true;var stringValue="hello";var editor:NSTextView?;func currentEditor()->NSTextView? {editor}}\nfinal class Panel {var savedControl:NSView?;var savedSelection:NSRange?;var isVisible=true;var isKeyWindow=true;var firstResponder:NSView?;var contentView:NSView?;var changes=0\nfunc firstEditable(in view:NSView)->NSTextField? {PanelFocusTraversal.first(in:view,children:{$0.subviews},visible:{!$0.isHidden},accept:{$0 as? NSTextField})}\nfunc makeFirstResponder(_ view:NSView)->Bool {changes+=1;firstResponder=view;return true}\n'
suffix='\nlet panel=Panel(),field=NSTextField(),root=NSView();field.window=panel;root.window=panel;root.subviews=[field];panel.contentView=root\npanel.restorePanelFocus();precondition(panel.firstResponder === field && panel.changes==1)\nlet editor=NSTextView();editor.window=panel;editor.delegate=field;editor.range=NSRange(location:2,length:2);field.editor=editor;panel.firstResponder=editor\npanel.restorePanelFocus();precondition(panel.changes==1 && editor.range.location==2)\npanel.resignKey();precondition(panel.savedControl === field && panel.savedSelection==editor.range)\nlet button=NSControl();button.window=panel;panel.firstResponder=button;panel.restorePanelFocus();precondition(panel.changes==1)\npanel.firstResponder=root;panel.isKeyWindow=false;panel.restorePanelFocus();precondition(panel.changes==1)\npanel.isKeyWindow=true;field.stringValue="a";panel.restorePanelFocus();precondition(panel.changes==2 && editor.range==NSRange(location:1,length:0))\nprint("PASS extracted production restore/resign lifecycle: editor/control preserved; inactive no-op; selection saved/clamped; AppKit native UNRUN")\n'
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'main.swift').write_text(prefix+methods+'}'+suffix)
 compiler=os.environ.get('SWIFTC','swiftc')
 subprocess.run([compiler,str(_plat_compile_input(root/'Sources/gor/GorPlatformMac/PanelFocusTraversal.swift')),str(p/'main.swift'),'-o',str(p/'check')],check=True)
 subprocess.run([str(p/'check')],check=True)
