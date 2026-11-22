// Core station: source units below retain their complete non-lifted bytes.
import AVFoundation
import AppKit
import CoreFoundation
import CoreGraphics
import CoreImage
import Darwin
import Foundation
import IOKit
import IOKit.ps
import QuartzCore
import Vision

// MARK: - Diag.swift


/// Build-time switch: enabled. Runtime off: stop(). Thread names may carry app data, so review before sending this log outside.
/// Diagnostic only. Measures which gor thread uses the CPU.
/// Costs one thread_info call per thread and one ps snapshot every 10 s; gor diagnostics append to this player's admitted gor_diag.log session sink (20MiB per-player cap with sink-side head+tail truncation, one native owner).
/// Limits: only threads alive at both samples are counted, short-lived threads are missed,
/// thread ids are Mach port names (can be reused), and the top list can miss spread-out load
/// (total= still shows the sum over counted threads). Uncompiled, Mac-pending.
/// Flip to false to turn it off. Writes only to the session gor_diag.log sink; never a shared /tmp file; rows are dropped when the capture is unavailable or drained.
enum ThreadCpuDiag {
    static let enabled = true
    private static let intervalSeconds = 10.0
    static var vrMode = false  // set on main by the VR controller; read by the 10 s sample
    private static var timer: DispatchSourceTimer?
    private static var lastCpu: [UInt32: Double] = [:]
    private static var lastWall = ProcessInfo.processInfo.systemUptime
    private static var mainPort: thread_t?
    private static let queue = DispatchQueue(label: "gor.diag.threadcpu", qos: .utility)

    // All mutable state (timer, lastCpu, lastWall) is touched only on `queue`.
    // start()/stop() hop onto it, so they serialize with an in-flight sample().
    static func start() {
        guard enabled else { return }
        // Borrowed port name only, no mach_thread_self send right to release.
        let callerMainPort: thread_t? = Thread.isMainThread ? pthread_mach_thread_np(pthread_self()) : nil
        queue.async {
            guard timer == nil else { return }
            rotateIfFull()
            mainPort = callerMainPort
            lastCpu = [:]
            lastWall = ProcessInfo.processInfo.systemUptime
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
            t.setEventHandler { sample() }
            timer = t
            t.resume()
        }
    }

    /// Runtime off: call stop(). Setting `enabled = false` is a build-time switch only.
    static func stop() {
        queue.async {
            timer?.cancel()
            timer = nil
            lastCpu = [:]
        }
    }

    /// Kept as a startup hook, but no automatic legacy rotation is permitted.
    private static func rotateIfFull() {
        // The shared file is append-stop. Never rename/delete legacy diagnostics
        // or race descriptors held by another process at startup.
    }

    private static func cpuSeconds(_ info: thread_basic_info) -> Double {
        Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1e6
            + Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1e6
    }

    private static func processCPU() {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,%cpu=,comm="]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard let text = String(data: bytes, encoding: .utf8) else { return }
        let result = PlaybackProcessCPU.parse(text, rootPID: getpid())
        append(String(format: "playback-cost gor=%.1f mpv=%.1f ffmpeg=%.1f ffmpegWorkers=%d vr=%d sampleEvery_s=10 metric=ps_cpu_percent thermal=%d", result.gor, result.mpv, result.ffmpeg, result.workers, vrMode ? 1 : 0, ProcessInfo.processInfo.thermalState.rawValue) + " " + HeatShadow.drain())
    }

    static func recordPlaybackDecode(_ line: String) { print(line); queue.async { append(line) } }

    private static func sample() {
        processCPU()
        var list: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &list, &count) == KERN_SUCCESS, let threads = list else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)),
                          vm_size_t(Int(count) * MemoryLayout<thread_t>.size))
        }
        let now = ProcessInfo.processInfo.systemUptime  // monotonic
        let wall = now - lastWall
        lastWall = now
        var rows: [(pct: Double, name: String, id: UInt32, isMain: Bool)] = []
        var seen: [UInt32: Double] = [:]
        for i in 0..<Int(count) {
            let th = threads[i]
            defer { mach_port_deallocate(mach_task_self_, th) }  // every send right, on every path
            var info = thread_basic_info()
            var n = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
            let kr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) {
                    thread_info(th, thread_flavor_t(THREAD_BASIC_INFO), $0, &n)
                }
            }
            guard kr == KERN_SUCCESS else { continue }
            let cpu = cpuSeconds(info)
            seen[th] = cpu
            if let prev = lastCpu[th], wall > 0.5 {
                var nameBuf = [Int8](repeating: 0, count: 64)
                if let p = pthread_from_mach_thread_np(th) { pthread_getname_np(p, &nameBuf, 64) }
                let name = String(cString: nameBuf)
                rows.append((max(0, (cpu - prev) / wall * 100), th == mainPort ? "gor.main" : (name.isEmpty ? "-" : name), th, th == mainPort))
            }
        }
        lastCpu = seen
        guard !rows.isEmpty else { return }
        rows.sort { $0.pct > $1.pct }
        let total = rows.reduce(0) { $0 + $1.pct }
        let top = rows.prefix(8).map { String(format: "%@#%u=%.0f%%(main=%@)", $0.name, $0.id, $0.pct, $0.isMain ? "true" : "false") }.joined(separator: " ")
        append(String(format: "thread-cpu: win=%.1fs threads=%d total=%.0f%% top[%@]", wall, rows.count, total, top))
    }

    private static func append(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let prefix = "\(f.string(from: Date())) "
        let marker = "...[truncated]"
        var text = line.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let budget = 4096 - prefix.utf8.count - 1
        if text.utf8.count > budget {
            while text.utf8.count + marker.utf8.count > budget { text.removeLast() }
            text += marker
        }
        let data = Data((prefix + text + "\n").utf8)
        _ = DiagSessionSink.append(data)
    }
}


