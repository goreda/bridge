
from pathlib import Path
import importlib.util
import tempfile,subprocess,shutil
r=Path(__file__).resolve().parents[3]
_spec=importlib.util.spec_from_file_location('watchdog_sections',r/'Tests/Structure/section_source.py')
_sections=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(_sections)
method=_sections.symbol_text(r,'SubtitleFaceWatchdog',kind='class').replace('private final','final',1)
program='''import Foundation
enum Device {case cpu,ane}
class VNRequest {
 var usesCPUOnly=false,cancels=0;var selected=[String:Device]();var devices=["main":[Device.ane,.cpu]]
 var supportedComputeStageDevices:[String:[Device]] {get throws {devices}}
 func setComputeDevice(_ d:Device,for stage:String){selected[stage]=d}
 func cancel(){cancels+=1}
}
struct Diag {static func mediaRecord(_ s:String){}}
'''+method+'''
let request=VNRequest();precondition(SubtitleFaceWatchdog.selectCPU(request));precondition(request.selected["main"] == .cpu)
let unsupported=VNRequest();unsupported.devices=["main":[.ane]];precondition(!SubtitleFaceWatchdog.selectCPU(unsupported))
let blocked=VNRequest();let w=SubtitleFaceWatchdog(blocked)
let gate=DispatchSemaphore(value:0),done=DispatchSemaphore(value:0)
DispatchQueue.global().async {gate.wait();precondition(!w.finish());done.signal()}
Thread.sleep(forTimeInterval:1.3);precondition(blocked.cancels==1);gate.signal();precondition(done.wait(timeout:.now()+2) == .success)
let healthy=VNRequest();let h=SubtitleFaceWatchdog(healthy);precondition(h.finish());Thread.sleep(forTimeInterval:1.2);precondition(healthy.cancels==0)
print("PASS actual subtitle CPU selection, no ANE fallback, blocked double cancel once/drop, healthy result preserved")
'''
with tempfile.TemporaryDirectory() as folder:
 p=Path(folder);(p/'main.swift').write_text(program);c=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc';subprocess.run([c,str(p/'main.swift'),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
 bad=program.replace('request.cancel();','/* cancellation removed */');(p/'main.swift').write_text(bad);subprocess.run([c,str(p/'main.swift'),'-o',str(p/'bad')],check=True);assert subprocess.run([str(p/'bad')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
print('PASS dropped subtitle cancel negative control rejected')
body=_sections.func_text(r,'private func sampleSubtitleFaces()')
assert body.index('SubtitleFaceWatchdog.selectCPU(request)')<body.index('let watchdog = SubtitleFaceWatchdog(request)')<body.index('.perform([request])')<body.index('watchdog.finish()')
assert 'guard accepted, self.faceLifecycle == lifecycle' in body
