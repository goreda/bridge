import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

// BEGIN camera-helper runtime (arch-195z Z3, owner-approved; arch-196b C6)
// Same-executable camera helper: the child owns AVCaptureSession and all
// camera Vision work; the parent (HeadTracker) keeps consumer policy,
// pose/blink/gaze/ambient downstream math and every receipt. This file
// holds the process boundary: the parent-side client, the wire host and
// the child-side engine. Lifetime honesty notes from QuitChildKiller
// apply here: SIGKILL targets only our own registered child pid while
// it is live and unreaped; the residual TOCTOU is named, not eliminated.
// Termination is at most one automatic relaunch per consumer
// generation, decided by HeadTracker -- no unlimited retry loop.

/// Parent side: owns the helper Process, the NDJSON pipes and the
/// 2 s stop guarantee. All callbacks fire on a single serial queue, so
/// HeadTracker consumes frames with the same serialized discipline the
/// old visionQueue gave it. Never touches the main thread itself.
final class CameraHelperClient {
    enum Incoming {
        case running(generation: UInt64)
        case stopped(generation: UInt64, stillRunning: Bool)
        case failed(reason: String)
        /// The child process ended, expectedly (after stop/shutdown) or not.
        case exited
        /// The stop deadline passed; SIGKILL was sent to the owned child.
        case terminatedAfterTimeout
        /// The helper's bounded Vision watchdog expired this token (C2):
        /// the frame carrying it will never arrive, and in-flight blink
        /// deliveries must be invalidated (blink epoch bump).
        case visionCancelled(token: UInt64)
        case log(channel: String, message: String)
        case frame(CameraHelperIPC.Frame)
    }
    var onIncoming: (Incoming) -> Void = { _ in }

    private let queue = DispatchQueue(label: "gor.camera-helper.client", qos: .userInitiated)
    private var child: Process?
    private var childStdin: FileHandle?
    private var splitter = CameraHelperIPC.LineSplitter()
    /// Bumps per spawn; reader/termination callbacks of an older child
    /// are rejected, so a stale pipe can never deliver into a new epoch.
    private var epoch: UInt64 = 0
    private(set) var helperPID: pid_t = 0
    private var stopCompletions: [(Bool) -> Void] = []
    private var stopTimer: DispatchWorkItem?
    private var killConfirmTimer: DispatchWorkItem?
    private let stopTimeout: TimeInterval
    /// Test seam: the fake helper's path. nil = this app's own executable.
    var executableOverride: URL?

    init(stopTimeout: TimeInterval = 2.0) { self.stopTimeout = stopTimeout }

    var hasLiveChild: Bool { queue.sync { child != nil } }

    func ensureRunning(generation: UInt64, window: UInt64, headPose: Bool, blink: Bool, ambientOnly: Bool) {
        queue.async {
            guard self.spawnLocked() else { self.onIncoming(.failed(reason: "spawn")); return }
            self.sendLocked(CameraHelperIPC.Command(cmd: "configure", generation: generation, window: window, headPose: headPose, blink: blink, ambientOnly: ambientOnly))
        }
    }

    func setConfig(generation: UInt64, window: UInt64, headPose: Bool, blink: Bool, ambientOnly: Bool) {
        queue.async {
            guard self.child != nil else { return }
            self.sendLocked(CameraHelperIPC.Command(cmd: "configure", generation: generation, window: window, headPose: headPose, blink: blink, ambientOnly: ambientOnly))
        }
    }

    func resetSettling(generation: UInt64, window: UInt64) {
        queue.async { self.sendLocked(CameraHelperIPC.Command(cmd: "reset-settling", generation: generation, window: window)) }
    }

    /// Zero-consumer stop. completion(true) means the camera is
    /// confirmed off (helper reported stopped, or the process is gone:
    /// exit releases the device). completion(false) means even SIGKILL
    /// could not be confirmed -- a truthful failure, never a false off.
    func stopSession(generation: UInt64, completion: @escaping (Bool) -> Void) {
        queue.async {
            guard let p = self.child, p.isRunning else { completion(true); return }
            self.stopCompletions.append(completion)
            guard self.stopCompletions.count == 1 else { return } // one stop in flight; completions chain
            self.sendLocked(CameraHelperIPC.Command(cmd: "stop", generation: generation))
            let timer = DispatchWorkItem { [weak self] in self?.stopTimedOutLocked() }
            self.stopTimer = timer
            self.queue.asyncAfter(deadline: .now() + self.stopTimeout, execute: timer)
        }
    }

    /// App quit: ask politely, never wait. The QuitChildKiller registry
    /// (SIGTERM -> 300 ms -> SIGKILL) owns the quit-time guarantee.
    func shutdown() {
        queue.async { self.sendLocked(CameraHelperIPC.Command(cmd: "shutdown")) }
    }

    /// 197i: escalate blink landmark admission while a gesture episode is
    /// in flight under the 196v thermal stride. until is a CACurrentMediaTime
    /// deadline on the same clock; 0 clears. Additive command: an old helper
    /// ignores the unknown cmd string (default: break in apply()).
    func blinkBoost(until: Double) {
        queue.async { self.sendLocked(CameraHelperIPC.Command(cmd: "blink-boost", blinkBoostUntil: until)) }
    }

    // MARK: - internals (all on `queue`)

