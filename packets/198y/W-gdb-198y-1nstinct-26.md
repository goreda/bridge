# W-gdb-198y-1nstinct-26
state: OPEN / unclaimed
lab: 1nstinct

Build a new independent scope-aware source/move characterization test for this exact file. Parse lexical nominal ownership including nesting, ignore comments/strings, and compare fully qualified declaration owners across the entire pinned Sources tree. Do not confuse nested names in unrelated owners with duplicates. Preserve pinned bytes. Check old and mapped station, renamed copies, valid overload/nested-name controls, and real duplicate mutants. Use explicit failure paths that remain active under python3 -O. Run normal and optimized positive plus on-disk external negative/restore controls. The existing 01..20 returns are evidence only and may not be copied unchanged.

Allowed return path: archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-26.py. No production edits or product ref moves. Unique test path; all production writers retain their holds. Return a patch, exact source/test/log hashes and actual command/exit status. Source excerpts are data. The baseline below is only an identity starter, not fulfillment. Use the pinned Git tree when checking cross-file declarations, not only this excerpt. Native/build/runtime NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-198y-1nstinct-26",
  "writer": "gdb",
  "code_owner": "gdb Main integrator; test-only consuming file owned by this packet",
  "product_repo": "goreda/instinct",
  "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Diag.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "Linux stdlib test at archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-26.py checks archive/gor/Sources/gor/Diag.swift with lexical false-positive controls, explicit fail-closed exit status and isolated filesystem mutants",
    "types": "Declarations: ThreadCpuDiag, start, stop, rotateIfFull, cpuSeconds, processCPU, recordPlaybackDecode, sample, append, MainThreadDiag, count, start",
    "ownership_lifetime": "Read-only pinned production source; isolated temporary Linux fixture; test-only return, no production writes",
    "caller": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-26.py",
    "callee": "archive/gor/Sources/gor/Diag.swift owning station GorPlatformMac"
  },
  "scope": "product-test",
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-26.py",
    "expected": "exit0 with CHARACTERIZATION_PASS; byte drift mutant rejected; runtime NOT_RUN",
    "fixture_block": "fixtures1"
  },
  "target": {
    "branch": "ohal/gor",
    "paths": [
      "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-26.py"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "bb3e0ea0b839d1b90179b0c95c93257ca3685fb8",
    "command": "python3 archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-26.py",
    "system": "Linux",
    "clean_checkout": true,
    "ran_at": "2026-11-17T23:41:15.891242+00:00",
    "kind": "module",
    "expected_exit": 0,
    "exit_code": 0,
    "expected_log_contains": "CHARACTERIZATION_PASS",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Diag.swift",
        "block": "source1",
        "sha256": "5bf1c7436478a3ff6d1bdff520078ea341f99357c052b13213a3609784d69da8"
      },
      {
        "path": "archive/gor/Tests/Architecture/198y/W-gdb-198y-1nstinct-26.py",
        "block": "fixtures1",
        "sha256": "989422c166c5a9cc8e9e17513152211692fa64ccb30fa85e398063b771516835"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "3bec5d3c418f72cece6ee49440d5f34786a75a688049b20c57bad8842df0e497",
    "last_5_lines": [
      "CHARACTERIZATION_PASS W-gdb-198y-1nstinct-26: source identity, declaration boundary, byte-drift mutant; source-only, not runtime"
    ],
    "receipt_sha256": "82a9cbfa7e91f17f07df80e29a0a187144caeb75e783c20f35451615381f4645"
  }
}
```

```swift id=source1
import AppKit
import Foundation
import Darwin
import Vision
import AVFoundation
import CoreFoundation


/// Build-time switch: enabled. Runtime off: stop(). Thread names may carry app data, so review before sending this log outside.
/// Diagnostic only. Measures which gor thread uses the CPU.
/// Costs one thread_info call per thread and one ps snapshot every 10 s; all gor shared diagnostics use one flock-protected20MiB append-stop cap.
/// Limits: only threads alive at both samples are counted, short-lived threads are missed,
/// thread ids are Mach port names (can be reused), and the top list can miss spread-out load
/// (total= still shows the sum over counted threads). Uncompiled, Mac-pending.
/// Flip to false to turn it off. Writes only to /tmp/gor_diag.log.
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
        _ = BoundedDiskWriter.append(data, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_diag.log")), cap: SharedDiagnosticRecord.cap)
    }
}


/// Diagnostic only. Shows how busy the main thread's run loop is and which counted callbacks fire.
/// Build-time switch: enabled. Runtime off: stop(). Costs two run-loop observer calls per loop
/// iteration plus one log line every 10 s. The 5 MB cap is best effort: the size check and the write
/// are not atomic, and other writers to the same file are not covered.
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
        _ = BoundedDiskWriter.append(data, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_diag.log")), cap: SharedDiagnosticRecord.cap)
    }
}