/// Diagnostic only. Shows how busy the main thread's run loop is and which counted callbacks fire.
/// Build-time switch: enabled. Runtime off: stop(). Costs two run-loop observer calls per loop
/// iteration plus one log line every 10 s. The session sink enforces a hard 20MiB per-player cap
/// with head+tail truncation; rows past it compact with a TRUNCATED note.
/// Limits: busy% is how long the main run loop was awake (it includes time blocked inside callbacks
/// and nested loops in modes that are not observed), so it is NOT main-thread CPU use and cannot by
/// itself explain a thread's CPU. Counters only cover call sites that call count(_:).
/// Counting only happens between start() and stop(); start()/stop() hop to the main thread.
/// All time values use the monotonic ProcessInfo.systemUptime clock.
/// Stop/restart and logging are not strictly serialized: a report that already took its snapshot may
/// still write one line after stop() or a restart, and the timer's generation is read when its setup
/// block runs, not when start() was called. Treat lines near a stop/start as approximate.
/// Uncompiled, Mac-pending.
enum MainThreadDiag {
    static let enabled = true
    private static let intervalSeconds = 10.0
    private static let lock = NSLock()
    private static var counters: [String: Int] = [:]
    private static var loopIterations = 0
    private static var busySeconds = 0.0
    private static var busyStart: TimeInterval = 0
    private static var active = false
    private static var generation = 0
    private static var lastReport = ProcessInfo.processInfo.systemUptime
    private static var observer: CFRunLoopObserver?
    private static var timer: DispatchSourceTimer?
    private static let queue = DispatchQueue(label: "gor.diag.mainthread", qos: .utility)

    /// Call from a callback you want counted (cheap: one lock, one dictionary add).
    static func count(_ name: String) {
        guard enabled else { return }
        lock.lock(); if active { counters[name, default: 0] += 1 }; lock.unlock()
    }

    /// Safe to call from any thread: the work runs on the main thread.
    static func start() {
        guard enabled else { return }
        if !Thread.isMainThread { DispatchQueue.main.async { start() }; return }
        guard observer == nil else { return }
        lock.lock(); counters = [:]; loopIterations = 0; busySeconds = 0; busyStart = 0; active = true; generation += 1; lastReport = ProcessInfo.processInfo.systemUptime; lock.unlock()
        let activities: CFRunLoopActivity = [.afterWaiting, .beforeWaiting]
        let obs = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities.rawValue, true, 0) { _, activity in
            lock.lock()
            if activity.contains(.afterWaiting) {
                busyStart = ProcessInfo.processInfo.systemUptime
                loopIterations += 1
            } else if activity.contains(.beforeWaiting), busyStart > 0 {
                busySeconds += ProcessInfo.processInfo.systemUptime - busyStart
                busyStart = 0
            }
            lock.unlock()
        }
        observer = obs
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        queue.async {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
            let gen = generation_snapshot()
            t.setEventHandler { report(generation: gen) }
            timer = t
            t.resume()
        }
    }

    /// Runtime off. Safe to call from any thread: the work runs on the main thread.
    static func stop() {
        if !Thread.isMainThread { DispatchQueue.main.async { stop() }; return }
        lock.lock(); active = false; generation += 1; counters = [:]; loopIterations = 0; busySeconds = 0; busyStart = 0; lock.unlock()
        if let obs = observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), obs, .commonModes) }
        observer = nil
        queue.async { timer?.cancel(); timer = nil }
    }

    private static func generation_snapshot() -> Int { lock.lock(); defer { lock.unlock() }; return generation }

    private static func report(generation gen: Int) {
        lock.lock()
        // Decided under the lock: a stopped or restarted instance logs nothing, and `now` is read
        // after the observer can no longer move busyStart past it.
        guard active, gen == generation else { lock.unlock(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let wall = now - lastReport
        lastReport = now
        let snapshot = counters; counters = [:]
        let loops = loopIterations; loopIterations = 0
        // Time spent inside the current, unfinished loop iteration counts too.
        var busy = busySeconds
        if busyStart > 0 { busy += now - busyStart; busyStart = now }
        busySeconds = 0
        lock.unlock()
        guard wall > 0.5 else { return }
        let counts = snapshot.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        append(String(format: "main-thread: win=%.1fs busy=%.0f%% loops=%d counts[%@]", wall, min(100, busy / wall * 100), loops, counts))
    }

    private static func append(_ line: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let prefix = "\(f.string(from: Date())) "
        let marker = "...[truncated]"
        var text = line.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        let budget = 4096 - prefix.utf8.count - 1
        if text.utf8.count > budget {
            while text.utf8.count + marker.utf8.count > budget { text.removeLast() }
            text += marker
        }
        let data = Data((prefix + text + "\n").utf8)
        _ = DiagSessionSink.append(data)
    }
}

/// Numeric/backend-only live-caption diagnostics. Never records audio, decoded text,
/// model paths or arbitrary stderr. Append-only to this player's admitted gor diagnostic sink; dropped when the capture is unavailable.
final class LiveCaptionDiagnostics {
    let session = UUID().uuidString
    private let lock=NSRecursiveLock()
    private var pending=Data()
    private let sink:(String)->Void
    init(sink:@escaping (String)->Void = LiveCaptionDiagnostics.append) {self.sink=sink}
    func begin(model:String,threads:Int,window:Double,step:Double,language:String,vad:Bool) {
        let safeModel=String(model.filter{$0.isLetter || $0.isNumber || "-_.".contains($0)}.prefix(64))
        let safeLanguage=String(language.filter{$0.isLetter || $0=="-"}.prefix(16))
        sink("live-caption session=\(session) model=\(safeModel) threads=\(threads) window_s=\(window) step_s=\(step) language=\(safeLanguage) vad=\(vad)")
    }
    func ingest(_ data:Data) {
        lock.lock();defer{lock.unlock()}
        for byte in data {
            if byte==10 {
                let line=String(data:pending,encoding:.utf8)
                pending.removeAll(keepingCapacity:true)
                if let line {record(line)}
            } else if pending.count<4096 {pending.append(byte)}
        }
    }
    private func record(_ line:String) {
        // Numeric timing line only. Raw text/language/status lines are intentionally excluded.
        if line.hasPrefix("[dbg] whisper_full returned ") {
            let pattern = #"^\[dbg\] whisper_full returned -?[0-9]+ \(window\.size\(\)=[0-9]+, took [0-9]+ms, wf_ms_ema=-?[0-9]+ms, current_step=[0-9]+ms, tick=[0-9]+, wall=[0-9.]+s\)$"#
            if line.range(of:pattern,options:.regularExpression) != nil {
                sink("live-caption session=\(session) \(line)")
            }
        } else {
            // Reduce backend-init lines to fixed labels, no paths/device names.
            let low=line.lowercased()
            if low.contains("core ml model loaded") {sink("live-caption session=\(session) backend=coreml-loaded")}
            else if low.contains("metal"),low.contains("using") || low.contains("found device") || low.contains("loaded") {
                sink("live-caption session=\(session) backend=metal-init-observed")
            } else if low.hasPrefix("system_info:") {
                for token in ["COREML = 1","COREML = 0","METAL = 1","METAL = 0","NEON = 1"] where line.contains(token) {
                    sink("live-caption session=\(session) build-feature=\(token)")
                }
            }
        }
    }
    private static let queue=DispatchQueue(label:"gor.diag.livecaption",qos:.utility)
    private static func append(_ line:String) {
        queue.async {
            let data=Data(("\(Date().timeIntervalSince1970) \(line)\n").utf8)
            _ = DiagSessionSink.append(data)
        }
    }
}

/// Read-only display headroom diagnostics. No video or UI state is changed.
enum DisplayHeadroomDiag {
    private static var observers:[NSObjectProtocol]=[]
    static func line(reason:String,index:Int,potential:Double,current:Double)->String {
        String(format:"display-edr reason=%@ screen=%d potential=%.3f current=%.3f",reason,index,potential,current)
    }
    static func start() {
        guard observers.isEmpty else {return}
        record("launch")
        for name in [NSApplication.didChangeScreenParametersNotification,NSWindow.didChangeScreenNotification] {
            observers.append(NotificationCenter.default.addObserver(forName:name,object:nil,queue:.main) {_ in record("screen-change")})
        }
    }
    private static func record(_ reason:String) {
        for (index,screen) in NSScreen.screens.enumerated() {
            NSLog("[gor] %@",line(reason:reason,index:index,
                potential:Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue),
                current:Double(screen.maximumExtendedDynamicRangeColorComponentValue)))
        }
    }
}

