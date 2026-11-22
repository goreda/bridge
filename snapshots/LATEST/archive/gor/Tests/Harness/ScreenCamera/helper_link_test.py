#!/usr/bin/env python3
"""C6 camera helper link: real NDJSON protocol + parent client against a fake helper.
Compiles the production CameraHelperIPC section (Stereo/HeadPose.swift) and the
production CameraHelperClient (QuitChildKiller.swift) with only the registry and
owner-flag names doubled, then drives real child processes of the same test
binary: normal stop<2s, hung stop -> SIGKILL, bad hello -> kill, respawn epochs.
Negative control: dropping the SIGKILL makes the hung-stop assertion fail.
"""

# S3 location adapter: reconstructs byte-identical pre-move source, assertions unchanged.
import sys as _s3sys
from pathlib import Path as _S3Path
_s3root=next(p for p in _S3Path(__file__).resolve().parents if (p/'Sources/gor').is_dir())
_s3sys.path.insert(0,str(_s3root/'Tests/Architecture'))
from camera_source import read_source as _s3read
from pathlib import Path
import subprocess,tempfile,shutil,sys
r=Path(__file__).resolve().parents[3]

def cut(s,a,b):return s[s.index(a):s.index(b,s.index(a))]

ipc=cut(_s3read(r/'Sources/gor/Camera/HeadPose.swift'),
        '// BEGIN camera-helper IPC','// END camera-helper IPC')
client=cut(_s3read(r/'Sources/gor/GorPlatformMac/QuitChildKiller.swift'),
           'final class CameraHelperClient','// MARK: - Helper-side (child process)')
# Doubles for the two production names the client takes from macOS-only code.
client=client.replace('CameraHelperCLI.flag','"--camera-helper"')
client=client.replace('PrepareProcessLifetime.ownerFlag','"--gor-owner-pid"')
client=client.replace('QuitChildKiller.shared.register(p)','register(p)')
client=client.replace('import AVFoundation\n','').replace('import Vision\n','')