    private func spawnLocked() -> Bool {
        guard child == nil else { return true }
        guard let exe = executableOverride ?? Bundle.main.executableURL else { return false }
        epoch &+= 1
        let myEpoch = epoch
        let p = Process()
        p.executableURL = exe
        p.arguments = [CameraHelperCLI.flag, PrepareProcessLifetime.ownerFlag, String(ProcessInfo.processInfo.processIdentifier)]
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.standardError
        splitter = CameraHelperIPC.LineSplitter()
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.queue.async {
                guard self.epoch == myEpoch else { return } // stale reader of an older child
                if data.isEmpty { self.childExitedLocked(); return }
                for line in self.splitter.push(data) { self.handleLineLocked(line) }
            }
        }
        p.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.queue.async { guard self.epoch == myEpoch else {return}; self.childExitedLocked() }
        }
        do {
            try p.run()
            QuitChildKiller.shared.register(p)
            child = p
            childStdin = inPipe.fileHandleForWriting
            helperPID = p.processIdentifier
            return true
        } catch {
            child = nil
            childStdin = nil
            return false
        }
    }

    private func sendLocked(_ command: CameraHelperIPC.Command) {
        guard let handle = childStdin, child?.isRunning == true else { return }
        try? handle.write(contentsOf: CameraHelperIPC.encode(command))
    }

    private func handleLineLocked(_ line: Data) {
        guard let event = CameraHelperIPC.decodeEvent(line) else { return }
        switch event.ev {
        case "hello":
            // Identity binding: the wire pid must be the child we
            // spawned and the schema must match. Anything else is not
            // our helper; it is killed before any of its output is used.
            guard event.version == CameraHelperIPC.protocolVersion,
                  let p = child, event.pid == p.processIdentifier else {
                if let p = child, p.isRunning { kill(p.processIdentifier, SIGKILL) }
                onIncoming(.failed(reason: "hello-mismatch"))
                return
            }
        case "state":
            switch event.state {
            case "running": onIncoming(.running(generation: event.generation))
            case "stopped":
                finishStopLocked(event.running ? false : true)
                onIncoming(.stopped(generation: event.generation, stillRunning: event.running))
            case "failed": onIncoming(.failed(reason: event.reason))
            default: break
            }
        case "log": onIncoming(.log(channel: event.channel, message: event.message))
        case "vision-cancelled": onIncoming(.visionCancelled(token: event.token))
        case "frame": if let f = event.frame { onIncoming(.frame(f)) }
        default: break
        }
    }

    private func childExitedLocked() {
        guard child != nil else { return }
        child = nil
        childStdin = nil
        helperPID = 0
        stopTimer?.cancel(); stopTimer = nil
        killConfirmTimer?.cancel(); killConfirmTimer = nil
        // Process exit releases the camera device: a pending stop
        // completes as off. Consumers learn of the exit separately and
        // HeadTracker decides on the single bounded relaunch.
        finishStopLocked(true)
        onIncoming(.exited)
    }

    private func finishStopLocked(_ off: Bool) {
        let completions = stopCompletions
        stopCompletions = []
        stopTimer?.cancel(); stopTimer = nil
        for c in completions { c(off) }
    }

    private func stopTimedOutLocked() {
        guard let p = child, p.isRunning else { finishStopLocked(true); return }
        // The helper did not report stopped within the deadline. Process
        // exit is the guaranteed camera-off; signal only our own live
        // child pid (QuitChildKiller identity honesty applies).
        onIncoming(.terminatedAfterTimeout)
        kill(p.processIdentifier, SIGKILL)
        let confirm = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if let p = self.child, p.isRunning { self.finishStopLocked(false) }
            // otherwise childExitedLocked already completed the stop as off
        }
        killConfirmTimer = confirm
        queue.asyncAfter(deadline: .now() + 1.0, execute: confirm)
    }
}

// MARK: - Helper-side (child process)

#if canImport(AVFoundation) && canImport(Darwin)
import AVFoundation
import Vision
import CoreML
import CoreMedia
import CoreVideo

/// Bounded event writer: state/log lines are FIFO (capped, oldest log
/// lines dropped under sustained backpressure, never state lines --
/// they are rare), frame events coalesce to the latest one, matching
/// LatestMainFrame's "one pending callback, never a FIFO of old
/// frames". Blocking pipe writes happen only on this queue, so a
/// stalled parent can never wedge capture or Vision behind stdout.
final class CameraHelperSink {
    private let lock = NSLock()
    private var lines: [Data] = []
    private var pendingFrames: [String:Data] = [:]
    private var pendingKinds: [String] = []
    private var draining = false
    private let writeQueue = DispatchQueue(label: "gor.camera-helper.emit", qos: .userInitiated)
    private let out: FileHandle
    init(out: FileHandle) { self.out = out }
    func send(_ event: CameraHelperIPC.Event) {
        let data = CameraHelperIPC.encode(event)
        lock.lock()
        if event.ev == "frame" {
            let kind=event.frame?.delivery ?? "ambient"
            if pendingFrames[kind]==nil {pendingKinds.append(kind)}
            pendingFrames[kind]=data
        }
        else {
            if event.ev == "log", lines.count >= 256 { lines.removeFirst(lines.count - 255) }
            lines.append(data)
        }
        if draining { lock.unlock(); return }
        draining = true
        lock.unlock()
        writeQueue.async { self.drain() }
    }
    private func drain() {
        while true {
            lock.lock()
            let line: Data?
            if !lines.isEmpty { line = lines.removeFirst() }
            else if !pendingKinds.isEmpty {line=pendingFrames.removeValue(forKey:pendingKinds.removeFirst())}
            else {line=nil}
            if line == nil { draining = false; lock.unlock(); return }
            lock.unlock()
            if let line { try? out.write(contentsOf: line) }
        }
    }
}

// Capture-free inference boundary. Raw BGRA bytes travel losslessly over owned pipes.
// A head worker and a landmark worker have independent single slots and deadlines.
private final class CameraVisionDeadline {
    private let lock=NSLock()
    private var active=true,expired=false
    init(_ request:VNRequest) {
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+1) { [self] in
            lock.lock();let cancel=active;if cancel {active=false;expired=true};lock.unlock()
            if cancel {request.cancel()}
        }
    }
    func finish()->Bool {lock.lock();defer{lock.unlock()};active=false;return !expired}
}
private struct CameraVisionPacket: Codable {
    var frame: CameraHelperIPC.Frame
    var kind: String
    var stride: Int
    var bytes: Int
}

