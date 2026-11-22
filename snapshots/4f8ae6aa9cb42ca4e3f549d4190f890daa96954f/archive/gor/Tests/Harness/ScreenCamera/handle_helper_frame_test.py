#!/usr/bin/env python3
"""C6 ambient publish gate: the handleHelperFrame prefix (down to the
guard !ambientOnly boundary) extracted from ScreenCaptureEngine.swift,
compiled against the real camera-helper IPC Frame with boundary doubles.

Contract (lane request; the lane is the single writer of the product fix
and the ledger):
- a processed=false settled busy frame carrying lumaFull is NOT a
  Vision-confirmed noface: it must not publish full-frame immediately;
  it only arms the existing 0.25 s scalar fallback (the fallback stays
  under this fixture; C5 is separate and held);
- processed=true with face landmarks/rect publishes face+room;
- processed=true verified noface may publish full-frame;
- stale generation/window frames are rejected.

Positive execution uses the production prefix unchanged. The negative control removes its processed/no-error gate.
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import subprocess,tempfile,shutil
r=Path(__file__).resolve().parents[3]

def cut(s,a,b):return s[s.index(a):s.index(b,s.index(a))]

src=_s3read(r/'Sources/gor/Camera/ScreenCaptureEngine.swift')
start='    private func handleHelperFrame(_ f: CameraHelperIPC.Frame, generation: UInt64, ambientOnly: Bool) {'
i=src.index(start)
j=src.index('        guard !ambientOnly else { return }',i)
j=src.index('\n',j)+1
prefix=src[i:j]+'    }\n'
prefix=prefix.replace('    private func handleHelperFrame','    func handleHelperFrame')
GATE_OLD='            if !faceFound {\n                if let luma = f.lumaFull {'
GATE_NEW='            if !faceFound {\n                if f.processed, !f.visionFailed, let luma = f.lumaFull {'
assert GATE_NEW in prefix, 'production processed/no-error gate missing'
patched=prefix
prefix=prefix.replace(GATE_NEW,GATE_OLD)

ipc=cut(_s3read(r/'Sources/gor/Camera/HeadPose.swift'),
        '// BEGIN camera-helper IPC','// END camera-helper IPC')

HEAD='''import Foundation

'''+ipc+'''

var EVENTS=[String]()
// Boundary doubles below the guard !ambientOnly line and around the
// ambient-publish callees; the real IPC Frame above is the method's
// input type.
enum HeadTracker { struct TwoRegionLuma { var faceLuma: Double; var roomLuma: Double; var combined: Double } }
final class SubmitNow { func submit(_ body: () -> Void) { body() } }
final class Probe {
    var lifecycle: (requested: Bool, generation: UInt64) = (true, 7)
    func captureLifecycle() -> (requested: Bool, generation: UInt64) { lifecycle }
    func currentExpiredVisionToken() -> UInt64? { nil }
    var lastHelperPoseTime:Double = 0
    var blinkLogEnabled = false
    func feedBlinkFrame(_ f: CameraHelperIPC.Frame, generation: UInt64) { EVENTS.append("blink") }
    var ambientWindowID: UInt64 = 3
    var latestAmbientFrame = SubmitNow()
    func publishAmbient(_ luma: Double, regions: HeadTracker.TwoRegionLuma?, generation: UInt64, epoch: Double, source: String) { EVENTS.append(source) }
    func armAmbientFallback(_ luma: Double, generation: UInt64, epoch: Double) { EVENTS.append("armed") }
    func ambientEpoch() -> Double { 1 }
'''

SCEN='''
}

func mkframe(generation: UInt64 = 7, window: UInt64 = 3, processed: Bool, visionFailed: Bool = false,
             rect: CameraHelperIPC.FaceRect? = nil, lumaFull: Double? = nil,
             lumaRectFace: CameraHelperIPC.Luma2? = nil) -> CameraHelperIPC.Frame {
    CameraHelperIPC.Frame(generation: generation, window: window, now: 0, pts: -1, age: -1,
                          pixelWidth: 2, pixelHeight: 2, ambientOnly: false, settled: true,
                          consecutiveSettled: 3, seenFirstSettled: true, ambientSettled: true,
                          processed: processed, visionFailed: visionFailed, visionMS: 1,
                          rect: rect, lumaFull: lumaFull, lumaRectFace: lumaRectFace, exposureChanging: 0)
}
let p = Probe()
// Stale generation: rejected before anything records.
p.handleHelperFrame(mkframe(generation: 8, processed: true, lumaFull: 0.4), generation: 8, ambientOnly: false)
precondition(EVENTS.isEmpty, "stale generation must be rejected: \\(EVENTS)")
// Stale settle window: rejected.
p.handleHelperFrame(mkframe(window: 999, processed: true, lumaFull: 0.4), generation: 7, ambientOnly: false)
precondition(EVENTS.isEmpty, "stale window must be rejected: \\(EVENTS)")
// Busy tick (Vision slot busy, processed=false) with lumaFull: not a
// Vision-confirmed noface, no immediate publish; only the fallback arms.
p.handleHelperFrame(mkframe(processed: false, lumaFull: 0.4), generation: 7, ambientOnly: false)
precondition(EVENTS == ["armed"], "unprocessed busy frame must only arm the fallback, not publish noface: \\(EVENTS)")
EVENTS = []
// Processed face: face+room publish, then the fallback arms.
let fr = CameraHelperIPC.FaceRect(box: [0.1, 0.1, 0.4, 0.4], confidence: 0.9, faceCount: 1)
p.handleHelperFrame(mkframe(processed: true, rect: fr, lumaFull: 0.4, lumaRectFace: CameraHelperIPC.Luma2(face: 1, room: 2, combined: 3)), generation: 7, ambientOnly: false)
precondition(EVENTS == ["face-room", "armed"], "processed face publishes face+room: \\(EVENTS)")
EVENTS = []
// Processed, Vision-verified noface: full-frame publish is allowed.
p.handleHelperFrame(mkframe(processed: true, lumaFull: 0.4), generation: 7, ambientOnly: false)
precondition(EVENTS == ["full-frame", "armed"], "verified noface may publish full-frame: \\(EVENTS)")
EVENTS = []
// Processed but Vision perform() failed: not a verified noface; fallback only.
p.handleHelperFrame(mkframe(processed: true, visionFailed: true, lumaFull: 0.4), generation: 7, ambientOnly: false)
precondition(EVENTS == ["armed"], "visionFailed is not a verified noface: \\(EVENTS)")
print("PASS handleHelperFrame: stale generation/window rejected; busy tick arms fallback only; processed face publishes face+room; verified noface publishes full-frame")
'''

swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
with tempfile.TemporaryDirectory() as folder:
    p=Path(folder)
    (p/'fixed').mkdir()
    (p/'fixed/main.swift').write_text(HEAD+patched+SCEN)
    subprocess.run([swift,str(p/'fixed/main.swift'),'-o',str(p/'fixed/test')],check=True)
    subprocess.run([str(p/'fixed/test')],check=True,timeout=30)
    # Negative control: the current gate-dropped production text publishes
    # the unprocessed busy frame as a Vision-confirmed noface and fails.
    (p/'current').mkdir()
    (p/'current/main.swift').write_text(HEAD+prefix+SCEN)
    subprocess.run([swift,str(p/'current/main.swift'),'-o',str(p/'current/test')],check=True,capture_output=True)
    result=subprocess.run([str(p/'current/test')],capture_output=True,timeout=30)
    assert result.returncode!=0,'current gate-dropped text not caught'
    print('PASS current behavior publishes an unprocessed busy frame as Vision-confirmed noface (regression negative control)')
