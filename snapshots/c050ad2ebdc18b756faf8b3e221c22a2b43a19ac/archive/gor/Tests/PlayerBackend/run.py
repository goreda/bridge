from pathlib import Path
import os,subprocess,tempfile
r=Path(__file__).resolve().parents[2]
code='''import Foundation
precondition(PlayerEngine.selected(environment:[:],saved:nil) == .mpv)
precondition(PlayerEngine.selected(environment:["GOR_ENGINE":"gorav"],saved:nil) == .gorav)
precondition(PlayerEngine.selected(environment:["GOR_ENGINE":"mpv"],saved:"gorav") == .mpv)
precondition(PlayerEngine.selected(environment:["GOR_ENGINE":"invalid"],saved:"invalid") == .mpv)
precondition(PlayerEngine.selected(environment:[:],saved:"gorav") == .gorav)
var launched:[String?]=[]
for engine in [PlayerEngine.mpv,.gorav,.mpv,.gorav,.mpv] {
 let route=PlayerBackendRoute.resolve(engine)
 precondition(route.requested==engine && route.active == .mpv)
 precondition((route.fallbackReason != nil)==(engine == .gorav))
 route.launch(file:"movie.mp4"){launched.append($0)}
}
precondition(launched.count==5 && launched.allSatisfy{$0=="movie.mp4"})
precondition(GorAVBackend().admission() != .ready)
print("PASS production backend selection/default/env/persistence, stub refusal, explicit fallback, repeated rollback, exactly one unchanged mpv launch per request")
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(code)
 subprocess.run([os.environ.get('SWIFTC','swiftc'),str(r/'Sources/gor/Engine/MPVCommand.swift'),str(t/'main.swift'),'-o',str(t/'test')],check=True)
 subprocess.run([str(t/'test')],check=True)
 env=dict(os.environ,GOR_ENGINE='gorav');env.pop('GORAV_E1_ASSERTS',None)
 result=subprocess.check_output(['bash',str(r/'Tests/PlayerBackend/selftest.sh')],env=env,text=True)
 assert result.strip()=='E1 asserts: not yet on trunk' and 'PASS' not in result
 (t/'Package.swift').write_text('// fixture package boundary')
 for rc in [0,1]:
  f=t/'asserts.sh';f.write_text('exit '+str(rc)+'\n')
  result=subprocess.run(['bash',str(r/'Tests/PlayerBackend/selftest.sh')],env=dict(env,GORAV_ENGINE_ROOT=str(t),GORAV_E1_ASSERTS=str(f)),capture_output=True,text=True)
  assert (result.returncode==0)==(rc==0)
  assert ('PASS gorav-e1' in result.stdout)==(rc==0)
print('PASS optional E1 hook: absent is not PASS; actual command exit decides pass/fail')
s=(r/'build.sh').read_text();app=(r/'Sources/gor/App/AppDelegate.swift').read_text()
assert 'export GOR_ENGINE=mpv' in s and 'local requested_test_engine=' in s
block=s[s.index('# Optional E1'):s.index('# Block184 new feature')]
assert 'st_pass' not in block and 'st_fail' not in block and 'st_note' in block
assert 'route.launch(file: file)' in app and 'private func launchMPVImplementation' in app
assert 'choice.representedObject = engine.rawValue' in app and 'UserDefaults.standard.set(engine.rawValue' in app
assert '.package(' not in (r/'Package.swift').read_text()
print('PASS integration: real launch wraps existing mpv implementation; persisted menu selection; no package dependency; optional E1 does not alter lifecycle counters')
print('Linux tests only; no native AppKit build, native playback, E1 or t1/l1-l4 execution claim')