private enum CameraVisionWire {
    static func read(_ handle: FileHandle, count: Int) throws -> Data {
        guard count >= 0 else { throw CocoaError(.fileReadUnknown) }
        var data=Data()
        while data.count<count {
            guard let part=try handle.read(upToCount:count-data.count), !part.isEmpty else { throw CocoaError(.fileReadUnknown) }
            data.append(part)
        }
        return data
    }
    static func line(_ handle: FileHandle) throws -> Data {
        var data=Data()
        while data.count<CameraHelperIPC.maxLineBytes {
            let next=try read(handle,count:1)
            if next.first==10 {return data}
            data.append(next)
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}

private final class CameraVisionWorkerClient {
    private let lock=NSLock()
    private var child:Process?, input:FileHandle?, output:FileHandle?
    private var requestID:UInt64=0,activeID:UInt64?,expired=false
    private var generation:UInt64=0,failures=0
    private let kind:String
    init(kind:String) {self.kind=kind}
    func stop() {
        lock.lock();activeID=nil;requestID &+= 1
        let p=child;child=nil;input=nil;output=nil;lock.unlock()
        if let p,p.isRunning {kill(p.processIdentifier,SIGKILL)}
    }
    private func spawn() throws {
        lock.lock();if child?.isRunning==true {lock.unlock();return};lock.unlock()
        let p=Process(),i=Pipe(),o=Pipe()
        p.executableURL=Bundle.main.executableURL
        p.arguments=[CameraVisionWorkerCLI.flag,PrepareProcessLifetime.ownerFlag,String(getpid())]
        p.standardInput=i;p.standardOutput=o;p.standardError=FileHandle.standardError
        try p.run();QuitChildKiller.shared.register(p)
        lock.lock();child=p;input=i.fileHandleForWriting;output=o.fileHandleForReading;lock.unlock()
        // A worker's handshake binds its response stream to this exact child.
        let hello=try JSONDecoder().decode(CameraHelperIPC.Event.self,from:CameraVisionWire.line(o.fileHandleForReading))
        guard hello.ev=="hello",hello.pid==p.processIdentifier,hello.version==CameraHelperIPC.protocolVersion else {throw CocoaError(.fileReadCorruptFile)}
    }
    func infer(_ pixels:CVPixelBuffer,frame:CameraHelperIPC.Frame,log:@escaping(String)->Void) -> CameraHelperIPC.Frame? {
        // Exactly one caller owns each client slot; stop may invalidate it concurrently.
        lock.lock()
        if generation != frame.generation {generation=frame.generation;failures=0}
        guard failures<2 else {lock.unlock();return nil}
        requestID &+= 1;let token=requestID;activeID=token;expired=false
        lock.unlock()
        let deadline=DispatchWorkItem { [self] in
            lock.lock();let timeout=activeID==token
            if timeout {expired=true}
            let p=child;lock.unlock()
            guard timeout else {return}
            log("VISION-WORKER timeout kind=\(kind) generation=\(frame.generation) request=\(token) recovery=sample-owned-worker-then-retire")
            if let p {self.sampleAndRetire(p,token:token,log:log)}
        }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+1,execute:deadline)
        do {
            // The timeout covers spawn, handshake, input backpressure and inference.
            try spawn()
            lock.lock()
            guard activeID==token,!expired,let i=input,let o=output else {lock.unlock();throw CocoaError(.fileReadUnknown)}
            lock.unlock()
            let stride=CVPixelBufferGetBytesPerRow(pixels),height=CVPixelBufferGetHeight(pixels)
            guard stride>0,height>0,stride*height<=32*1024*1024 else {throw CocoaError(.fileReadCorruptFile)}
            let packet=CameraVisionPacket(frame:frame,kind:kind,stride:stride,bytes:stride*height)
            CVPixelBufferLockBaseAddress(pixels,.readOnly)
            guard let base=CVPixelBufferGetBaseAddress(pixels) else {CVPixelBufferUnlockBaseAddress(pixels,.readOnly);throw CocoaError(.fileReadUnknown)}
            let data=Data(bytes:base,count:packet.bytes)
            CVPixelBufferUnlockBaseAddress(pixels,.readOnly)
            try i.write(contentsOf:CameraHelperIPC.encode(packet));try i.write(contentsOf:data)
            while true {
                let event=try JSONDecoder().decode(CameraHelperIPC.Event.self,from:CameraVisionWire.line(o))
                if event.ev=="log" {log(event.message);continue}
                guard event.ev=="frame",let result=event.frame,result.generation==frame.generation,result.now==frame.now,result.delivery==kind else {throw CocoaError(.fileReadCorruptFile)}
                lock.lock();let accepted=activeID==token && !expired
                lock.unlock()
                guard accepted,result.processed,!result.visionFailed else {throw CocoaError(.userCancelled)}
                lock.lock();if activeID==token {activeID=nil};lock.unlock();deadline.cancel()
                return result
            }
        } catch {
            lock.lock();if activeID==token {activeID=nil};failures+=1
            let p=child;child=nil;input=nil;output=nil;lock.unlock();deadline.cancel()
            if let p,p.isRunning {kill(p.processIdentifier,SIGKILL)}
            log("VISION-WORKER failed kind=\(kind) generation=\(frame.generation) failures=\(failures) error=\((error as NSError).code)")
            return nil
        }
    }
    private func sampleAndRetire(_ p:Process,token:UInt64,log:@escaping(String)->Void) {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("gor-vision-worker-"+UUID().uuidString)
        let file=folder.appendingPathComponent("sample.txt")
        try? FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer {try? FileManager.default.removeItem(at:folder)}
        let sampler=Process();sampler.executableURL=URL(fileURLWithPath:"/usr/bin/sample")
        sampler.arguments=[String(p.processIdentifier),"2","-file",file.path]
        sampler.standardOutput=FileHandle.nullDevice;sampler.standardError=FileHandle.nullDevice
        do {
            try sampler.run()
            DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+4) {if sampler.isRunning {kill(sampler.processIdentifier,SIGKILL)}}
            sampler.waitUntilExit()
            if let h=try? FileHandle(forReadingFrom:file) {
                let data=(try? h.read(upToCount:1024*1024)) ?? Data();try? h.close()
                let receipt="VISION-WORKER sample kind=\(kind) pid=\(p.processIdentifier) request=\(token) bytes=\(data.count)"
                log(receipt)
                _=BoundedDiskWriter.append(Data((receipt+"\n").utf8)+data,to:URL(fileURLWithPath:StagedRunPaths.tmp("/tmp/gor_camera_helper_sample.txt")),cap:16*1024*1024)
            }
        } catch {log("VISION-WORKER sample-unavailable kind=\(kind)")}
        lock.lock();let retire=activeID==token && expired && child===p;lock.unlock()
        if retire,p.isRunning {kill(p.processIdentifier,SIGKILL)}
    }
}