// MARK: - Session traces

/// Normal-session numeric A/V diagnostics only. No paths, titles, device names or media content.
final class AVSessionTrace {
    static let shared=AVSessionTrace()
    private var samples:[[String:Any]]=[]
    private var lastAt=0.0
    func sample(_ props:[String:Any],stereo:Bool) {
        PlaybackCacheTrace.sample(props); let now=ProcessInfo.processInfo.systemUptime
        guard now-lastAt>=1 else {return};lastAt=now
        var row:[String:Any] = ["t":now,"stereo":stereo]
        for key in ["avsync","total-avsync-change","frame-drop-count","decoder-frame-drop-count",
                    "vo-delayed-frame-count","mistimed-frame-count","time-pos","audio-delay","speed",
                    "estimated-vf-fps","display-fps","paused-for-cache","pause","seeking"] {
            if let n=props[key] as? NSNumber {row[key]=n}
        }
        // Only known nonprivate enum states, never an arbitrary returned string.
        if let sync=props["video-sync"] as? String,["audio","display-resample","display-resample-vdrop","display-resample-desync","display-tempo","display-vdrop","display-adrop","display-desync","desync"].contains(sync) {row["video-sync"]=sync}
        samples.append(row)
        if samples.count>300 {samples.removeFirst(samples.count-300)}
    }
    /// 199bi aux admission: the trace lands in this player's OWN admitted
    /// av-session.jsonl via the context's allowlisted writeAux (one sink per
    /// name, helper-enforced cap). No Application Support fallback and no file
    /// at all without admission; each JSON row carries the existing player id.
    @discardableResult func writeOnQuit()->URL? {
        guard !samples.isEmpty,let context=PlayerSessionContext.shared else{return nil}
        do {
            let pid=context.rawRoot.lastPathComponent
            let text=try samples.map {row->String in
                var tagged=row;tagged["player"]=pid
                return String(data:try JSONSerialization.data(withJSONObject:tagged,options:.sortedKeys),encoding:.utf8)!
            }.joined(separator:"\n")+"\n"
            guard context.writeAux(name:"av-session.jsonl",data:Data(text.utf8)) else{return nil}
            return context.rawRoot.appendingPathComponent("av-session.jsonl")
        } catch{return nil}
    }
}

