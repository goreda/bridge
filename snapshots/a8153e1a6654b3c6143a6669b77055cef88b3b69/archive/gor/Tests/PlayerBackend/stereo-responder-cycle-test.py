#!/usr/bin/env python3
"""Actual stereo input class + actual RowSnap mouseDown through native AppKit.
Baseline loops are bounded by the fixture before stack exhaustion. No pixel claim.
"""
import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
from pathlib import Path
import os,subprocess,tempfile,sys
r=Path(__file__).resolve().parents[2]
s=(_pp_split().path(r,'PPController.swift')).read_text()
a=s.index('final class VRStereoControlInput:');b=s.index('/// Opt-in geometry trace',a);fixed=s[a:b]
f=(r/'Sources/gor/Media/FileBrowser.swift').read_text();a=f.index('class RowSnapScrollView');a=f.index('    override func mouseDown(with event: NSEvent)',a);b=f.index('\n    override func mouseDragged',a);row=f[a:b]
guard='''        guard !forwardingEvent else {return}
        forwardingEvent = true
        defer {forwardingEvent = false}
'''
assert fixed.count(guard)==4
variants=[('fixed',fixed),('baseline-no-guards',fixed.replace(guard,'')),('mutant-down-only-missing',fixed.replace(guard,'',1)),('mutant-stuck-guard',fixed.replace('defer {forwardingEvent = false}','defer {}'))]
if '--wiring-only' in sys.argv:
 print('PASS four event guards precede interaction/forwarding; exact input and RowSnap methods bound; native AppKit NOT_RUN')
 raise SystemExit(0)
main='''
final class Controller {func ipcCommand(_ s:String) {}}
final class AppDelegate:NSObject,NSApplicationDelegate {var controller:Controller?}
final class RowSnapScrollView:NSScrollView {
 override func hitTest(_ point:NSPoint)->NSView? {self}
 ROW_METHOD
}
let app=NSApplication.shared
let window=NSWindow(contentRect:NSRect(x:0,y:0,width:320,height:240),styleMask:[.borderless],backing:.buffered,defer:false)
let host=NSView(frame:NSRect(x:0,y:0,width:320,height:240));window.contentView=host
let input=VRStereoControlInput(frame:host.bounds)
let scroll=RowSnapScrollView(frame:NSRect(x:0,y:0,width:200,height:200))
host.addSubview(scroll);host.addSubview(input)
input.host=host;input.sources=[scroll];input.active=true
scroll.nextResponder=input
var interactions=0
input.onInteraction={ interactions += 1; if interactions>8 {exit(42)} }
let event=NSEvent.mouseEvent(with:.leftMouseDown,location:NSPoint(x:30,y:30),modifierFlags:[],timestamp:1,windowNumber:window.windowNumber,context:nil,eventNumber:1,clickCount:1,pressure:1)!
input.mouseDown(with:event)
precondition(interactions==1,"one source delivery only")
input.mouseDown(with:event)
precondition(interactions==2,"guard resets for next real click")
print("PASS native AppKit responder cycle bounded; next independent click preserved")
'''.replace('ROW_METHOD',row)
with tempfile.TemporaryDirectory(prefix='stereo-responder-') as td:
 t=Path(td)
 for label,code in variants:
  (t/'main.swift').write_text('import AppKit\n'+code+'\n'+main)
  for mode in ['-Onone','-O']:
   p=subprocess.run([os.environ.get('SWIFTC','swiftc'),mode,str(t/'main.swift'),'-framework','AppKit','-o',str(t/'probe')],capture_output=True,text=True)
   assert p.returncode==0,(label,mode,p.stderr)
   p=subprocess.run([str(t/'probe')],capture_output=True,text=True,timeout=15)
   assert (p.returncode==0)==(label=='fixed'),(label,mode,p.returncode,p.stdout,p.stderr)
   if label in ['baseline-no-guards','mutant-down-only-missing']:assert p.returncode==42,(label,'did not hit actual responder loop',p.returncode,p.stderr)
   print(label,mode,'GREEN' if p.returncode==0 else 'RED',p.returncode)
print('NOT_RUN owner Mac interactive playback or pixels')