// No AVCaptureSession, AVCaptureDevice or CameraHelperEngine instance is created here.
enum CameraVisionWorkerCLI {
    static let flag="--camera-vision-worker"
    private static func cpu(_ request:VNRequest) throws {
        if #available(macOS 14.0,*) {
            let stages=try request.supportedComputeStageDevices
            guard !stages.isEmpty else {throw CocoaError(.featureUnsupported)}
            for (stage,devices) in stages {
                guard let cpu=devices.first(where:{if case .cpu = $0 {return true};return false}) else {throw CocoaError(.featureUnsupported)}
                request.setComputeDevice(cpu,for:stage)
            }
        } else {request.usesCPUOnly=true}
    }
    static func cli(arguments:[String])->Int32? {
        guard arguments.contains(flag) else {return nil}
        PrepareProcessLifetime.watchOwner(arguments:arguments)
        let sink=CameraHelperSink(out:FileHandle.standardOutput)
        sink.send(CameraHelperIPC.Event(ev:"hello",version:CameraHelperIPC.protocolVersion,pid:getpid()))
        let input=FileHandle.standardInput
        while true {
            do {
                let packet=try JSONDecoder().decode(CameraVisionPacket.self,from:CameraVisionWire.line(input))
                let w=packet.frame.pixelWidth,h=packet.frame.pixelHeight
                guard w>0,w<=8192,h>0,h<=8192,packet.stride>=w*4,packet.bytes==packet.stride*h,packet.bytes<=32*1024*1024,["head","blink","ambient"].contains(packet.kind) else {return 4}
                let data=try CameraVisionWire.read(input,count:packet.bytes)
                var buffer:CVPixelBuffer?
                guard CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_32BGRA,nil,&buffer)==kCVReturnSuccess,let pixels=buffer else {return 4}
                CVPixelBufferLockBaseAddress(pixels,[])
                let stride=CVPixelBufferGetBytesPerRow(pixels)
                guard let base=CVPixelBufferGetBaseAddress(pixels) else {return 4}
                data.withUnsafeBytes {raw in
                    for y in 0..<h {memcpy(base.advanced(by:y*stride),raw.baseAddress!.advanced(by:y*packet.stride),w*4)}
                }
                CVPixelBufferUnlockBaseAddress(pixels,[])
                var frame=packet.frame;frame.delivery=packet.kind
                frame.visionToken=0
                // Landmark observations can omit pitch. Measure the same frame's
                // rectangle pose separately; never fill missing landmark angles.
                if packet.kind=="blink" {
                    let pose=VNDetectFaceRectanglesRequest();try cpu(pose)
                    let poseDeadline=CameraVisionDeadline(pose)
                    do {try VNImageRequestHandler(cvPixelBuffer:pixels,orientation:.up,options:[:]).perform([pose])} catch {frame.visionFailed=true}
                    guard poseDeadline.finish() else {return 5}
                    if let face=pose.results?.first {frame.rect=CameraHelperEngine.faceRect(face,count:pose.results?.count ?? 0)}
                }
                let request:VNImageBasedRequest=packet.kind=="ambient" ? VNDetectFaceRectanglesRequest() : (packet.kind=="head" ? VNDetectFaceRectanglesRequest():VNDetectFaceLandmarksRequest())
                try cpu(request)
                sink.send(CameraHelperIPC.Event(ev:"log",channel:"media",message:"VISION-WORKER start kind=\(packet.kind) pid=\(getpid()) capture_session=false revision=\(request.revision) configured=cpu-all-stages executed_device=not-exposed"))
                let started=CACurrentMediaTime(),watchdog=CameraVisionDeadline(request)
                do {try VNImageRequestHandler(cvPixelBuffer:pixels,orientation:.up,options:[:]).perform([request])} catch {frame.visionFailed=true}
                let accepted=watchdog.finish()
                frame.visionMS=(CACurrentMediaTime()-started)*1000;frame.processed=accepted
                if !accepted {frame.visionFailed=true}
                if accepted,let r=request as? VNDetectFaceRectanglesRequest,let face=r.results?.first {
                    frame.rect=CameraHelperEngine.faceRect(face,count:r.results?.count ?? 0)
                    frame.lumaRectFace=HeadTracker.averageLumaTwoRegion(of:pixels,faceBox:face.boundingBox).map{CameraHelperIPC.Luma2(face:$0.faceLuma,room:$0.roomLuma,combined:$0.combined)}
                }
                if accepted,let r=request as? VNDetectFaceLandmarksRequest,let face=r.results?.first {
                    frame.landmarks=CameraHelperEngine.faceLandmarks(face,count:r.results?.count ?? 0)
                    frame.lumaLandmarkFace=HeadTracker.averageLumaTwoRegion(of:pixels,faceBox:face.boundingBox).map{CameraHelperIPC.Luma2(face:$0.faceLuma,room:$0.roomLuma,combined:$0.combined)}
                    frame.quality=CameraHelperEngine.measureQuality(pixels,frame:frame)
                }
                sink.send(CameraHelperIPC.Event(ev:"log",channel:"media",message:"VISION-WORKER end kind=\(packet.kind) pid=\(getpid()) elapsed_ms=\(frame.visionMS) accepted=\(accepted) failed=\(frame.visionFailed)"))
                sink.send(CameraHelperIPC.Event(ev:"frame",frame:frame))
            } catch {return 0}
        }
    }
}

