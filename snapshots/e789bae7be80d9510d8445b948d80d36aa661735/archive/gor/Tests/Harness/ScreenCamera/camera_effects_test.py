
# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import tempfile,subprocess,shutil
r=Path(__file__).resolve().parents[3]
s=_s3read(r/'Sources/gor/GorPlatformMac/QuitChildKiller.swift');a=s.index('    private func configureCameraEffects()');b=s.index('    private func stopSessionLocked',a)
methods=s[a:b].replace('private func','func')
program='''import Foundation
final class AVCaptureDevice {
 enum Mode {case user,app}
 static var centerStageControlMode=Mode.user
 static var isCenterStageEnabled=true
 static let reactionEffectsEnabled=false,reactionEffectGesturesEnabled=false
 let isCenterStageActive=false,isPortraitEffectActive=false,isStudioLightActive=false,canPerformReactionEffects=false
}
final class Engine {let device:AVCaptureDevice?=AVCaptureDevice();var logs=[String]();func mediaLog(_ s:String){logs.append(s)}
'''+methods+'''}
let e=Engine();e.configureCameraEffects();e.recordCameraEffects(phase:"before-start",generation:3)
precondition(AVCaptureDevice.centerStageControlMode == .app && !AVCaptureDevice.isCenterStageEnabled)
for key in ["isCenterStageActive=false","isPortraitEffectActive=false","isStudioLightActive=false","reactionEffectsEnabled=false","canPerformReactionEffects=false","hypothesis=H2"] {precondition(e.logs[0].contains(key))}
print("PASS actual camera effect opt-out method + truthful state receipt")
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'main.swift').write_text(program);c=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 subprocess.run([c,str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
 mutant=program.replace('AVCaptureDevice.isCenterStageEnabled = false','AVCaptureDevice.isCenterStageEnabled = true')
 (p/'main.swift').write_text(mutant);subprocess.run([c,str(p/'main.swift'),'-o',str(p/'bad')],check=True)
 assert subprocess.run([str(p/'bad')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
print('PASS dropped Center Stage opt-out negative control rejected')
start=s.index('            configureCameraEffects()');run=s.index('            session.startRunning()',start)
assert start<run<s.index('recordCameraEffects(phase: "after-start"',run)
assert 'NSCameraReactionEffectGesturesEnabledDefault</key><false/>' in _s3read(r/'build.sh')
print('PASS plist default opt-out + start ordering; Mac effects require hardware receipt')