driver=r'''
import Foundation
#if canImport(Glibc)
import Glibc
#endif
func register(_ p: Process) {}

'''+ipc+'''

'''+client+'''

// MARK: - fake helper modes

func fakeHelperMain(_ mode: String) -> Int32 {
    let out = FileHandle.standardOutput
    func send(_ e: CameraHelperIPC.Event) { try? out.write(contentsOf: CameraHelperIPC.encode(e)) }
    if mode == "badhello" {
        send(CameraHelperIPC.Event(ev: "hello", version: 999, pid: getpid()))
        while true { sleep(1) }
    }
    send(CameraHelperIPC.Event(ev: "hello", version: CameraHelperIPC.protocolVersion, pid: getpid()))
    var splitter = CameraHelperIPC.LineSplitter()
    let stdin = FileHandle.standardInput
    while true {
        let data = stdin.availableData
        if data.isEmpty { exit(0) }
        for line in splitter.push(data) {
            guard let cmd = CameraHelperIPC.decodeCommand(line) else { continue }
            switch cmd.cmd {
            case "configure":
                send(CameraHelperIPC.Event(ev: "state", state: "running", generation: cmd.generation))
                for i in 0..<2 {
                    let f = CameraHelperIPC.Frame(generation: cmd.generation, window: cmd.window,
                        now: Double(i), pts: -1, age: -1, pixelWidth: 2, pixelHeight: 2,
                        ambientOnly: cmd.ambientOnly, settled: true, consecutiveSettled: 3,
                        seenFirstSettled: true, ambientSettled: true, processed: true,
                        visionFailed: false, visionMS: 1, exposureChanging: 0)
                    send(CameraHelperIPC.Event(ev: "frame", frame: f))
                }
                if cmd.generation == 1 { send(CameraHelperIPC.Event(ev: "vision-cancelled", token: 77)) }
            case "stop":
                if mode == "hang" { break } // never answer: the hung-Apple-stop model
                send(CameraHelperIPC.Event(ev: "state", state: "stopped", generation: cmd.generation, running: false))
                exit(0)
            case "shutdown": exit(0)
            default: break
            }
        }
    }
}

// MARK: - protocol unit checks

func protocolChecks() {
    let cmd = CameraHelperIPC.Command(cmd: "configure", generation: 7, window: 3, headPose: true, blink: false, ambientOnly: false)
    precondition(CameraHelperIPC.decodeCommand(CameraHelperIPC.encode(cmd).dropLast()) == cmd)
    let frame = CameraHelperIPC.Frame(generation: 1, window: 2, now: 3, pts: 4, age: 0.1, pixelWidth: 640, pixelHeight: 480,
        ambientOnly: false, settled: true, consecutiveSettled: 3, seenFirstSettled: true, ambientSettled: true,
        processed: true, visionFailed: false, visionMS: 12.5, exposureChanging: 0)
    let ev = CameraHelperIPC.Event(ev: "frame", frame: frame)
    precondition(CameraHelperIPC.decodeEvent(CameraHelperIPC.encode(ev).dropLast()) == ev)
    let cancel = CameraHelperIPC.Event(ev: "vision-cancelled", token: 77)
    precondition(CameraHelperIPC.decodeEvent(CameraHelperIPC.encode(cancel).dropLast()) == cancel)
    var sp = CameraHelperIPC.LineSplitter()
    let half = CameraHelperIPC.encode(cmd)
    precondition(sp.push(half.prefix(5)).isEmpty)
    precondition(sp.push(half.suffix(from: 5)).count == 1)
    precondition(sp.push(Data(repeating: 65, count: CameraHelperIPC.maxLineBytes + 1)).isEmpty)
    precondition(sp.push(CameraHelperIPC.encode(cmd)).count == 1) // recovers after the dropped garbage
    print("PASS protocol: command/event/frame roundtrip, partial-line hold, over-long line dropped then recovery")
}

// MARK: - client driver

final class Recorder {
    let lock = NSLock()
    var runnings = 0, frames = 0, exits = 0, timeouts = 0
    var failures: [String] = []
    var stopReported = false
    var cancelledTokens: [UInt64] = []
    func add(_ i: CameraHelperClient.Incoming) {
        lock.lock(); defer { lock.unlock() }
        switch i {
        case .running: runnings += 1
        case .frame: frames += 1
        case .exited: exits += 1
        case .terminatedAfterTimeout: timeouts += 1
        case .failed(let r): failures.append(r)
        case .stopped: stopReported = true
        case .visionCancelled(let t): cancelledTokens.append(t)
        case .log: break
        }
    }
    func snapshot() -> (Int, Int, Int, Int, [String]) {
        lock.lock(); defer { lock.unlock() }
        return (runnings, frames, exits, timeouts, failures)
    }
    func cancels() -> [UInt64] { lock.lock(); defer { lock.unlock() }; return cancelledTokens }
}

func until(_ seconds: Double, _ cond: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { if cond() { return true }; Thread.sleep(forTimeInterval: 0.01) }
    return cond()
}

func clientChecks() {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0])

    // 1. Normal: hello identity, configure -> running + frames, stop < 2 s.
    let rec = Recorder(); let client = CameraHelperClient()
    client.executableOverride = exe
    client.onIncoming = { rec.add($0) }
    client.ensureRunning(generation: 1, window: 1, headPose: true, blink: false, ambientOnly: false)
    precondition(until(3) { let s = rec.snapshot(); return s.0 == 1 && s.1 >= 2 }, "normal: running+frames")
    let pid1 = client.helperPID
    precondition(pid1 > 0)
    let t0 = Date()
    var stopResult: Bool?
    client.stopSession(generation: 1) { ok in stopResult = ok }
    precondition(until(3) { stopResult != nil }, "normal: stop completion")
    let stopElapsed = Date().timeIntervalSince(t0)
    precondition(stopResult == true && stopElapsed < 2.0, "normal: stop reported off under 2s")
    precondition(until(3) { rec.cancels() == [77] }, "normal: vision-cancelled notice delivered")
    precondition(until(3) { kill(pid1, 0) != 0 && errno == ESRCH }, "normal: child exited")
    print("PASS normal helper: hello pid/version bound, frames delivered, stop off in \(String(format: "%.2f", stopElapsed))s, child reaped")

    // 2. Hung stop: no stopped report in 2 s -> SIGKILL -> completion(true) via exit.
    let rec2 = Recorder(); let client2 = CameraHelperClient()
    client2.executableOverride = exe
    client2.onIncoming = { rec2.add($0) }
    client2.ensureRunning(generation: 1, window: 1, headPose: true, blink: false, ambientOnly: false)
    // mode switch: relaunch in hang mode
    client2.stopSession(generation: 1) { _ in }
    precondition(until(3) { rec2.snapshot().2 == 1 })
    let hangExe = exe // same binary, hang mode via env
    let rec3 = Recorder(); let client3 = CameraHelperClient()
    client3.executableOverride = hangExe
    client3.onIncoming = { rec3.add($0) }
    setenv("FAKE_HELPER_MODE", "hang", 1)
    client3.ensureRunning(generation: 2, window: 1, headPose: true, blink: false, ambientOnly: false)
    precondition(until(3) { rec3.snapshot().0 == 1 }, "hang: running")
    let pid3 = client3.helperPID
    let t1 = Date()
    var stop3: Bool?
    client3.stopSession(generation: 2) { ok in stop3 = ok }
    precondition(until(6) { rec3.snapshot().3 == 1 }, "hang: terminatedAfterTimeout fired")
    let killElapsed = Date().timeIntervalSince(t1)
    precondition(killElapsed >= 1.9 && killElapsed < 3.5, "hang: SIGKILL at the 2s deadline")
    precondition(until(4) { stop3 != nil }, "hang: stop completion after kill")
    precondition(stop3 == true, "hang: exit confirms camera off (never a false-off)")
    precondition(until(3) { kill(pid3, 0) != 0 && errno == ESRCH }, "hang: killed child reaped")
    print("PASS hung stop: 2s deadline -> SIGKILL at \(String(format: "%.2f", killElapsed))s, completion via exit, no false off")

    // 3. Bad hello: version mismatch -> failed + child killed before any use.
    unsetenv("FAKE_HELPER_MODE")
    setenv("FAKE_HELPER_MODE", "badhello", 1)
    let rec4 = Recorder(); let client4 = CameraHelperClient()
    client4.executableOverride = exe
    client4.onIncoming = { rec4.add($0) }
    client4.ensureRunning(generation: 3, window: 1, headPose: true, blink: false, ambientOnly: false)
    precondition(until(3) { rec4.snapshot().4.contains("hello-mismatch") }, "badhello: failed(hello-mismatch)")
    // The mismatched child is SIGKILLed before any of its output is
    // used; the client observes the exit (helperPID is already cleared
    // by then, so assert the exit event, not the pid).
    precondition(until(3) { rec4.snapshot().2 == 1 }, "badhello: impostor killed")
    print("PASS bad hello: version mismatch refused, child killed")

    // 4. Respawn epoch: a new spawn gets a new pid and delivers again.
    unsetenv("FAKE_HELPER_MODE")
    let rec5 = Recorder(); let client5 = CameraHelperClient()
    client5.executableOverride = exe
    client5.onIncoming = { rec5.add($0) }
    client5.ensureRunning(generation: 4, window: 1, headPose: true, blink: false, ambientOnly: false)
    precondition(until(3) { rec5.snapshot().0 == 1 })
    let pid5a = client5.helperPID
    var s5: Bool?
    client5.stopSession(generation: 4) { ok in s5 = ok }
    precondition(until(3) { s5 == true })
    client5.ensureRunning(generation: 5, window: 2, headPose: true, blink: false, ambientOnly: false)
    precondition(until(3) { let s = rec5.snapshot(); return s.0 == 2 && s.1 >= 4 }, "respawn: second running+frames")
    precondition(client5.helperPID != pid5a, "respawn: fresh child pid")
    print("PASS respawn: new epoch/pid, frames flow again")
}

// The client spawns this same binary with --camera-helper --gor-owner-pid <pid>;
// the mode travels in FAKE_HELPER_MODE so the spawn arguments stay identical
// to production.
let args = CommandLine.arguments
if args.contains("--camera-helper") {
    let mode = ProcessInfo.processInfo.environment["FAKE_HELPER_MODE"] ?? "normal"
    exit(fakeHelperMain(mode))
}
protocolChecks()
clientChecks()
print("PASS helper link: all client checks")
'''