final class CommandLatencyTrace {
    static let shared=CommandLatencyTrace()
    private let lock=NSLock()
    private var rows:[[String:Any]]=[]
    func record(kind:String,queuedMS:Double,sendMS:Double) {
        lock.lock();defer{lock.unlock()}
        rows.append(["t":ProcessInfo.processInfo.systemUptime,"kind":kind,"queueMS":queuedMS,"sendMS":sendMS])
        if rows.count>9000 {rows.removeFirst(rows.count-9000)}
    }
    func writeOnQuit() {
        lock.lock();let captured=rows;lock.unlock()
        guard !captured.isEmpty,let context=PlayerSessionContext.shared else{return}
        do {
            let pid=context.rawRoot.lastPathComponent
            let text=try captured.map {row->String in
                var tagged=row;tagged["player"]=pid
                return String(data:try JSONSerialization.data(withJSONObject:tagged,options:.sortedKeys),encoding:.utf8)!
            }.joined(separator:"\n")+"\n"
            _=context.writeAux(name:"input-session.jsonl",data:Data(text.utf8))
        } catch {}
    }
}

// Pure numeric aggregation. ps %cpu is the OS estimate, not a 10-second delta;
// short-lived children between samples are not measured. Never log comm/arguments.
enum PlaybackProcessCPU {
    static func parse(_ text: String, rootPID: Int32) -> (gor: Double, mpv: Double, ffmpeg: Double, workers: Int) {
        var rows: [(Int32, Int32, Double, String)] = []
        for line in text.split(separator: "\n") {
            let fields = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            if fields.count == 4, let pid = Int32(fields[0]), let parent = Int32(fields[1]), let cpu = Double(fields[2]), cpu.isFinite, cpu >= 0 {
                rows.append((pid, parent, cpu, (String(fields[3]) as NSString).lastPathComponent))
            }
        }
        var children: [Int32: [Int32]] = [:]
        for row in rows { children[row.1, default: []].append(row.0) }
        var owned: Set<Int32> = [rootPID]
        var pending: [Int32] = [rootPID]
        var cursor = 0
        while cursor < pending.count {
            let parent = pending[cursor]
            cursor += 1
            for child in children[parent] ?? [] where owned.insert(child).inserted {
                pending.append(child)
            }
        }
        // CPU percentages are nonnegative. Saturate only at Double's actual
        // representation limit so malformed huge rows never produce infinity.
        func finiteSum(_ selected: [(Int32, Int32, Double, String)]) -> Double {
            selected.reduce(0) { total, row in
                let next = total + row.2
                return next.isFinite ? next : Double.greatestFiniteMagnitude
            }
        }
        let gor = finiteSum(rows.filter { $0.0 == rootPID })
        let mpv = finiteSum(rows.filter { owned.contains($0.0) && $0.3 == "mpv" })
        let ffmpeg = finiteSum(rows.filter { owned.contains($0.0) && $0.3 == "ffmpeg" })
        let workers = rows.filter { owned.contains($0.0) && $0.3 == "ffmpeg" }.count
        return (gor, mpv, ffmpeg, workers)
    }
}

// MARK: - Vision request diagnostics (observational only)
// No compute selection, request revision, camera effect or frame cadence changes.
@available(macOS 12.0, *)
enum VisionRequestDiag {
    private static let lock = NSLock()
    private static var nextID: UInt64 = 0
    private final class WeakRequest {
        weak var value: VNRequest?
        init(_ value: VNRequest) { self.value = value }
    }
    // Bounded diagnostic identity cache. Eviction can repeat an inventory log,
    // but must never retain requests or confuse a reused object address.
    private static var inventoried: [ObjectIdentifier: WeakRequest] = [:]
    private static var inventoryOrder: [ObjectIdentifier?] = Array(repeating: nil, count: 256)
    private static var inventoryCursor = 0
    private static func firstInventory(_ request: VNRequest) -> Bool {
        let key = ObjectIdentifier(request)
        if inventoried[key]?.value === request { return false }
        if let evicted = inventoryOrder[inventoryCursor] { inventoried.removeValue(forKey: evicted) }
        inventoried[key] = WeakRequest(request)
        inventoryOrder[inventoryCursor] = key
        inventoryCursor = (inventoryCursor + 1) % inventoryOrder.count
        return true
    }
    private static var pending: [UInt64: (String, Double, Bool)] = [:]
    private static var timer: DispatchSourceTimer?
    private static func clock() -> Double { ProcessInfo.processInfo.systemUptime }
    private static func emit(_ text: String) { Diag.mediaRecord("VISION-DIAG " + text) }
    static func perform(_ handler: VNImageRequestHandler, _ requests: [VNRequest], label: String) throws {
        let started = clock()
        lock.lock(); nextID &+= 1; let id = nextID
        pending[id] = (label, started, false)
        if timer == nil {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "gor.vision.diagnostic"))
            t.schedule(deadline: .now() + 1, repeating: 1)
            t.setEventHandler { checkSlow() }; timer = t; t.resume()
        }
        let newRequests = requests.filter { firstInventory($0) }
        lock.unlock()
        emit("start id=\(id) label=\(label) uptime=\(started) count=\(requests.count)")
        for request in newRequests { inventory(request, label: label) }
        var result = "ok"
        defer {
            let ended = clock()
            lock.lock()
            pending.removeValue(forKey: id)
            if pending.isEmpty {
                timer?.cancel()
                timer = nil
            }
            lock.unlock()
            emit("end id=\(id) label=\(label) uptime=\(ended) elapsed_s=\(ended-started) result=\(result)")
        }
        do { try handler.perform(requests) }
        catch { result = "error-\((error as NSError).domain)-\((error as NSError).code)"; throw error }
    }
    private static func checkSlow() {
        let now = clock(); var rows: [String] = []
        lock.lock()
        for (id, item) in pending where !item.2 && now-item.1 >= 2 {
            rows.append("slow id=\(id) label=\(item.0) elapsed_s=\(now-item.1) threshold_s=2")
            pending[id] = (item.0, item.1, true)
        }
        lock.unlock(); for row in rows { emit(row) }
    }
    private static func inventory(_ request: VNRequest, label: String) {
        emit("request label=\(label) type=\(type(of:request)) revision=\(request.revision) cpuOnly=\(request.usesCPUOnly) background=\(request.preferBackgroundProcessing)")
        if #available(macOS 14.0, *) {
            do {
                let stages = try request.supportedComputeStageDevices
                for (stage, devices) in stages {
                    let configured = request.computeDevice(for: stage).map { String(describing: $0) } ?? "system-default-not-observable"
                    emit("compute label=\(label) stage=\(stage) supported=\(devices.map { String(describing:$0) }.joined(separator:",")) configured=\(configured) executed_device=not-exposed")
                }
            } catch { emit("compute label=\(label) supported-query-error=\((error as NSError).code)") }
        } else { emit("compute label=\(label) stage-query=unavailable-before-macOS14 executed_device=not-exposed") }
    }
    static func camera(_ device: AVCaptureDevice) {
        let dimensions = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        let centerStage: String; if #available(macOS 12.3, *) { centerStage = String(device.isCenterStageActive) } else { centerStage = "unavailable-before-macOS12.3" }
        emit("camera type=\(device.deviceType.rawValue) model=\(device.modelID) format=\(dimensions.width)x\(dimensions.height) minDuration=\(CMTimeGetSeconds(device.activeVideoMinFrameDuration)) maxDuration=\(CMTimeGetSeconds(device.activeVideoMaxFrameDuration)) portraitActive=\(device.isPortraitEffectActive) portraitSupported=\(device.activeFormat.isPortraitEffectSupported) centerStageActive=\(centerStage) face_attributes=private-system-request-not-observable")
    }
}

