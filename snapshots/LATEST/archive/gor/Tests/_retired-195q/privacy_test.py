import importlib.util as _iu, pathlib as _pl
def _pp_split():
    _d = _pl.Path(__file__).resolve().parent
    while not (_d / 'Tests/Structure/pp_split.py').exists():
        _d = _d.parent
    _s = _iu.spec_from_file_location('pp_split', _d / 'Tests/Structure/pp_split.py')
    _m = _iu.module_from_spec(_s); _s.loader.exec_module(_m); return _m
#!/usr/bin/env python3
from pathlib import Path
import subprocess,tempfile,shutil,importlib.util
r=Path(__file__).resolve().parents[3]
swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
main='''import Foundation
var gate=CameraPrivacyGate()
precondition(gate.permitsRequests && !gate.paused)
precondition(gate.pause() && !gate.permitsRequests)
// Default ambient and blink requests cannot authorize hardware.
for _ in 0..<100 {precondition(!gate.permitsRequests)}
precondition(gate.explicitEnable() && gate.permitsRequests)
precondition(!gate.explicitEnable() && gate.permitsRequests)
precondition(gate.pause() && !gate.permitsRequests)
precondition(!gate.pause() && !gate.permitsRequests)
// Stale authorization/start work checks the current gate, never old intent.
precondition(!gate.permitsRequests)
precondition(gate.explicitEnable() && gate.permitsRequests)
gate.quit();precondition(!gate.permitsRequests && gate.shutDown)
precondition(!gate.explicitEnable() && !gate.permitsRequests)
for _ in 0..<100 {gate.pause();precondition(!gate.explicitEnable() && !gate.permitsRequests)}
print("PASS production camera privacy gate: launch preserved, explicit resume,OFF beats auto requests, quit irreversible")
precondition(ThreeDKeymap.match(charactersIgnoringModifiers:"H",keyCode:4,shift:true,option:false,control:false,command:false) == .headTracking)
precondition(ThreeDKeymap.match(charactersIgnoringModifiers:"h",keyCode:4,shift:false,option:false,control:false,command:false) == nil)
print("PASS real Swift shared keymap ShiftH/head action; plainH remains unclaimed")
'''
with tempfile.TemporaryDirectory() as td:
 t=Path(td);(t/'main.swift').write_text(main)
 (t/'ThreeDKeymap.swift').write_text((r/'Sources/gor/ThreeDKeymap.swift').read_text().split('enum ThreeDInfo {')[0])
 subprocess.run([swift,str(r/'Sources/gor/CameraPrivacyGate.swift'),str(t/'ThreeDKeymap.swift'),str(t/'main.swift'),'-o',str(t/'test')],check=True)
 subprocess.run([str(t/'test')],check=True)
s=(r/'Sources/gor/GorCaptureModel/ScreenCaptureEngine.swift').read_text();f=(_pp_split().path(r,'PPController_Features.swift')).read_text();m=(r/'Sources/gor/ThreeDMenu.swift').read_text();a=(r/'Sources/gor/AppDelegate.swift').read_text()
assert 'activeConsumers > 0 && cameraPrivacy.permitsRequests' in s
assert 'guard cameraPrivacy.permitsRequests, activeConsumers > 0' in s
assert 'guard cameraPrivacy.permitsRequests, !hasRequestedAmbientStart' in s
assert 'func stopForQuit()' in s and 'cameraPrivacy.quit()' in s
assert 'HeadTracker.shared.stopForQuit()' in a
assert 'HeadTracker.shared.setCameraPrivacyPaused(!enabled)' in f and 'HeadTracker.shared.setCameraPrivacyPaused(!next)' in m
assert 'HEAD-KEY event=received' in f and 'HEAD-KEY event=matched' in f and 'HEAD-KEY event=dispatch' in m
assert 'HEAD-STATE event=apply' in f and 'hardware-stopped' in s and 'hardware-started' in s
# Hardware stop authority is current request state; a paused consumer joining
# cannot invalidate an already queued privacy stop by advancing its generation.
stop=s[s.index('private func scheduleHardwareStop'):s.index('// MARK: - Ambient-only consumer')]
assert 'guard !snapshot.requested else' in stop and 'snapshot.generation == generation' not in stop
spec=importlib.util.spec_from_file_location('capture',r/'tools/gor-periodic-capture.py');capture=importlib.util.module_from_spec(spec);spec.loader.exec_module(capture)
rows=capture.extract('gor_diag.log','''17:41 HEAD-CAPTURE event=consumer-start state=running consumers=1 generation=39 ambient=true paused=false path=/private/secret
17:42 HEAD-CAPTURE event=hardware-stopped running=false generation=40
HEAD-KEY event=received keyCode=4 repeat=false music=false iptv=false panel=false email=private@example.com
HEAD-STATE event=apply enabled=false loaded=true active=true
''')
text='\n'.join(rows);assert 'ambient=true' in text and 'hardware-stopped' in text and 'keyCode=4' in text and 'enabled=false' in text
assert 'private' not in text and 'secret' not in text
print('PASS production capture fixed key/consumer/privacy/hardware receipts with private-field exclusion; native AVCapture/keyboard hardware NOT_RUN')