/// The capture engine that used to live inside HeadTracker, now owning
/// the camera in the child. Behavior is the in-process code's: same
/// session configuration, same throttle, same AE/AWB settle gate, same
/// single-slot Vision admission, same requests and revisions. Where the
/// old code wrote Diag lines directly it now emits log events; where it
/// ran downstream math it now emits typed frame events.
final class CameraHelperEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let sink: CameraHelperSink
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "gor.camera-helper.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "gor.camera-helper.frame", qos: .utility)
    private let visionQueue = DispatchQueue(label: "gor.camera-helper.vision", qos: .userInitiated)
    private let ambientVisionQueue = DispatchQueue(label: "gor.camera-helper.ambient", qos: .utility)
    private let blinkVisionQueue = DispatchQueue(label: "gor.camera-helper.blink-worker", qos: .userInitiated)
    private let headWorker=CameraVisionWorkerClient(kind:"head")
    private let blinkWorker=CameraVisionWorkerClient(kind:"blink")
    private let ambientWorker=CameraVisionWorkerClient(kind:"ambient")
    private var blinkVisionInFlight=false
    // 196v heat: counts frames admitted past the frameInterval floor so the blink
    // slot can drop to a 1-in-5 sub-cadence under thermal pressure (see below).
    private var blinkAdmissionCounter: UInt64=0
    // Legacy in-helper head path below remains for characterization while the
    // capture-free worker replaces it. process() routes all nonambient frames
    // to independent workers before reaching it. C5 ambient now returns through its own worker too.
    // Head-path requests are built fresh per frame (arch-196b C2): a
    // request the watchdog cancelled is never reused. The ambient-only
    // request stays shared, exactly as the in-process code kept it.
    private func makeFaceRequest() -> VNDetectFaceRectanglesRequest {
        let r = VNDetectFaceRectanglesRequest()
        // Match the standalone CPU probe that returns on the owner's Mac.
        // The old explicit revision3 was not the revision policy tested by E1.
        return r
    }
    private func makeBlinkRequest() -> VNDetectFaceLandmarksRequest {
        let r = VNDetectFaceLandmarksRequest()
        return r
    }
    private let ambientFaceRequest: VNDetectFaceRectanglesRequest = {
        let r = VNDetectFaceRectanglesRequest()
        r.revision = VNDetectFaceRectanglesRequestRevision3
        return r
    }()

    // MARK: - bounded CPU Vision watchdog (arch-196b C2, ported from HeadTracker)
    private let visionEpochLock = NSLock()
    private var visionEpoch: UInt64 = 0
    private var activeVisionEpoch: UInt64?
    private func visionEpochIsCurrent(_ epoch: UInt64) -> Bool {
        visionEpochLock.lock(); defer { visionEpochLock.unlock() }; return visionEpoch == epoch
    }
    /// Cancel once on expiry, reject the expired result, then sample the helper.
    /// Retire only if the same perform is still stuck after sampling.
    private func beginVisionWatchdog(_ requests: [VNRequest]) -> UInt64 {
        visionEpochLock.lock(); visionEpoch &+= 1; let epoch = visionEpoch; activeVisionEpoch = epoch; visionEpochLock.unlock()
        let started = CACurrentMediaTime()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now()+1) { [weak self] in
            guard let self else { return }; self.visionEpochLock.lock()
            let expired = self.activeVisionEpoch == epoch && self.visionEpoch == epoch
            if expired { self.visionEpoch &+= 1 }
            self.visionEpochLock.unlock(); guard expired else { return }
            for request in requests { request.cancel() }
            self.sink.send(CameraHelperIPC.Event(ev: "vision-cancelled", token: epoch))
            self.mediaLog("HEAD-CAPTURE vision busy watchdog elapsed_s=\(CACurrentMediaTime()-started) cancel_once=true recovery=sample-then-bounded-process-exit")
            self.sampleHungVision(epoch: epoch)
        }
        return epoch }
    /// The active helper samples ITSELF before retiring the stuck process.
    /// Parent already limits unexpected-exit relaunch to one per consumer generation.
    private func sampleHungVision(epoch: UInt64) {
        let generation = snapshot().generation
        DispatchQueue.global(qos: .utility).async {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("gor-camera-sample-" + UUID().uuidString, isDirectory: true)
            let output = folder.appendingPathComponent("sample.txt")
            var receipt = "CAMERA-HELPER sample pid=\(getpid()) generation=\(generation) epoch=\(epoch)"
            var data = Data()
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                defer { try? FileManager.default.removeItem(at: folder) }
                let sampler = Process()
                sampler.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                sampler.arguments = [String(getpid()), "2", "-file", output.path]
                sampler.standardOutput = FileHandle.nullDevice; sampler.standardError = FileHandle.nullDevice
                try sampler.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now()+4) {
                    if sampler.isRunning { kill(sampler.processIdentifier, SIGKILL) }
                }
                sampler.waitUntilExit()
                if sampler.terminationStatus == 0 {
                    let file = try FileHandle(forReadingFrom: output); defer { try? file.close() }
                    data = try file.read(upToCount: 1024*1024) ?? Data()
                    receipt += " result=sampled bytes=\(data.count)"
                } else { receipt += " result=sample-failed status=\(sampler.terminationStatus)" }
            } catch { receipt += " result=sample-unavailable" }
            self.mediaLog(receipt)
            let record = Data((receipt+"\n").utf8)+data+Data("\n".utf8)
            _ = BoundedDiskWriter.append(record, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_camera_helper_sample.txt")), cap: 16*1024*1024)
            // End/stop may have won during sampling. Never retire a healthy/new epoch.
            self.visionEpochLock.lock()
            let stillHung = self.activeVisionEpoch == epoch
            self.visionEpochLock.unlock()
            let current = self.snapshot()
            if stillHung && generation > 0 && current.generation == generation && !current.ambientOnly && (current.headPose || current.blink) {
                exit(75)
            }
        }
    }
    private func endVisionWatchdog(_ epoch: UInt64) {
        visionEpochLock.lock(); if activeVisionEpoch == epoch { activeVisionEpoch = nil }; visionEpochLock.unlock() }
    /// CPU-only compute selection: every stage must offer a CPU device,
    /// otherwise the frame is skipped rather than falling back to the
    /// ANE (the in-process guard, unchanged).
    private func selectVisionCPU(_ request: VNRequest) -> Bool {
        if #available(macOS 14.0, *) {
            do {
                let stages = try request.supportedComputeStageDevices; guard !stages.isEmpty else { return false }
                for (stage, devices) in stages {
                    guard let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) else {
                        mediaLog("VISION-CPU unsupported type=\(type(of:request)) stage=\(stage); no ANE fallback"); return false }
                    request.setComputeDevice(cpu, for: stage)
                }
            } catch { mediaLog("VISION-CPU supported-query-error=\((error as NSError).code)"); return false }
        } else { request.usesCPUOnly = true }
        return true }
    private var configured = false
    private var device: AVCaptureDevice?
    private var visionInFlight = false
    private var ambientVisionInFlight = false
    private var busyReceiptAt: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval = 0
    private var ambientConsecutiveSettledFrames = 0
    private var ambientHasSeenFirstSettledFrame = false
    private var ambientDiagLastIsSettled: Bool?
    private var ambientDiagRawFrameCount = 0
    private var ambientDiagLastRawLogTime: CFTimeInterval = 0
    private static let ambientSettleFramesRequired = 3
    private static let ambientOnlyMinFrameInterval: CFTimeInterval = 1.0 / 2.0
    private static let ambientPreSettleMinFrameInterval: CFTimeInterval = 1.0 / 10.0
    private var visionDiagID: UInt64 = 0

    /// Current consumer configuration, lock-protected like the old
    /// lifecycleSnapshot; written by sessionQueue (command handling),
    /// read by frameQueue (capture callbacks).
    private let configLock = NSLock()
    private var config = CameraHelperIPC.Command(cmd: "configure")

    init(sink: CameraHelperSink) { self.sink = sink }

    private func snapshot() -> CameraHelperIPC.Command {
        configLock.lock(); defer { configLock.unlock() }
        return config
    }
    private func mediaLog(_ message: String) { sink.send(CameraHelperIPC.Event(ev: "log", channel: "media", message: message)) }
    private func diagLog(_ message: String) { sink.send(CameraHelperIPC.Event(ev: "log", channel: "diag", message: message)) }

    private var commandSplitter = CameraHelperIPC.LineSplitter()

    /// All command handling is serialized on sessionQueue, so stop and a
    /// following configure are applied in wire order: a stop that was
    /// mid-flight when a new consumer arrived finishes first, then the
    /// session starts again (the Z2 stop/start/stop ordering).
    private func apply(_ command: CameraHelperIPC.Command) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        do {
            switch command.cmd {
            case "configure":
                self.configLock.lock(); self.config = command; self.configLock.unlock()
                self.startIfNeeded()
            case "reset-settling":
                self.configLock.lock(); self.config.window = command.window; self.config.generation = command.generation; self.configLock.unlock()
                self.frameQueue.async {
                    self.ambientConsecutiveSettledFrames = 0
                    self.ambientHasSeenFirstSettledFrame = false
                    self.ambientDiagLastIsSettled = nil
                    self.ambientDiagRawFrameCount = 0
                    self.ambientDiagLastRawLogTime = 0
                }
            case "blink-boost":
                self.configLock.lock(); self.config.blinkBoostUntil = command.blinkBoostUntil; self.configLock.unlock()
            case "stop":
                self.configLock.lock(); self.config.generation=command.generation; self.config.headPose=false; self.config.blink=false; self.configLock.unlock()
                self.stopSessionLocked(generation: command.generation)
            case "shutdown":
                self.stopSessionLocked(generation: command.generation) { exit(0) }
                if !self.session.isRunning { exit(0) }
            default: break
            }
        }
    }

    private func startIfNeeded() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let snap = snapshot()
        guard snap.generation > 0, !session.isRunning else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            sink.send(CameraHelperIPC.Event(ev: "state", state: "failed", generation: snap.generation, reason: "unauthorized"))
            return
        }
        let ready = configureSessionIfNeeded()
        if ready {
            videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
            mediaLog("HEAD-CAPTURE event=delegate generation=\(snap.generation) attached=true")
            configureCameraEffects()
            recordCameraEffects(phase: "before-start", generation: snap.generation)
            session.startRunning()
            recordCameraEffects(phase: "after-start", generation: snap.generation)
        }
        let running = ready && session.isRunning
        mediaLog("HEAD-CAPTURE event=hardware-started running=\(running) generation=\(snap.generation)")
        sink.send(CameraHelperIPC.Event(ev: "state", state: running ? "running" : "failed", generation: snap.generation, reason: running ? "" : "start-failed"))
    }

    // H2 probe: system effects may share Vision resources. This is not a proven hang cure.
    private func configureCameraEffects() {
        if #available(macOS 12.3, *) {
            AVCaptureDevice.centerStageControlMode = .app
            AVCaptureDevice.isCenterStageEnabled = false
        }
    }
    private func recordCameraEffects(phase: String, generation: UInt64) {
        var state = "HEAD-CAPTURE event=camera-effects hypothesis=H2 phase=\(phase) generation=\(generation)"
        if #available(macOS 12.3, *), let device {
            state += " isCenterStageActive=\(device.isCenterStageActive)"
        }
        if #available(macOS 12.0, *), let device { state += " isPortraitEffectActive=\(device.isPortraitEffectActive)" }
        if #available(macOS 13.0, *), let device { state += " isStudioLightActive=\(device.isStudioLightActive)" }
        if #available(macOS 14.0, *), let device {
            state += " reactionEffectsEnabled=\(AVCaptureDevice.reactionEffectsEnabled) canPerformReactionEffects=\(device.canPerformReactionEffects) reactionEffectGesturesEnabled=\(AVCaptureDevice.reactionEffectGesturesEnabled)"
        }
        mediaLog(state)
    }

    private static let stopReturnBudget: TimeInterval = 1.2

    private func stopSessionLocked(generation: UInt64, after: (() -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        headWorker.stop();blinkWorker.stop();ambientWorker.stop()
        mediaLog("HEAD-CAPTURE event=delegate generation=\(generation) attached=false")
        // A missing completion does not identify an Apple-stack wait site.
        // Bound this call below the parent's 2 s stop deadline regardless.
        // sessionQueue waits here, preserving stop/configure wire order.
        // Only the detached stop thread touches the session during this wait.
        let stopReturned = DispatchSemaphore(value: 0)
        Thread.detachNewThread { [session] in
            session.stopRunning()
            stopReturned.signal()
        }
        if stopReturned.wait(timeout: .now() + Self.stopReturnBudget) == .timedOut {
            mediaLog("HEAD-CAPTURE event=hardware-stop-timeout elapsed_s=\(Self.stopReturnBudget) generation=\(generation) recovery=bounded-self-exit")
            // Best effort log drain, not a hardware-off acknowledgment.
            // The parent reports off only after observing child exit.
            Thread.sleep(forTimeInterval: 0.05)
            after?()
            exit(0)
        }
        let running = session.isRunning
        mediaLog("HEAD-CAPTURE event=hardware-stopped running=\(running) stopped=\(!running) generation=\(generation)")
        sink.send(CameraHelperIPC.Event(ev: "state", state: "stopped", generation: generation, running: running))
        after?()
    }

    /// Same body as the in-process configureSessionIfNeeded: partial
    /// input installation is rolled back so a retry never duplicates.
    private func configureSessionIfNeeded() -> Bool {
        guard !configured else { return true }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .medium
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 && $0.minFrameRate <= 30 }) {
            do { try device.lockForConfiguration(); device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30); device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30); device.unlockForConfiguration() }
            catch { }
        }
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(videoOutput) else {
            session.removeInput(input)
            return false
        }
        session.addOutput(videoOutput)
        // Upright, unmirrored pixels for Vision; anatomical eye names.
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = false
        }
        self.device = device
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        mediaLog("VISION-DIAG camera type=\(device.deviceType.rawValue) model=\(device.modelID) format=\(dimensions.width)x\(dimensions.height)")
        configured = true
        return true
    }

    /// Vision perform with the same start/end receipt shape as
    /// VisionRequestDiag, relayed instead of written directly (the
    /// helper never writes the parent's log files).
    private func perform(_ handler: VNImageRequestHandler, _ requests: [VNRequest], label: String) throws {
        configLock.lock(); visionDiagID &+= 1; let id = visionDiagID; configLock.unlock()
        let started = CACurrentMediaTime()
        for request in requests {
            mediaLog("VISION-DIAG request label=\(label) type=\(type(of:request)) revision=\(request.revision) configured=cpu-all-stages executed_device=not-exposed")
        }
        mediaLog("VISION-DIAG start id=\(id) label=\(label) uptime=\(started) count=\(requests.count)")
        var result = "ok"
        defer { mediaLog("VISION-DIAG end id=\(id) label=\(label) uptime=\(CACurrentMediaTime()) elapsed_s=\(CACurrentMediaTime() - started) result=\(result)") }
        do { try handler.perform(requests) }
        catch { result = "error-\((error as NSError).domain)-\((error as NSError).code)"; throw error }
    }

    private static func pointList(_ region: VNFaceLandmarkRegion2D?) -> [[Double]]? {
        guard let region, region.pointCount > 0 else { return nil }
        return region.normalizedPoints.map { [Double($0.x), Double($0.y)] }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let snap = snapshot()
        guard snap.generation > 0 else { return }
        let now = CACurrentMediaTime()
        if snap.ambientOnly {
            ambientDiagRawFrameCount += 1
            if now - ambientDiagLastRawLogTime >= 1.0 {
                let elapsed = ambientDiagLastRawLogTime == 0 ? 1.0 : (now - ambientDiagLastRawLogTime)
                diagLog("[AmbientDiag] raw captureOutput calls in last \(String(format: "%.2f", elapsed))s: \(ambientDiagRawFrameCount) t=\(String(format: "%.2f", now))")
                ambientDiagRawFrameCount = 0
                ambientDiagLastRawLogTime = now
            }
        }
        // Same throttle as the in-process code: ~30fps head rate (owner
        // knob gorHeadTrackFPS), 2 Hz ambient post-settle, 10 Hz pre-settle.
        let frameInterval: CFTimeInterval
        if snap.ambientOnly {
            frameInterval = ambientHasSeenFirstSettledFrame
                ? Self.ambientOnlyMinFrameInterval
                : Self.ambientPreSettleMinFrameInterval
        } else {
            frameInterval = HeatTelemetry.headTrackInterval
        }
        guard now - lastFrameTime >= frameInterval else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = now

        // Exposure before Vision admission: a hung classifier cannot
        // prevent the deadline from reaching three real settled frames.
        let isSettled = (device.map { !$0.isAdjustingExposure && !$0.isAdjustingWhiteBalance } ?? true)
        if ambientDiagLastIsSettled != isSettled {
            mediaLog("AMBIENT-SETTLE transition -> isSettled=\(isSettled) consecutiveBefore=\(ambientConsecutiveSettledFrames) hadSeenFirst=\(ambientHasSeenFirstSettledFrame) t=\(String(format: "%.2f", CACurrentMediaTime()))")
            ambientDiagLastIsSettled = isSettled
        }
        if isSettled {
            ambientConsecutiveSettledFrames += 1
            if ambientConsecutiveSettledFrames <= Self.ambientSettleFramesRequired {
                mediaLog("AMBIENT-SETTLE frame=\(ambientConsecutiveSettledFrames) generation=\(snap.generation)")
            }
            ambientHasSeenFirstSettledFrame = true
        } else {
            ambientConsecutiveSettledFrames = 0
            ambientHasSeenFirstSettledFrame = false
        }
        let ambientSettled = ambientConsecutiveSettledFrames >= Self.ambientSettleFramesRequired
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        let host = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
        let age = pts.isFinite && host.isFinite ? max(0, host - pts) : 0
        var frame = CameraHelperIPC.Frame(
            generation: snap.generation, window: snap.window, now: now,
            pts: pts.isFinite ? pts : -1, age: pts.isFinite && host.isFinite ? age : -1,
            pixelWidth: CVPixelBufferGetWidth(pixelBuffer), pixelHeight: CVPixelBufferGetHeight(pixelBuffer),
            ambientOnly: snap.ambientOnly, settled: isSettled,
            consecutiveSettled: ambientConsecutiveSettledFrames,
            seenFirstSettled: ambientHasSeenFirstSettledFrame,
            ambientSettled: ambientSettled,
            processed: false, visionFailed: false, visionMS: 0,
            exposureChanging: device.map { ($0.isAdjustingExposure || $0.isAdjustingWhiteBalance) ? 1.0 : 0.0 } ?? -1)
        if ambientSettled { frame.lumaFull = HeadTracker.averageLumaSingleRegion(of: pixelBuffer) }

        // Independent landmark slot: a blocked blink worker cannot occupy the head slot.
        // 196v heat: under thermal pressure admit the blink pass on every 5th
        // gated frame (about 2 Hz at the 10 fps thermal floor) while the
        // head/pose cadence is untouched. A cool machine admits every frame
        // exactly as before. 197i correction: the double-blink seek IS fed
        // from this pass (the 196v note here claimed no command was bound -
        // stale), so at 2 Hz the shipped detector gates cancelled on every
        // sample; the parent's cadence layer plus the blink-boost escalation
        // below restore the gesture without re-adding the chronic blink load.
        blinkAdmissionCounter &+= 1
        // 197i boost: while the parent's gesture detector reports an episode
        // in flight (blink-boost command), admit every frame so the episode
        // resolves at full cadence; bounded by the detector's own deadline.
        let blinkBoosted = (snap.blinkBoostUntil ?? 0) > now
        let blinkThermalAdmit = !HeatTelemetry.thermalPressureCached || blinkAdmissionCounter % 5 == 0 || blinkBoosted
        if !snap.ambientOnly,snap.blink,blinkThermalAdmit,!blinkVisionInFlight {
            blinkVisionInFlight=true
            let captured=frame
            blinkVisionQueue.async {
                defer {self.frameQueue.async {self.blinkVisionInFlight=false}}
                guard self.snapshot().generation==captured.generation else {return}
                var result=self.blinkWorker.infer(pixelBuffer,frame:captured,log:self.mediaLog)
                if result==nil {var failed=captured;failed.delivery="blink";failed.processed=true;failed.visionFailed=true;result=failed}
                guard self.snapshot().generation==captured.generation,let result else {return}
                self.sink.send(CameraHelperIPC.Event(ev:"frame",frame:result))
            }
        }

        // Single-slot admission, one slot per mode as in the in-process
        // code. A busy slot emits the minimal tick (scalar + settle only)
        // so the parent's fallback deadline and settle gate keep moving
        // while a Vision call is hung.
        guard !(snap.ambientOnly ? ambientVisionInFlight : visionInFlight) else {
            if now - busyReceiptAt >= 1 {
                busyReceiptAt = now
                mediaLog("HEAD-CAPTURE vision busy generation=\(snap.generation)")
            }
            if frame.lumaFull != nil || !snap.ambientOnly { sink.send(CameraHelperIPC.Event(ev: "frame", frame: frame)) }
            return
        }
        if snap.ambientOnly { ambientVisionInFlight = true } else { visionInFlight = true }
        let executor = snap.ambientOnly ? ambientVisionQueue : visionQueue
        executor.async {
            defer { self.frameQueue.async {
                if snap.ambientOnly { self.ambientVisionInFlight = false } else { self.visionInFlight = false }
            } }
            let current = self.snapshot()
            guard current.generation == snap.generation, current.generation > 0 else { return }
            self.process(pixelBuffer, into: frame, blink: current.blink)
        }
    }

    private func process(_ pixelBuffer: CVPixelBuffer, into frame: CameraHelperIPC.Frame, blink: Bool) {
        var frame = frame
        if !frame.ambientOnly {
            guard let result=headWorker.infer(pixelBuffer,frame:frame,log:mediaLog),snapshot().generation==frame.generation else {return}
            sink.send(CameraHelperIPC.Event(ev:"frame",frame:result))
            return
        }
        // C5: ambient has its own capture-free CPU slot. Preserve the same
        // settle/window cadence and scalar fallback while face/room acceptance is pending.
        if frame.ambientOnly {
            guard let result=ambientWorker.infer(pixelBuffer,frame:frame,log:mediaLog),snapshot().generation==frame.generation else {return}
            sink.send(CameraHelperIPC.Event(ev:"frame",frame:result))
            return
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        let started = CACurrentMediaTime()
        if frame.ambientOnly {
            // C2: CPU selection on the shared ambient request; no
            // watchdog here, same as the in-process processAmbientFrame.
            guard selectVisionCPU(ambientFaceRequest) else { return }
            do {
                try perform(handler, [ambientFaceRequest], label: "ambient-rectangles")
                if let face = ambientFaceRequest.results?.first as? VNFaceObservation {
                    frame.rect = Self.faceRect(face, count: ambientFaceRequest.results?.count ?? 0)
                    frame.lumaRectFace = HeadTracker.averageLumaTwoRegion(of: pixelBuffer, faceBox: face.boundingBox).map { CameraHelperIPC.Luma2(face: $0.faceLuma, room: $0.roomLuma, combined: $0.combined) }
                }
            } catch { frame.visionFailed = true }
        } else {
            let blinkRequest = makeBlinkRequest(), faceRequest = makeFaceRequest()
            guard selectVisionCPU(faceRequest), selectVisionCPU(blinkRequest) else { return }
            let visionToken = beginVisionWatchdog([blinkRequest, faceRequest])
            defer { endVisionWatchdog(visionToken) }
            frame.visionToken = visionToken
            do {
                // Separate CPU requests match E1, not a combined revision3 graph.
                try perform(handler, [faceRequest], label: "head-pose-cpu-default-revision")
                guard visionEpochIsCurrent(visionToken) else { return }
                try perform(handler, [blinkRequest], label: "blink-cpu-default-revision")
                // C2 token gate: a watchdog-expired perform delivers
                // nothing - the frame is dropped instead of sent.
                guard visionEpochIsCurrent(visionToken) else { return }
                frame.rect = (faceRequest.results?.first as? VNFaceObservation).map { Self.faceRect($0, count: faceRequest.results?.count ?? 0) }
                if let face = blinkRequest.results?.first as? VNFaceObservation {
                    frame.landmarks = Self.faceLandmarks(face, count: blinkRequest.results?.count ?? 0)
                    frame.lumaLandmarkFace = HeadTracker.averageLumaTwoRegion(of: pixelBuffer, faceBox: face.boundingBox).map { CameraHelperIPC.Luma2(face: $0.faceLuma, room: $0.roomLuma, combined: $0.combined) }
                }
                // Same selected-face rule as the parent: the landmark
                // box only when all three pose angles exist, else the
                // rectangle detection's box.
                let selectedBox: [Double]?
                if let lm = frame.landmarks, lm.yaw != nil, lm.pitch != nil, lm.roll != nil { selectedBox = lm.box }
                else { selectedBox = frame.rect?.box }
                if let box = selectedBox {
                    frame.lumaRectFace = HeadTracker.averageLumaTwoRegion(of: pixelBuffer, faceBox: CGRect(x: box[0], y: box[1], width: box[2], height: box[3])).map { CameraHelperIPC.Luma2(face: $0.faceLuma, room: $0.roomLuma, combined: $0.combined) }
                }
                frame.quality = Self.measureQuality(pixelBuffer, frame: frame)
            } catch { frame.visionFailed = true }
        }
        frame.lumaFull = frame.lumaFull ?? HeadTracker.averageLumaSingleRegion(of: pixelBuffer)
        frame.visionMS = (CACurrentMediaTime() - started) * 1000
        frame.processed = true
        sink.send(CameraHelperIPC.Event(ev: "frame", frame: frame))
    }

    fileprivate static func faceRect(_ face: VNFaceObservation, count: Int) -> CameraHelperIPC.FaceRect {
        CameraHelperIPC.FaceRect(box: [Double(face.boundingBox.minX), Double(face.boundingBox.minY), Double(face.boundingBox.width), Double(face.boundingBox.height)],
                                 yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue, roll: face.roll?.doubleValue,
                                 confidence: Double(face.confidence), faceCount: count)
    }
    fileprivate static func faceLandmarks(_ face: VNFaceObservation, count: Int) -> CameraHelperIPC.FaceLandmarks {
        CameraHelperIPC.FaceLandmarks(box: [Double(face.boundingBox.minX), Double(face.boundingBox.minY), Double(face.boundingBox.width), Double(face.boundingBox.height)],
                                      yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue, roll: face.roll?.doubleValue,
                                      confidence: Double(face.confidence),
                                      landmarksConfidence: Double(face.landmarks?.confidence ?? 0),
                                      faceCount: count,
                                      leftEye: pointList(face.landmarks?.leftEye), rightEye: pointList(face.landmarks?.rightEye),
                                      leftPupil: pointList(face.landmarks?.leftPupil), rightPupil: pointList(face.landmarks?.rightPupil))
    }

    /// Eye centre in pixel space; the same formula the parent's
    /// processVisionFrame uses, duplicated here so quality sampling can
    /// happen where the pixels are. Box-scaled landmark points.
    private static func eyeCentre(_ points: [[Double]]?, box: [Double], lmConf: Double, width: Double, height: Double) -> (Double, Double)? {
        guard let points, !points.isEmpty, lmConf >= 0.65 else { return nil }
        let x = points.reduce(0.0) { $0 + $1[0] } / Double(points.count)
        let y = points.reduce(0.0) { $0 + $1[1] } / Double(points.count)
        return ((box[0] + x * box[2]) * width, (box[1] + y * box[3]) * height)
    }

    fileprivate static func measureQuality(_ pixelBuffer: CVPixelBuffer, frame: CameraHelperIPC.Frame) -> CameraHelperIPC.Quality? {
        guard let lm = frame.landmarks else { return nil }
        let selected = (lm.yaw != nil && lm.pitch != nil && lm.roll != nil) ? lm.box : (frame.rect?.box ?? lm.box)
        let width = Double(frame.pixelWidth), height = Double(frame.pixelHeight)
        let leftC = eyeCentre(lm.leftPupil, box: lm.box, lmConf: lm.landmarksConfidence, width: width, height: height)
            ?? eyeCentre(lm.leftEye, box: lm.box, lmConf: lm.landmarksConfidence, width: width, height: height)
        let rightC = eyeCentre(lm.rightPupil, box: lm.box, lmConf: lm.landmarksConfidence, width: width, height: height)
            ?? eyeCentre(lm.rightEye, box: lm.box, lmConf: lm.landmarksConfidence, width: width, height: height)
        let eyes = [leftC, rightC].compactMap { $0 }.map { CGPoint(x: $0.0 / width, y: $0.1 / height) }
        let box = CGRect(x: selected[0], y: selected[1], width: selected[2], height: selected[3])
        guard let q = PoseFrameQuality.measure(pixelBuffer, face: box, eyes: eyes) else { return nil }
        return CameraHelperIPC.Quality(mean: q.mean, contrast: q.contrast, clipped: q.clipped)
    }
}