// BEGIN relocated SharedDiagnosticRecord.swift (195w 2a, behavior unchanged)

/// Lua emits these already-bounded records through mpv's existing stdout pipe.
/// All actual shared-file writes then use the same flock-protected descriptor
/// path as native diagnostics. No shell helper or per-record process is used.
enum SharedDiagnosticRecord {
    static let cap: UInt64 = 20 * 1024 * 1024
    static let marker = "GOR_DIAG_RECORD "
    static func payload(from line: String) -> Data? {
        guard let range = line.range(of: marker) else { return nil }
        let text = line[range.upperBound...].replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        return Data((String(text.prefix(4096)) + "\n").utf8.prefix(16385))
    }
}
// END relocated SharedDiagnosticRecord.swift

// BEGIN relocated SessionLogPaths.swift (195w 2a, behavior unchanged)

///195t B: original shared raw paths, with the existing in-place byte caps.
/// ZIP reads never delete these shared logs. StagedRunPaths owns test isolation.
enum SessionLogPaths {
    static let names: Set<String> = ["gor_diag.log","gor_direct.log","gor_sample.txt","gor_mpv_sample.txt","gor_camera_helper_sample.txt","wt_full.log","photon-grain-size.log","photon-grain-doc.log","gor-quit-debug.log"]
    static let root = URL(fileURLWithPath:"/tmp",isDirectory:true)
    static func path(_ original:String)->String { original }

    /// App-wide row seam (199bi item 2): app-level records (session marker,
    /// engine route rows) enter here exactly once — never copied twice and
    /// never written to a global shared file. The row carries THIS player's
    /// existing id (trailing field; rawRoot.lastPathComponent == allocate()'s
    /// player_id) and the core helper fans it out to app.log in every open
    /// player's dir; per-target attribution is the helper's job.
    @discardableResult
    static func appendAppRow(_ data: Data) -> Bool {
        PlayerSessionContext.appendAppRow(DiagSessionSink.tagged(data))
    }

    /// Final-close entry for the player capture: drains the per-player
    /// diagnostic sink (fsync, helper status commit, queue-drained barrier).
    /// Matches the ()throws->Void drainDiagnostics closure of
    /// PlayerSessionContext.finishAfterProducerShutdown. After return, appends
    /// are refused. Throws on a retryable drain failure; with no capture it is
    /// a no-op success, so a nil capture never stops playback or close.
    static func drainPlayerCapture() throws { try DiagSessionSink.drain() }
}
// END relocated SessionLogPaths.swift

// BEGIN player-session sink wiring (199bi)

/// Session wiring (199bi): every gor diagnostic append goes to the ONE
/// admitted native sink ("gor_diag.log", 20MiB per player with sink-side
/// head+tail truncation) under the exact PlayerSessionContext.rawRoot,
/// through the context's already-registered diagnostic producer — no
/// duplicate registration, no second owner of the admitted file. There is NO
/// global shared-log fallback: when the capture is unavailable (nil
/// context), the admission is refused, or the sink is drained, the row is
/// dropped and playback is never affected. Admission is lazy-once and
/// sticky: the helper is contacted at the first append, never per row.
enum DiagSessionSink {
    static let name = "gor_diag.log"
    private static let lock = NSLock()
    private enum State {
        case pending                        // no append and no drain yet
        case ready(PlayerSessionNativeSink) // admitted, accepting rows
        case refused                        // nil capture or refused admission; sticky
        case drained                        // final close ran; all appends refused
    }
    nonisolated(unsafe) private static var state: State = .pending