with tempfile.TemporaryDirectory() as td:
 p=Path(td)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 (p/'main.swift').write_text(driver)
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'test')],check=True)
 subprocess.run([str(p/'test'),'driver'],check=True,timeout=60,env={'PATH':'/usr/bin:/bin'})

# C2 watchdog fixture: compile and execute the actual helper watchdog and
# CPU-selection methods (extracted production text) with only the Vision/ML
# boundary and the sink doubled. Covers what text pins cannot: cancel-once,
# expired-token rejection, end-before-deadline, supersede, compute fallback.
watch=cut(_s3read(r/'Sources/gor/GorPlatformMac/QuitChildKiller.swift'),
          '    // MARK: - bounded CPU Vision watchdog','    private var configured = false')
a=watch.index('    /// The active helper samples ITSELF')
b=watch.index('    private func endVisionWatchdog',a)
watch=watch[:a]+'    private func sampleHungVision(epoch:UInt64) {}\n'+watch[b:]
watch=watch.replace('private ','')
wprog=r"""import Foundation
func CACurrentMediaTime()->Double { ProcessInfo.processInfo.systemUptime }
enum MLComputeDevice { case cpu, neuralEngine, gpu }
class VNRequest {
 var usesCPUOnly=false
 var devices:[String:[MLComputeDevice]] = ["main":[.cpu]]
 var throwOnQuery=false
 var setDevices:[String:MLComputeDevice]=[:]
 var cancels=0
 var supportedComputeStageDevices:[String:[MLComputeDevice]] { get throws {
  if throwOnQuery { throw NSError(domain:"test",code:9) }; return devices } }
 func setComputeDevice(_ d:MLComputeDevice, for stage:String){ setDevices[stage]=d }
 func cancel(){ cancels+=1 }
}
"""+ipc+r"""
final class Sink { var events:[CameraHelperIPC.Event]=[]; var logs:[String]=[]
 func send(_ e:CameraHelperIPC.Event){events.append(e)} }
final class Engine {
 let sink=Sink()
 func mediaLog(_ m:String){ sink.logs.append(m) }
"""+watch+r"""
}
let e=Engine(),rq=VNRequest()
let token=e.beginVisionWatchdog([rq])
precondition(token==1 && e.visionEpochIsCurrent(token))
Thread.sleep(forTimeInterval:1.4)
precondition(rq.cancels==1,"watchdog cancels exactly once")
precondition(!e.visionEpochIsCurrent(token),"expired token rejected")
precondition(e.sink.events.contains{ $0.ev=="vision-cancelled" && $0.token==token })
precondition(e.sink.logs.contains{ $0.contains("cancel_once=true") && $0.contains("recovery=sample-then-bounded-process-exit") })
let rq2=VNRequest()
let token2=e.beginVisionWatchdog([rq2])
e.endVisionWatchdog(token2)
Thread.sleep(forTimeInterval:1.4)
precondition(rq2.cancels==0 && e.sink.events.count==1)
let rq3=VNRequest(),rq4=VNRequest()
let t3=e.beginVisionWatchdog([rq3])
let t4=e.beginVisionWatchdog([rq4])
e.endVisionWatchdog(t4)
Thread.sleep(forTimeInterval:1.4)
precondition(rq3.cancels==0 && rq4.cancels==0,"a superseded watchdog must never cancel")
precondition(e.sink.events.count==1)
let ok=VNRequest(); ok.devices=["main":[.cpu,.neuralEngine],"secondary":[.gpu,.cpu]]
precondition(e.selectVisionCPU(ok) && ok.setDevices.count==2)
let noCpu=VNRequest(); noCpu.devices=["main":[.neuralEngine]]
precondition(!e.selectVisionCPU(noCpu))
let empty=VNRequest(); empty.devices=[:]
precondition(!e.selectVisionCPU(empty))
let broken=VNRequest(); broken.throwOnQuery=true
precondition(!e.selectVisionCPU(broken))
print("PASS C2 watchdog actual methods: cancel-once at 1s, expired token rejected, vision-cancelled event, end/supersede safe, CPU pin + no-ANE-fallback + query-error")
"""
with tempfile.TemporaryDirectory() as td:
 p=Path(td)
 swift=shutil.which('swiftc') or '/tmp/swift-6.0.3-RELEASE-ubuntu22.04/usr/bin/swiftc'
 (p/'watch.swift').write_text(wprog)
 subprocess.run([swift,str(p/'watch.swift'),'-o',str(p/'watch')],check=True)
 subprocess.run([str(p/'watch')],check=True,timeout=30)
 # Negative controls: dropped cancel and dropped expiry are both caught.
 for name,old,new in [('cancel','for request in requests { request.cancel() }','_ = requests'),
                      ('expiry','if expired { self.visionEpoch &+= 1 }','if expired {}')]:
  mutant=wprog.replace(old,new)
  (p/(name+'.swift')).write_text(mutant)
  subprocess.run([swift,str(p/(name+'.swift')),'-o',str(p/name)],check=True,capture_output=True)
  assert subprocess.run([str(p/name)],capture_output=True,timeout=30).returncode!=0,name+' mutant not caught'
  print('PASS dropped-'+name+' negative control rejected')
 # Negative control: without the SIGKILL the hung stop never completes.
 mutant=driver.replace('kill(p.processIdentifier, SIGKILL)','_ = p.processIdentifier')
 (p/'mutant.swift').write_text(mutant)
 subprocess.run([swift,str(p/'mutant.swift'),'-o',str(p/'mutant')],check=True,capture_output=True)
 result=subprocess.run([str(p/'mutant'),'driver'],capture_output=True,timeout=60,env={'PATH':'/usr/bin:/bin'})
 assert result.returncode!=0,'dropped-SIGKILL mutant not caught'
 print('PASS dropped-SIGKILL negative control rejected')