/// Child-process entry: `gor --camera-helper --gor-owner-pid <pid>`.
/// Reads NDJSON commands on stdin, runs the engine, exits with the
/// parent (owner watch) or on the shutdown command. Returns 4 where the
/// camera stack cannot exist (non-Darwin), like PrepareWorker.cli.
enum CameraHelperCLI {
    static let flag = "--camera-helper"
    static func cli(arguments: [String]) -> Int32? {
        guard arguments.contains(flag) else { return nil }
        _ = setpgid(0, 0) // own group; the parent's kill set is this exact pid
        PrepareProcessLifetime.watchOwner(arguments: arguments)
        let sink = CameraHelperSink(out: FileHandle.standardOutput)
        let engine = CameraHelperEngine(sink: sink)
        sink.send(CameraHelperIPC.Event(ev: "hello", version: CameraHelperIPC.protocolVersion, pid: getpid()))
        FileHandle.standardInput.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { exit(0) } // parent closed the pipe
            engine.handleLines(data)
        }
        dispatchMain()
    }
}

extension CameraHelperEngine {
    /// stdin chunks are funneled through sessionQueue so splitting and
    /// command handling share one serial order (the LineSplitter is a
    /// value type; it must not be mutated from concurrent callbacks).
    func handleLines(_ data: Data) {
        sessionQueue.async {
            for line in self.commandSplitter.push(data) {
                if let command = CameraHelperIPC.decodeCommand(line) { self.apply(command) }
            }
        }
    }
}
#endif
// END camera-helper runtime