    /// 199bi row ownership: structured diag rows carry this player's existing
    /// deterministic id — rawRoot.lastPathComponent is allocate()'s
    /// player_id (the session dir identity, verified in
    /// player_session_logs.py: path=parent/identity, root=str(path)). No new
    /// id or allocator. Raw mpv/WT byte chunks never pass through here, so no
    /// binary/UTF8 framing is touched. The tag is a trailing key=value field
    /// so prefix-based cutters (timestamps at column 0) keep working.
    static func tagged(_ data: Data) -> Data {
        guard let context = PlayerSessionContext.shared else { return data }
        let tag = Data(" player=\(context.rawRoot.lastPathComponent)".utf8)
        var out = data
        if out.last == 0x0A { out.insert(contentsOf: tag, at: out.count - 1) }
        else { out.append(tag) }
        return out
    }

    /// Serialized state resolution only; the sink's own serial queue owns the
    /// write. The lock is never held across a disk write.
    @discardableResult
    static func append(_ data: Data) -> Bool {
        lock.lock()
        switch state {
        case .refused, .drained:
            lock.unlock()
            return false
        case .pending:
            guard let context = PlayerSessionContext.shared else {
                state = .refused
                lock.unlock()
                return false
            }
            let producer = context.adapter.diagnostic
            do {
                let sink = try context.makeSink(name: name, producer: producer, acknowledgeDrain: {
                    try context.observe("queue-drained", producer: producer)
                })
                state = .ready(sink)
            } catch {
                state = .refused
                lock.unlock()
                return false
            }
        case .ready:
            break
        }
        guard case .ready(let sink) = state else { lock.unlock(); return false }
        lock.unlock()
        // .capReached means this row landed in the sink's bounded head+tail
        // compaction, not as a full row; a drained/closed sink throws. Both
        // are a dropped row for the caller, never a playback failure.
        return (try? sink.append(tagged(data))) == .accepted
    }

    /// Final close (SessionLogPaths.drainPlayerCapture): fsync the admitted
    /// file, commit cap/io status to the helper, then acknowledge the
    /// queue-drained barrier. After a successful drain every later append is
    /// refused and no new sink is created. A failed drain throws and stays
    /// retryable; the sink itself already refuses further appends once its
    /// close began. With no capture or a never-used sink the drain is
    /// vacuous: the barrier is still acknowledged so the session can finish.
    static func drain() throws {
        lock.lock()
        switch state {
        case .drained:
            lock.unlock()
            return
        case .refused, .pending:
            // Admission never happened or no row was ever appended: no sink is
            // created just to drain; the barrier is acknowledged vacuously so
            // the session can finish.
            state = .drained
            lock.unlock()
            if let context = PlayerSessionContext.shared {
                try? context.observe("queue-drained", producer: context.adapter.diagnostic)
            }
            return
        case .ready(let sink):
            lock.unlock()
            try sink.drain()
            lock.lock()
            state = .drained
            lock.unlock()
        }
    }
}
// END player-session sink wiring

// BEGIN relocated BoundedDiskWriter.swift (195w 2a, behavior unchanged)
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Byte guards for diagnostic/cache writers. Existing legacy files are never
/// rotated or deleted here. An oversized old log simply receives no new bytes.
enum BoundedDiskWriter {
    static let logCap:UInt64=10*1024*1024
    @discardableResult static func append(_ data:Data,to url:URL,cap:UInt64=logCap)->Bool {
        guard UInt64(data.count)<=cap else {return false}
        let fd=open(url.path,O_CREAT|O_WRONLY|O_APPEND|O_NOFOLLOW|O_NONBLOCK,mode_t(0o600));guard fd>=0 else {return false}
        defer {_ = flock(fd,LOCK_UN);close(fd)}
        guard flock(fd,LOCK_EX)==0 else {return false}
        var s=stat();guard fstat(fd,&s)==0,s.st_nlink==1,(s.st_mode & S_IFMT)==S_IFREG,UInt64(max(0,s.st_size))+UInt64(data.count)<=cap else {return false}
        return data.withUnsafeBytes {raw in
            var at=0
            while at<raw.count {
                let n=write(fd,raw.baseAddress!.advanced(by:at),raw.count-at)
                if n<0 && errno==EINTR {continue};if n<=0 {return false};at+=n
            }
            return true
        }
    }
    /// New versioned subdirectory only; legacy siblings remain untouched. No
    /// pruning: full stores stop accepting diagnostic/cache copies. Successful
    /// callers still hold the original bytes in memory, so rendering is intact.
    @discardableResult static func save(_ data:Data,name:String,under parent:URL,cap:UInt64,entries:Int=256)->URL? {
        guard entries >= 0,!name.isEmpty,name==URL(fileURLWithPath:name).lastPathComponent,!name.hasPrefix("."),UInt64(data.count)<=cap else {return nil}
        let fm=FileManager.default,root=parent.appendingPathComponent("bounded-v1",isDirectory:true)
        let existed=fm.fileExists(atPath:root.path)
        if !existed {
            do {try fm.createDirectory(at:root,withIntermediateDirectories:true);try Data("gor-bounded-v1".utf8).write(to:root.appendingPathComponent(".owner"),options:.withoutOverwriting)}catch {return nil}
        }
        guard DepthCacheBudget.plainDirectory(root),DepthCacheBudget.plainFile(root.appendingPathComponent(".owner")),(try? String(contentsOf:root.appendingPathComponent(".owner"),encoding:.utf8))=="gor-bounded-v1" else {return nil}
        return try? DepthCacheBudget.withLock(root) {
            let all=try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
            let dest=root.appendingPathComponent(name)
            guard !fm.fileExists(atPath:dest.path),max(0,all.count-2)<entries,try DepthCacheBudget.bytes(root)+UInt64(data.count)<=cap else {throw DepthCacheBudget.Failure.quota}
            let fd=open(dest.path,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,mode_t(0o600));guard fd>=0 else {throw DepthCacheBudget.Failure.unsafe}
            // Keep the exclusive O_NOFOLLOW descriptor through the write. Reopening
            // its pathname would allow a rename/symlink race after validation.
            do {let h=FileHandle(fileDescriptor:fd,closeOnDealloc:false);defer {try? h.close()};try h.write(contentsOf:data)}catch {try? fm.removeItem(at:dest);throw error}
            return dest
        }
    }
}
// END relocated BoundedDiskWriter.swift