# E1 differential: default revision CPU requests returned; default device hung.
source=_s3read(r/'Sources/gor/GorPlatformMac/QuitChildKiller.swift')
constructors=cut(source,'    private func makeFaceRequest()','    private let ambientFaceRequest')
assert '.revision =' not in constructors
process=source[source.index('    private func process(_ pixelBuffer:'):]
assert 'guard selectVisionCPU(faceRequest), selectVisionCPU(blinkRequest) else { return }' in process
assert 'perform(handler, [blinkRequest, faceRequest]' not in process
head=process[process.index('let blinkRequest = makeBlinkRequest()'):]
assert head.index('beginVisionWatchdog([blinkRequest, faceRequest])') < head.index('perform(handler, [faceRequest]') < head.index('perform(handler, [blinkRequest]') < head.index('frame.rect =')
assert 'configured=cpu-all-stages executed_device=not-exposed' in source
program="""import Foundation
class VNDetectFaceRectanglesRequest {var revision=2}
class VNDetectFaceLandmarksRequest {var revision=2}
final class Factory {
"""+constructors.replace('private func','func')+"""
}
let f=Factory();precondition(f.makeFaceRequest().revision==2 && f.makeBlinkRequest().revision==2)
print("PASS actual head/blink constructors preserve system default revision")
"""
with tempfile.TemporaryDirectory() as td:
 p=Path(td);(p/'main.swift').write_text(program)
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'factory')],check=True)
 subprocess.run([str(p/'factory')],check=True)
 bad=program.replace('return r','r.revision=3;return r')
 (p/'main.swift').write_text(bad)
 subprocess.run([swift,str(p/'main.swift'),'-o',str(p/'badfactory')],check=True)
 assert subprocess.run([str(p/'badfactory')],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode!=0
print('PASS E1 differential: actual default revision constructors + negative control; separate CPU-only requests, bounded epoch/watchdog')