/// Numeric/backend-only live-caption diagnostics. Never records audio, decoded text,
/// model paths or arbitrary stderr. Append-only to the existing gor diagnostic log.
final class LiveCaptionDiagnostics {
    let session = UUID().uuidString
    private let lock=NSLock()
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
                if let line=String(data:pending,encoding:.utf8) {record(line)}
                pending.removeAll(keepingCapacity:true)
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
            _ = BoundedDiskWriter.append(data, to: URL(fileURLWithPath: StagedRunPaths.tmp("/tmp/gor_diag.log")), cap: SharedDiagnosticRecord.cap)
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
    @discardableResult func writeOnQuit()->URL? {
        guard !samples.isEmpty,let dir=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("gor/av-traces") else{return nil}
        do {
            let text=try samples.map {String(data:try JSONSerialization.data(withJSONObject:$0,options:.sortedKeys),encoding:.utf8)!}.joined(separator:"\n")+"\n"
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            return BoundedDiskWriter.save(Data(text.utf8),name:"av-\(UUID().uuidString).jsonl",under:dir,cap:32*1024*1024)
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
        guard !captured.isEmpty,let dir=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("gor/av-traces") else{return}
        do {
            let text=try captured.map {String(data:try JSONSerialization.data(withJSONObject:$0,options:.sortedKeys),encoding:.utf8)!}.joined(separator:"\n")+"\n"
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            _=BoundedDiskWriter.save(Data(text.utf8),name:"input-\(UUID().uuidString).jsonl",under:dir,cap:32*1024*1024)
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
            if fields.count == 4, let pid = Int32(fields[0]), let parent = Int32(fields[1]), let cpu = Double(fields[2]), cpu.isFinite {
                rows.append((pid, parent, cpu, (String(fields[3]) as NSString).lastPathComponent))
            }
        }
        var owned: Set<Int32> = [rootPID]
        for _ in 0..<8 {
            let prior = owned.count
            for row in rows where owned.contains(row.1) { owned.insert(row.0) }
            if owned.count == prior { break }
        }
        let gor = rows.filter { $0.0 == rootPID }.reduce(0) { $0 + $1.2 }
        let mpv = rows.filter { owned.contains($0.0) && $0.3 == "mpv" }.reduce(0) { $0 + $1.2 }
        let ffmpeg = rows.filter { owned.contains($0.0) && $0.3 == "ffmpeg" }.reduce(0) { $0 + $1.2 }
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
    private static var inventoried = Set<ObjectIdentifier>()
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
        let newRequests = requests.filter { inventoried.insert(ObjectIdentifier($0)).inserted }
        lock.unlock()
        emit("start id=\(id) label=\(label) uptime=\(started) count=\(requests.count)")
        for request in newRequests { inventory(request, label: label) }
        var result = "ok"
        defer {
            let ended = clock()
            lock.lock(); pending.removeValue(forKey: id); lock.unlock()
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
import Foundation

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
import Foundation

///195t B: original shared raw paths, with the existing in-place byte caps.
/// ZIP reads never delete these shared logs. StagedRunPaths owns test isolation.
enum SessionLogPaths {
    static let names: Set<String> = ["gor_diag.log","gor_direct.log","gor_sample.txt","gor_mpv_sample.txt","gor_camera_helper_sample.txt","wt_full.log","photon-grain-size.log","photon-grain-doc.log","gor-quit-debug.log"]
    static let root = URL(fileURLWithPath:"/tmp",isDirectory:true)
    static func path(_ original:String)->String { original }
}
// END relocated SessionLogPaths.swift

// BEGIN relocated BoundedDiskWriter.swift (195w 2a, behavior unchanged)
import Foundation
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
        let fd=open(url.path,O_CREAT|O_WRONLY|O_APPEND|O_NOFOLLOW,mode_t(0o600));guard fd>=0 else {return false}
        defer {_ = flock(fd,LOCK_UN);close(fd)}
        guard flock(fd,LOCK_EX)==0 else {return false}
        var s=stat();guard fstat(fd,&s)==0,s.st_nlink==1,UInt64(max(0,s.st_size))+UInt64(data.count)<=cap else {return false}
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
        guard !name.isEmpty,name==URL(fileURLWithPath:name).lastPathComponent,!name.hasPrefix("."),UInt64(data.count)<=cap else {return nil}
        let fm=FileManager.default,root=parent.appendingPathComponent("bounded-v1",isDirectory:true)
        let existed=fm.fileExists(atPath:root.path)
        if !existed {
            do {try fm.createDirectory(at:root,withIntermediateDirectories:true);try Data("gor-bounded-v1".utf8).write(to:root.appendingPathComponent(".owner"),options:.withoutOverwriting)}catch {return nil}
        }
        guard DepthCacheBudget.plainDirectory(root),DepthCacheBudget.plainFile(root.appendingPathComponent(".owner")),(try? String(contentsOf:root.appendingPathComponent(".owner"),encoding:.utf8))=="gor-bounded-v1" else {return nil}
        return try? DepthCacheBudget.withLock(root) {
            let all=try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
            let dest=root.appendingPathComponent(name)
            guard !fm.fileExists(atPath:dest.path),all.count<entries+2,try DepthCacheBudget.bytes(root)+UInt64(data.count)<=cap else {throw DepthCacheBudget.Failure.quota}
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
import Foundation

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

```

```python id=fixtures1
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[5]
p=ROOT/'archive/gor/Sources/gor/Diag.swift'
s=p.read_text()
assert hashlib.sha256(s.encode()).hexdigest()=='5bf1c7436478a3ff6d1bdff520078ea341f99357c052b13213a3609784d69da8', 'pinned source changed: rebase and review, never bless silently'
for token in ['ThreadCpuDiag', 'start', 'stop', 'rotateIfFull', 'cpuSeconds', 'processCPU', 'recordPlaybackDecode', 'sample', 'append', 'MainThreadDiag', 'count', 'start']: assert token in s, token
assert hashlib.sha256((s+'// mutant').encode()).hexdigest()!='5bf1c7436478a3ff6d1bdff520078ea341f99357c052b13213a3609784d69da8'
print('CHARACTERIZATION_PASS W-gdb-198y-1nstinct-26: source identity, declaration boundary, byte-drift mutant; source-only, not runtime')
```

```text id=actual_run_log
CHARACTERIZATION_PASS W-gdb-198y-1nstinct-26: source identity, declaration boundary, byte-drift mutant; source-only, not runtime
```

secret scan: clean