// BEGIN station-move PlaybackCacheTrace.swift

// Called on the poll consumer's main queue. One numeric record/second at most.
// These are observed cache samples, not the configured cache target.
enum PlaybackCacheTrace {
    private static var lastAt = -Double.infinity
    static func sample(_ props: [String: Any], now: Double = ProcessInfo.processInfo.systemUptime) {
        guard now - lastAt >= 1,
              let cache = props["demuxer-cache-duration"] as? NSNumber,
              cache.doubleValue.isFinite, cache.doubleValue >= 0 else { return }
        lastAt = now
        let position = (props["time-pos"] as? NSNumber)?.doubleValue ?? -1
        let paused = (props["paused-for-cache"] as? NSNumber)?.intValue ?? -1
        let utcMS = Int64(Date().timeIntervalSince1970 * 1000)
        ThreadCpuDiag.recordPlaybackDecode(String(format: "[playback-cache] utc_ms=%lld position_s=%.3f cache_s=%.3f paused_for_cache=%d", utcMS, position.isFinite ? position : -1, cache.doubleValue, paused))
    }
}
// END station-move PlaybackCacheTrace.swift

/// Engine route record: one bounded row per player open and per engine switch, fanned out through the app-row
/// seam to every open player's app.log so collection can show requested/active at every transition. Typed fields only.
enum GorEngineRecord {
    static let engines: Set<String> = ["mpv", "gorav"]
    static let events: Set<String> = ["open", "switch"]
    static let origins: Set<String> = ["menu", "environment", "saved", "default"]
    /// Returns nil for an unknown event, engine or origin: a malformed record is refused, never guessed.
    /// Raw selection inputs as recorded (nil -> "none"); anything outside [a-z0-9_-] or longer than 16 becomes "invalid".
    static func value(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "none" }
        let ok = raw.count <= 16 && raw.allSatisfy { ($0.isLowercase && $0.isLetter && $0.isASCII) || ($0.isNumber && $0.isASCII) || $0 == "_" || $0 == "-" }
        return ok ? raw : "invalid"
    }
    static func line(event: String, requested: String, active: String, origin: String? = nil, env: String? = nil, saved: String? = nil, menuOverride: String? = nil, fallback: String? = nil, at date: Date = Date()) -> String? {
        guard events.contains(event), engines.contains(requested), engines.contains(active) else { return nil }
        if let origin, !origins.contains(origin) { return nil }
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss.SSS"
        var text = "\(formatter.string(from: date)) [GOR-ENGINE] event=\(event) requested=\(requested) active=\(active)"
        if let origin { text += " origin=" + origin }
        if origin != nil { text += " env=" + value(env) + " saved=" + value(saved) + " override=" + value(menuOverride) }
        if let fallback, !fallback.isEmpty {
            let safe = fallback.map { $0.isLetter || $0.isNumber ? $0 : "_" }
            text += " fallback=" + String(safe.prefix(64))
        }
        return text
    }
    @discardableResult
    static func write(event: String, requested: String, active: String, origin: String? = nil, env: String? = nil, saved: String? = nil, menuOverride: String? = nil, fallback: String? = nil) -> Bool {
        GorSessionMarker.reemit()
        guard let text = line(event: event, requested: requested, active: active, origin: origin, env: env, saved: saved, menuOverride: menuOverride, fallback: fallback) else { return false }
        return SessionLogPaths.appendAppRow(Data((text + "\n").utf8))
    }
}

/// Session marker: written at launch through the app-row seam (fanned out to per-player app.log, mirrored to gor_direct.log by the caller's print)
/// and re-emitted before every engine record, so a cut or trim of the shared file keeps it findable.
/// Collection binds a cut to the marker whose pid and launch time match the real process and whose
/// build matches the installed build-id.
enum GorSessionMarker {
    private static let lock = NSLock()
    // Every read and write is protected by lock, including disk append ordering.
    nonisolated(unsafe) private static var current: String?
    private static func isHex(_ value: String, _ count: Int) -> Bool {
        value.count == count && value.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }
    static func line(pid: Int32, launchEpoch: Int, launchID: String, build: String, tree: String) -> String? {
        guard pid > 0, launchEpoch > 0, isHex(launchID, 32),
              build == "unknown" || isHex(build, 64), tree == "unknown" || isHex(tree, 40) else { return nil }
        return "[GOR-SESSION] pid=\(pid) launch_epoch=\(launchEpoch) launch_id=\(launchID) build=\(build) tree=\(tree)"
    }
    private static func append(_ text: String) -> Bool {
        SessionLogPaths.appendAppRow(Data((text + "\n").utf8))
    }
    /// Returns the line that was written so the caller can mirror it to stdout (gor_direct.log).
    static func write(build: String, tree: String, at date: Date = Date()) -> String? {
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        guard let text = line(pid: getpid(), launchEpoch: Int(date.timeIntervalSince1970), launchID: id,
                              build: isHex(build, 64) ? build : "unknown", tree: isHex(tree, 40) ? tree : "unknown") else { return nil }
        lock.lock(); defer { lock.unlock() }
        current = text
        _ = append(text); return text
    }
    /// Same launch_id, same line: the cut starts at the earliest copy, so re-emission never shortens it.
    static func reemit() {
        lock.lock(); defer { lock.unlock() }
        if let current { _ = append(current) }
    }
}

