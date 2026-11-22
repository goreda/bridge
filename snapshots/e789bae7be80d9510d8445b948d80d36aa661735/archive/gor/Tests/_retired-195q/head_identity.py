#!/usr/bin/env python3
"""Exact production source applier under boundary doubles: independent tools are not projection-gated."""
from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
t=(r/'Tests/ThreeDAutoRoute/explicit_sbs_lua_test.py').read_text();a=t.index('features=(root/');b=t.index('scenario=r',a)
ns={'root':r};exec(t[a:b],ns)
stubs=ns['stubs'].replace(' func setHeadTrackingEnabled(_ value:Bool,remember:Bool) {}',' var head=false;func setHeadTrackingEnabled(_ value:Bool,remember:Bool) {head=value}')
stubs=stubs.replace('func knownEyeAspect(kind:String,filename:String,width:Double,height:Double)->Double {16/9}', 'func knownEyeAspect(kind:String,filename:String,width:Double,height:Double)->Double {width>0 && height>0 ? width/height:0}')
main='''import Foundation
MainActor.assumeIsolated {
 for identity in ["","bound"] {
  for head in [false,true] {
   let c=TestController();c.recognitionIdentity=identity
   var state=ThreeDState();state.effects[.head] = .bool(head)
   // No bound film yet. Its source-projection fence must remain closed.
   c.applyThreeDState(state,[.showInfo],revision:1)
   precondition(c.head==head,"head choice lost at source identity guard")
   precondition(!c.commands.contains{$0.contains("vr180-look-set-projection")},"unbound source published projection")
   precondition(c.pendingRouteRevision==1,"pending source route lost")
   state.effects[.head] = .bool(!head)
   c.applyThreeDState(state,[.showInfo],revision:2)
   precondition(c.head == !head,"second head choice lost while binding pending")
  }
 }
 let g=TestController();g.latestWidth=0;g.latestHeight=0
 var pending=ThreeDState();pending.currentFilm=FilmID(rawValue:"191t-applier")
 pending.films["191t-applier"]=FilmThreeD();pending.films["191t-applier"]!.output = .sbs
 pending.effects[.head] = .bool(true)
 g.applyThreeDState(pending,[.showInfo],revision:3)
 precondition(g.head && g.pendingRouteRevision==3,"geometry guard suppressed head toggle")
 precondition(!g.commands.contains{$0.contains("vr180-look-set-projection")},"unready geometry published projection")
 print("PASS geometry pending does not block independent head capture")
 print("PASS actual applier: independent head ON/OFF reaches capture setters while missing/mismatched source keeps projection fenced")
}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d);(p/'Controller.swift').write_text(stubs+ns['applier']+ns['projection']+'}\n');(p/'main.swift').write_text(main)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/ThreeDState.swift'),str(p/'Controller.swift'),str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test')],check=True)
