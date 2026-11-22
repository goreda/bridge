#!/usr/bin/env python3
"""Quiet normal playback policy. Runs exact production code, no AppKit claim."""
from pathlib import Path
import os, subprocess, tempfile
root=Path(__file__).resolve().parents[2]
source=root/'Sources/gor/Engine/MPVCommand.swift'
engine=source.read_text()
engine='import Foundation\n'+engine[engine.index('enum PlayerEngine:'):engine.index('/// mpv visibility flags')]
app=(root/'Sources/gor/App/AppDelegate.swift').read_text()
assert 'showEngineRoute(engineRouteStatus.line)' not in app
assert 'guard let osd=engineRouteStatus.osdLine() else {return}' in app
assert 'print("[engine] \\(line)");Diag.mediaRecord(line)' in app
main='''import Foundation
for requested in PlayerEngine.allCases {
 for active in PlayerEngine.allCases {
  let normal=PlayerRouteStatus(requested:requested,active:active,fallbackReason:nil)
  precondition(normal.osdLine(environment:[:]) == nil)
  precondition(normal.osdLine(environment:["GOR_DEBUG_ENGINE_OSD":"0"]) == nil)
  precondition(normal.osdLine(environment:["GOR_DEBUG_ENGINE_OSD":"true"]) == nil)
  precondition(normal.osdLine(environment:["GOR_DEBUG_ENGINE_OSD":"1"]) == normal.line)
 }
}
let refused=PlayerRouteStatus(requested:.gorav,active:.mpv,fallbackReason:"ffprobe unavailable")
precondition(refused.osdLine(environment:[:]) == "gorav: ffprobe unavailable -> mpv")
precondition(refused.osdLine(environment:["GOR_DEBUG_ENGINE_OSD":"1"]) == refused.line)
precondition(PlayerRouteStatus(requested:.gorav,active:.mpv,fallbackReason:"").osdLine(environment:[:]) == nil)
print("PASS quiet normal route, explicit-debug-only diagnostics, actual refusal retained")
'''
variants=[('fixed',engine),
 ('mutant-always-debug',engine.replace('environment["GOR_DEBUG_ENGINE_OSD"] == "1"','true')),
 ('mutant-hide-reason',engine.replace('return "gorav: \\(reason) -> mpv"','return nil')),
 ('mutant-no-debug',engine.replace('environment["GOR_DEBUG_ENGINE_OSD"] == "1"','false'))]
assert len({v for _,v in variants})==4
if '--wiring-only' in __import__('sys').argv:
 print('PASS controller setup/wake central policy, diagnostics preserved, four distinct exact-source variants prepared; Swift NOT_RUN')
 raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix='engine-osd-') as td:
 t=Path(td);(t/'main.swift').write_text(main)
 for label,code in variants:
  (t/'Engine.swift').write_text(code)
  for mode in ['-Onone','-O']:
   subprocess.run([os.environ.get('SWIFTC','swiftc'),mode,str(t/'Engine.swift'),str(t/'main.swift'),'-o',str(t/'probe')],check=True)
   p=subprocess.run([str(t/'probe')],capture_output=True,text=True)
   assert (p.returncode==0)==(label=='fixed'),(label,mode,p.stdout,p.stderr)
   print(label,mode,'GREEN' if p.returncode==0 else 'RED')
print('NOT_RUN AppKit pixels and owner Mac playback')