// MARK: - GeomTrace.swift
/// Opt-in geometry trace for fullscreen root diagnosis. Off unless env GOR_TRACE_GEOM=1.
/// Writes only sizes/counts (never titles, URLs or keys) to Application Support/gor/geom_trace.log.
enum GeomTrace {
    static let on = ProcessInfo.processInfo.environment["GOR_TRACE_GEOM"] == "1"
    private static let q = DispatchQueue(label: "gor.geomtrace")
    // Change-gated variant for 4 Hz call sites (HUD layout/crop bounds): logs
    // only when the rendered message for a tag differs from the last logged one.
    // Call sites are main-thread only (applyVideoFrame, layoutPhotonHUD, scroll).
    private static var lastLogged = [String: String]()
    static func logChanged(_ tag: String, _ message: String) {
        guard on, lastLogged[tag] != message else { return }
        lastLogged[tag] = message
        log(tag, message)
    }
    /// Blink measurement output. Unlike log(), it does not need the GOR_TRACE_GEOM environment variable: a normal
    /// launch never sets it, so Shift+E measured nothing for the owner. It only runs while the owner has turned
    /// the blink measurement on, and writes its own file next to geom_trace.log.
    private static var blinkLogStopped = false // accessed only on q
    /// `session` is the blink session id of this opt-in. Lines enqueued while it is current carry it; a failure of an
    /// older session neither stops the newer log nor reaches the controller as a current failure (the controller also
    /// re-checks the id under the tracker lock before it turns anything off).
    private static let genLock = NSLock()
    private static var currentGen: UInt64 = 0          // guarded by genLock; read at enqueue time
    static func beginBlinkLog(session: UInt64, onFailure: @escaping (UInt64, String) -> Void) {
        genLock.lock(); currentGen = session; genLock.unlock()
        q.async { blinkQGen = session; blinkLogStopped = false; blinkLogFailure = onFailure }
    }
    private static var blinkQGen: UInt64 = 0          // accessed only on q
    private static var blinkLogFailure: ((UInt64, String) -> Void)? // accessed only on q
    private static func stopBlinkLog(_ reason: String, gen: UInt64) {
        guard gen == blinkQGen else { return }          // stale line of an older session: ignore
        blinkLogStopped = true
        let callback = blinkLogFailure
        DispatchQueue.main.async { callback?(gen, reason) }
    }
    /// Appends one line to blink_trace.log (append only, 8 MiB cap, no truncation). Returns nil on success or the
    /// failure reason. Must run on q.
    private static func appendBlinkLine(_ line: String) -> String? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("gor") else {
            return "blink measurement unavailable: no log directory"
        }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let p = dir.appendingPathComponent("blink_trace.log")
            // Append only, bounded across sessions. No truncation, rotation or deletion.
            if !FileManager.default.fileExists(atPath: p.path) {
                guard FileManager.default.createFile(atPath: p.path, contents: nil) else {
                    return "blink measurement unavailable: cannot create log"
                }
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: p.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size + line.utf8.count <= 8 * 1024 * 1024 else {
                return "blink measurement stopped: log full (8 MiB), existing samples preserved"
            }
            let h = try FileHandle(forWritingTo: p)
            defer { try? h.close() }
            try h.seekToEnd()
            try h.write(contentsOf: Data(line.utf8))
        } catch {
            return "blink measurement unavailable: log write failed; existing samples preserved"
        }
        return nil
    }
    static func logBlink(_ f: @autoclosure () -> String) {
        let line = String(format: "%.3f blinkTrace %@\n", Date().timeIntervalSince1970, f())
        genLock.lock(); let gen = currentGen; genLock.unlock()
        q.async {
            guard gen == blinkQGen, !blinkLogStopped else { return }   // a line of an older session is dropped, not written into the new one
            if let reason = appendBlinkLine(line) { stopBlinkLog(reason, gen: gen) }
        }
    }
    /// Session summary row. Unlike logBlink it never stops the log and never calls the failure callback (no recursion):
    /// if the log is stopped, full or failing it reports "unavailable" instead, otherwise "written".
    static func logBlinkSummary(_ f: @autoclosure () -> String, unavailable: @escaping (String) -> Void, written: @escaping () -> Void) {
        let line = String(format: "%.3f blinkTrace %@\n", Date().timeIntervalSince1970, f())
        q.async {
            if blinkLogStopped {
                DispatchQueue.main.async { unavailable("unavailable (blink log stopped or full)") }
                return
            }
            if let reason = appendBlinkLine(line) {
                DispatchQueue.main.async { unavailable("unavailable (\(reason))") }
            } else {
                DispatchQueue.main.async { written() }
            }
        }
    }
    static func log(_ tag: String, _ f: @autoclosure () -> String) {
        guard on else { return }
        let line = String(format: "%.3f %@ %@\n", Date().timeIntervalSince1970, tag, f())
        q.async {
            guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("gor") else { return }
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let p = dir.appendingPathComponent("geom_trace.log")
            _ = BoundedDiskWriter.append(Data(line.utf8),to:p)
        }
    }
}
