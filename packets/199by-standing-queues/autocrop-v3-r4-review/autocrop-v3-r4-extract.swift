// gor autocrop v3 reference extract (r4, base 374c2b9e14bfbf1614091767c83ce4ce3f07bac8): SourcePixelBounds + SourcePixelCropScanner + WTCropSamples, verbatim contiguous regions from Sources/gor/ThreeD/Source.swift; the unrelated lines between the scanner and WTCropSamples are omitted. Public-safe: product source only. Supersedes the 701-line r3 extract (r3 PP blocker fixed: dispatch frontier identity is now the raw max range end, same coordinate as the PPController poll; see rawFrontierEnd).
enum SourcePixelBounds {
    struct Bounds: Equatable {
        var x0: Int; var y0: Int; var x1: Int; var y1: Int
        func union(_ b: Bounds) -> Bounds {
            Bounds(x0:min(x0,b.x0),y0:min(y0,b.y0),x1:max(x1,b.x1),y1:max(y1,b.y1))
        }
    }
    /// Early-apply rule for stream scans: at least `minCount` non-black frames whose bounds all agree with their union
    /// within `tol` px on every edge. Returns the union, else nil. The final scan result is never narrower than this
    /// (later frames can only widen the union), so refining after an early apply never cuts more.
    static let earlyMinCount = 3
    static let earlyTolerance = 8
    static func consistent(_ members: [Bounds], tol: Int = earlyTolerance, minCount: Int = earlyMinCount) -> Bounds? {
        guard members.count >= minCount, let first = members.first else { return nil }
        let u = members.dropFirst().reduce(first) { $0.union($1) }
        for m in members where abs(m.x0-u.x0) > tol || abs(m.y0-u.y0) > tol || abs(m.x1-u.x1) > tol || abs(m.y1-u.y1) > tol { return nil }
        return u
    }
    /// Diagnostic only: luma mean/max (8-bit-equivalent, relative to black) of rows near the measured top and bottom bound, so a log shows the
    /// real bar level. Reads the first plane of little-endian 16-bit samples (luma for yuv444p16le and gray16le).
    static func edgeRows(_ bytes: Data, width: Int, height: Int, bounds b: Bounds, black: Int, bits: Int, gray: Bool) -> String {
        let planeBytes = width * height * 2
        guard width > 0, height > 0, bytes.count >= planeBytes else { return "unavailable" }
        let shift = max(0, 16 - bits), unit = 1 << max(0, bits - 8)
        var out: [String] = []
        bytes.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            func stat(_ y: Int) -> String {
                guard y >= 0, y < height else { return "-" }
                var sum = 0, mx = 0, x = 0
                while x < width { let i = (y * width + x) * 2; let v = Int(UInt16(p[i]) | UInt16(p[i + 1]) << 8) >> shift; sum += v; mx = max(mx, v); x += 1 }
                let mean = Double(sum) / Double(width) - Double(black), top = mx - black
                return String(format: "y%d=%.1f/%d", y, mean / Double(unit), top / unit)
            }
            for d in [-24, -12, -4, 0, 4, 12, 24] { out.append("T" + stat(b.y0 + d)) }
            for d in [-24, -12, -4, 0, 4, 12, 24] { out.append("B" + stat(b.y1 - 1 - d)) }
        }
        return out.joined(separator: " ")
    }
    /// Exact bounding box of every sample above `threshold` (identical result to a full per-pixel scan).
    /// Rows are visited top-down until the first bright row and bottom-up until the last; middle rows only
    /// look for a bright sample left of the current x0 or right of the current x1, so a full frame costs
    /// a few rows instead of every pixel. Little-endian UInt16 samples.
    ///
    /// Edge rows tolerate isolated specks: when `speck` > 0 a row at the top or bottom edge is content only if more than `speck`
    /// samples exceed `threshold`, or any sample exceeds `strong` (clearly non-black). Encode noise and stray bright pixels inside
    /// a letterbox bar then no longer move the bound (the owner saw a 26-row band above and 10 rows below the picture). With
    /// speck 0 the result is the exact one-sample veto as before.
    static func scan(_ bytes: Data, width: Int, height: Int, threshold: UInt16, speck: Int = 0, strong: UInt16 = 0) -> Bounds? {
        guard width > 0, height > 0, bytes.count >= width * height * 2 else { return nil }
        var result: Bounds?
        bytes.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt8.self)
            @inline(__always) func sample(_ y: Int, _ x: Int) -> UInt16 {
                let i = (y * width + x) * 2
                return UInt16(p[i]) | UInt16(p[i + 1]) << 8
            }
            // First bright x in [from, to) or -1; last bright x in [from, to) or -1.
            func first(_ y: Int, _ from: Int, _ to: Int) -> Int {
                var x = from
                while x < to { if sample(y, x) > threshold { return x }; x += 1 }
                return -1
            }
            func last(_ y: Int, _ from: Int, _ to: Int) -> Int {
                var x = to - 1
                while x >= from { if sample(y, x) > threshold { return x }; x -= 1 }
                return -1
            }
            func rowIsContent(_ y: Int) -> Bool {
                if speck <= 0 || strong <= threshold { return first(y, 0, width) >= 0 }
                var n = 0
                var x = 0
                while x < width {
                    let v = sample(y, x)
                    if v > strong { return true }
                    if v > threshold { n += 1; if n > speck { return true } }
                    x += 1
                }
                return false
            }
            var top = -1
            var y = 0
            while y < height { if rowIsContent(y) { top = y; break }; y += 1 }
            guard top >= 0 else { return }
            var bottom = top
            y = height - 1
            while y > top { if rowIsContent(y) { bottom = y; break }; y -= 1 }
            var x0 = width, x1 = 0
            for row in [top, bottom] {
                x0 = min(x0, first(row, 0, width))
                x1 = max(x1, last(row, 0, width) + 1)
            }
            if top + 1 < bottom {
                y = top + 1
                while y < bottom {
                    if x0 == 0 && x1 == width { break }
                    if x0 > 0 { let f = first(y, 0, x0); if f >= 0 { x0 = f } }
                    if x1 < width { let l = last(y, x1, width); if l >= 0 { x1 = l + 1 } }
                    y += 1
                }
            }
            result = Bounds(x0: x0, y0: top, x1: x1, y1: bottom + 1)
        }
        return result
    }
    static func scanHalves(_ bytes:Data,width:Int,height:Int,threshold:UInt16,topBottom:Bool=false)->[Bounds]? {
        guard width%2==0,height%2==0,bytes.count>=width*height*2 else{return nil}
        if topBottom {
            var eyes:[Bounds]=[]
            for eye in 0...1 {
                let a=eye*width*height
                let bound=scan(bytes.subdata(in:a..<(a+width*height)),width:width,height:height/2,threshold:threshold)
                    ?? Bounds(x0:width,y0:height/2,x1:0,y1:0)
                eyes.append(bound)
            }
            return eyes
        }
        var halves:[Bounds]=[]
        for eye in 0...1 {
            var half=Data();half.reserveCapacity(width*height)
            for y in 0..<height {
                let a=(y*width+eye*width/2)*2
                half.append(bytes.subdata(in:a..<(a+width)))
            }
            let bound=scan(half,width:width/2,height:height,threshold:threshold)
                ?? Bounds(x0:width/2,y0:height,x1:0,y1:0)
            halves.append(bound)
        }
        return halves
    }
    /// A display viewport may crop the common local eye rectangle without touching a packed seam.
    static func eyeViewport(_ eyes:[Bounds],width:Int,height:Int,topBottom:Bool) -> CGRect? {
        guard eyes.count==2 else {return nil}
        let w=topBottom ? width:width/2,h=topBottom ? height/2:height
        let common=eyes[0].union(eyes[1])
        guard common.x1>common.x0,common.y1>common.y0 else {return nil}
        let b=outward(common,width:w,height:h,stereo:false)
        return CGRect(x:Double(b.x0)/Double(w),y:Double(b.y0)/Double(h),width:Double(b.x1-b.x0)/Double(w),height:Double(b.y1-b.y0)/Double(h))
    }
    static func outward(_ b: Bounds, width: Int, height: Int, stereo: Bool,topBottom:Bool=false) -> Bounds {
        // A rectangular video-crop cannot remove each eye's inner horizontal edge without cutting
        // the seam. Keep all SBS columns; top/bottom bounds are the union of both complete halves.
        if topBottom {
            return Bounds(x0:(b.x0/2)*2,y0:0,x1:min(width,((b.x1+1)/2)*2),y1:height)
        }
        return Bounds(x0:stereo ? 0 : (b.x0 / 2) * 2, y0:(b.y0 / 2) * 2,
               x1:stereo ? width : min(width,((b.x1 + 1) / 2) * 2),
               y1:min(height,((b.y1 + 1) / 2) * 2))
    }
}
final class SourcePixelCropScanner {
    private let lock = NSLock()
    private var epoch = 0
    private var freshnessFloor = 0 // only an explicit measurement boundary forbids cancelled carry reuse
    private var active: Process?
    /// Work already measured on a stream (wt) survives a cancel: bars are a static property of the file, so the union of
    /// samples from an interrupted scan stays valid for the next scan of the same file, and a decisive rect that was
    /// computed but dropped by a cancel is handed to the next scan of that file instead of being thrown away.
    /// key = path|stereo|topBottom|rounded duration of the scan that wrote it; dims = "WxH pix range" once the stream was probed ("" if never).
    private struct Carry { var key: String; var dims: String; var at: Double; var bounds: SourcePixelBounds.Bounds?; var members: [SourcePixelBounds.Bounds]; var sampled: Int; var undelivered: Bool; var rect: CGRect?; var done: [Double]; var ep: Int; var planned: [Double] }   // ep = epoch of the scan that wrote it: an older scan never overwrites it; planned = the exact sample plan the progress belongs to
    /// Interrupted-scan progress may seed a later scan only when it is the exact same sample plan:
    /// identical planned seconds mean the same usable cache window produced them. A plan computed
    /// from an older cache frontier (or before a seek, or after eviction changed the ranges)
    /// planned different seconds, and its members must not join a fresh window's consensus, where
    /// they would veto agreement (owner session 2026-11-22: intro members carried into all 31
    /// later scans). Completed indecisive scans leave no progress at all - see finish.
    static func carryPlanReusable(undelivered: Bool, planned: [Double], plan: [Double]) -> Bool {
        undelivered || planned == plan
    }
    /// Whether a finished scan leaves its progress carry behind. finish runs only for completed
    /// scans, so completed indecisive evidence never seeds the next scan; a decisive-but-undelivered
    /// rect stays for handback, and an interrupted (cancelled) scan never reaches here.
    static func progressClearedOnCompletion(decisive: Bool, carryUndelivered: Bool) -> Bool {
        !decisive && !carryUndelivered
    }
    private var carry: Carry?
    private var newestKey: String?   // key of the most recently started stream scan: a stale scan may not store under another key
    private static let carryTTL: Double = 180   // seconds; older measurements are re-measured, never replayed
    private(set) var decodedWidth=0
    private(set) var decodedHeight=0
    private(set) var perEyeAspect:Double?
    private var lastDeliveredEpoch = -1   // epoch of the scan that last delivered a decisive result: an older scan may not store after it
    /// Forget everything carried (explicit manual Detect re-measures from scratch).
    /// Samples decoded so far by the scan now running (0 when none started or none decoded yet).
    private(set) var liveSamples = 0
    /// Set by every finished scan before its completion runs on main: true when an indecisive
    /// stream scan ended starved of non-black frames (fewer than the early-apply minimum, or no
    /// decodable samples), false when bright frames disagreed or the scan was decisive. The crop
    /// detector grows its automatic window level only on starvation; on disagreement the window
    /// stays at the cache frontier, which keeps advancing into fresh content on its own.
    private(set) var lastScanStarved = false
    /// True when a scan for the file on screen is already producing samples: a manual Detect then lets it finish
    /// instead of killing it (the capture showed repeated clicks cancelling every scan at 19-27 s of ~57 s).
    private var scanStartedAt:Double=0, scanDeadlineAt:Double=0, lastProgressAt:Double=0
    /// A single old sample is not proof that the worker is still making progress.
    func hasProgress() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let now=ProcessInfo.processInfo.systemUptime
        return liveSamples > 0 && now-lastProgressAt <= 20 && now-scanStartedAt <= 90 && scanDeadlineAt-now > 12
    }
    func dropCarry() { lock.lock(); if carry?.undelivered != true { carry = nil }; lock.unlock() }   // a decisive rect that was never delivered stays as the fallback for an indecisive manual scan
    // Caller holds lock. Ordinary cancel retains carry reuse; explicit freshness boundaries do not.
    private func mayStoreCancelledCarry(_ e:Int,_ key:String)->Bool {
        return e >= freshnessFloor && newestKey == key && e > lastDeliveredEpoch && (carry == nil || (carry?.key == key && (carry?.sampled ?? 0) == 0 && (carry?.ep ?? -1) < e))
    }
    /// A seek changes the measurement context, unlike an ordinary scan restart.
    /// Old cancelled finish callbacks cannot refill carry after this boundary.
    func invalidateMeasurementContext() {
        lock.lock();epoch += 1;freshnessFloor=epoch;carry=nil;newestKey=nil;let p=active;lock.unlock()
        if let p,p.isRunning {kill(p.processIdentifier,SIGKILL)}
    }
    func cancel() {
        lock.lock(); epoch += 1; let p = active; lock.unlock()
        if let p, p.isRunning { kill(p.processIdentifier,SIGKILL) }
    }
    private func valid(_ e: Int) -> Bool { lock.lock(); defer { lock.unlock() }; return epoch == e }
    // Typed execution seam. stderr is diagnostic data, never interpreted as commands.
    private enum ReadFailure:String {case cancelled,deadline,launch,oversized,exitStatus,incomplete}
    private struct ReadResult {
        let stdout:Data,stderr:Data,status:Int32
        let failure:ReadFailure?
    }
    private func run(_ binary: String, _ args: [String], epoch e: Int, cap: Int, killAfter: Double = 20) -> ReadResult {
        guard valid(e) else { return ReadResult(stdout:Data(),stderr:Data(),status: -1,failure:.cancelled) }
        guard killAfter > 0 else { return ReadResult(stdout:Data(),stderr:Data(),status: -1,failure:.deadline) }
        let readerArgs = CropHTTPReader.arguments(args)
        let args = URL(fileURLWithPath: binary).lastPathComponent == "ffmpeg" ? FFmpegAnalysisThreads.arguments(readerArgs) : readerArgs
        let p = Process(), out = Pipe(), err = Pipe()
        p.executableURL = URL(fileURLWithPath:binary); p.arguments = args
        // Background work: lowest priority (nice execs, same pid, so kill still hits ffmpeg).
        if FileManager.default.isExecutableFile(atPath:"/usr/bin/nice") { p.executableURL = URL(fileURLWithPath:"/usr/bin/nice"); p.arguments = ["-n","19",binary] + args }
        p.standardOutput = out; p.standardError = err; p.standardInput = FileHandle.nullDevice
        lock.lock(); guard epoch == e else { lock.unlock(); return ReadResult(stdout:Data(),stderr:Data(),status: -1,failure:.cancelled) }; active = p
        do { try p.run() } catch { active = nil; lock.unlock(); return ReadResult(stdout:Data(),stderr:Data(String(describing:error).utf8),status: -1,failure:.launch) }; lock.unlock()
        let timedOut=LockedData()
        let deadline = DispatchWorkItem { if p.isRunning { timedOut.append(Data([1]),cap:1); kill(p.processIdentifier,SIGKILL) } }
        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+killAfter,execute:deadline)
        let g = DispatchGroup(); let stderr = LockedData()
        g.enter(); DispatchQueue.global(qos:.utility).async {
            while true { let c = err.fileHandleForReading.availableData; if c.isEmpty { break }; stderr.append(c,cap:262144) }
            g.leave()
        }
        var data = Data(); var oversized = false
        while true {
            let c = out.fileHandleForReading.availableData; if c.isEmpty { break }
            if data.count + c.count <= cap { data.append(c) } else { oversized = true; if p.isRunning { kill(p.processIdentifier,SIGKILL) } }
        }
        p.waitUntilExit(); g.wait(); deadline.cancel()
        lock.lock(); if active === p { active = nil }; lock.unlock()
        let reason:ReadFailure? = !valid(e) ? .cancelled : oversized ? .oversized : !timedOut.value().isEmpty ? .deadline : p.terminationStatus != 0 ? .exitStatus:nil
        return ReadResult(stdout:data,stderr:stderr.value(),status:p.terminationStatus,failure:reason)
    }
    private final class LockedData {
        let lock = NSLock(); var data = Data()
        func append(_ c: Data, cap: Int) { lock.lock(); if data.count+c.count <= cap { data.append(c) }; lock.unlock() }
        func value() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
    func scan(path: String, duration: Double, stereo: Bool,topBottom:Bool=false, viewportOnly:Bool=false, caller: String = "", fresh: Bool = false, positions samplePositions:(()->[Double]?)?=nil, interim: ((CGRect, Double)->Void)? = nil, completion: @escaping (CGRect?,Bool,Double)->Void) {
        cancel(); perEyeAspect=nil; lastScanStarved=false
        let started=ProcessInfo.processInfo.systemUptime
        let stream=CropDetector.isWTPlayback(path) || TransferProbeAdmission.isSource(path)
        let expires=started + (stream ? 90:240)
        lock.lock(); let e = epoch; liveSamples = 0;scanStartedAt=started;scanDeadlineAt=expires;lastProgressAt=0; lock.unlock()
        DispatchQueue.global(qos:.utility).async { [weak self] in
            guard let self else { return }
            var lastFailure="none"
            func failure(_ reason:String) {
                lastFailure=reason
                print("[cropdetect] read failure epoch=\(e) reason=\(reason)")
            }
            // Only transfer relay probes wait. The worker is cancellable throughout;
            // no process exists and no upstream range is opened while deferred.
            func decode(_ binary: String, _ args: [String], epoch: Int, cap: Int, killAfter: Double) -> (Data,Data,Int32)? {
                var deferred = false
                while !TransferProbeAdmission.admits(path) {
                    guard self.valid(e) else { failure("cancelled");return nil }
                    guard ProcessInfo.processInfo.systemUptime < expires else { failure("deadline: admission");return nil }
                    if !deferred { print("[cropdetect] transfer probe deferred: forward buffer below 15s or stale/stalled"); deferred = true }
                    Thread.sleep(forTimeInterval: 0.25)
                }
                if deferred { print("[cropdetect] transfer probe admitted: forward buffer healthy") }
                let remaining=expires-ProcessInfo.processInfo.systemUptime
                guard remaining > 0 else { failure("deadline: before open");return nil }
                let result=self.run(binary,args,epoch:epoch,cap:cap,killAfter:min(killAfter,remaining))
                if let why=result.failure {
                    let diagnostic=String(decoding:result.stderr.prefix(2048),as:UTF8.self).replacingOccurrences(of:"\n",with:" ")
                    failure("\(why.rawValue) status=\(result.status) stderr=\(diagnostic)")
                    return nil
                }
                return (result.stdout,result.stderr,result.status)
            }
            let ffmpeg = GORResources.vendorPath("ffmpeg/bin/ffmpeg")
            let ffprobe = GORResources.vendorPath("ffmpeg/bin/ffprobe")
            let wt: Bool = stream   // explicit source identity, never closure existence
            let rwTimeout: String = wt ? "10000000" : "5000000"   // allow a slow cached piece, bounded below the12s open watchdog
            let killAfter: Double = wt ? 12 : 20
            let key = "\(path)|\(stereo)|\(topBottom)|\(Int(duration.rounded()))"
            var idDims = ""   // set once the stream is probed
            func carryUsable(_ c: Carry?) -> Carry? { guard let c, c.key == key, ProcessInfo.processInfo.systemUptime - c.at <= SourcePixelCropScanner.carryTTL else { return nil }; return c }
            print("[cropdetect] scan start caller=\(caller.isEmpty ? "?" : caller) wt=\(wt) stereo=\(stereo) file=\((path as NSString).lastPathComponent)")
            func finish(_ rect: CGRect?, _ decisive: Bool, _ why: String = "", starved: Bool = false) {
                DispatchQueue.main.async {
                    if self.valid(e) {
                        self.lastScanStarved = !decisive && starved
                        self.lock.lock(); let c = self.carry; if decisive { self.carry = nil; self.lastDeliveredEpoch = e }; self.lock.unlock()
                        if !decisive, wt, let c = carryUsable(c), c.undelivered {
                            print("[cropdetect] scan ended without a result (\(why)); delivering the decisive rect measured earlier")
                            self.lock.lock(); self.carry = nil; self.lock.unlock(); completion(c.rect,true,1); return
                        }
                        if wt { self.lock.lock(); if SourcePixelCropScanner.progressClearedOnCompletion(decisive: decisive, carryUndelivered: self.carry?.undelivered == true) { self.carry = nil }; self.lock.unlock() }   // a completed indecisive scan leaves no progress behind; only an interrupted scan's exact same-plan progress may seed a later scan
                        if !decisive { print("[cropdetect] scan finished indecisive: \(why.isEmpty ? "no reason recorded" : why)") }
                        completion(rect,decisive,decisive ? 1 : 0)
                    } else if decisive, wt, !stereo {
                        self.lock.lock()
                        let mine = self.mayStoreCancelledCarry(e,key)   // never overwrite another file's or a newer scan's carry
                        if mine { self.carry = Carry(key: key, dims: idDims, at: ProcessInfo.processInfo.systemUptime, bounds: nil, members: [], sampled: 0, undelivered: true, rect: rect, done: [], ep: e, planned: []) }
                        self.lock.unlock()
                        print(mine ? "[cropdetect] decisive result was cancelled before delivery; kept for the next scan of this file" : "[cropdetect] decisive result was cancelled before delivery and a newer scan owns the state; dropped")
                    }
                }
            }
            // A partial stream must never fall back to the local whole-file plan.
            // Resolve cache admission before opening ffprobe/ffmpeg or reading metadata.
            let overridePositions: [Double]? = samplePositions?()
            let planPositions: [Double] = overridePositions ?? []
            if wt {
                let admitted = overridePositions ?? []
                guard admitted.count >= SourcePixelBounds.earlyMinCount,
                      admitted.allSatisfy({ $0.isFinite && $0 >= 0 }),
                      Set(admitted).count >= SourcePixelBounds.earlyMinCount else {
                    finish(nil,false,"downloaded sample plan unavailable; no source probe opened")
                    return
                }
            }
            self.lock.lock(); guard self.epoch==e else {self.lock.unlock();return}; var c0: Carry? = wt ? carryUsable(self.carry) : nil; let keepFallback: Bool = fresh && c0?.undelivered == true; if fresh { c0 = nil }; if let c = c0, !SourcePixelCropScanner.carryPlanReusable(undelivered: c.undelivered, planned: c.planned, plan: planPositions) { c0 = nil }; if wt { if c0 == nil && !keepFallback { self.carry = nil }; self.newestKey = key }; self.lock.unlock()
            guard FileManager.default.isExecutableFile(atPath:ffmpeg) else { finish(nil,false,"ffmpeg not executable"); return }
            var w=0,h=0,d=duration,pix="",range="",sar=1.0
            var rangeExplicit=false
            if FileManager.default.isExecutableFile(atPath:ffprobe),
               let probe=decode(ffprobe,["-v","error","-rw_timeout",rwTimeout,"-select_streams","v:0","-show_streams","-show_format","-of","json",path],epoch:e,cap:262144,killAfter:killAfter),probe.2==0,
               let root=try? JSONSerialization.jsonObject(with:probe.0) as? [String:Any],
               let stream=(root["streams"] as? [[String:Any]])?.first {
                w=stream["width"] as? Int ?? 0;h=stream["height"] as? Int ?? 0
                let format=root["format"] as? [String:Any]
                d=Double(format?["duration"] as? String ?? "") ?? duration
                let parts=(stream["sample_aspect_ratio"] as? String ?? "1:1").split(separator:":").compactMap{Double($0)}
                if parts.count==2,parts[1]>0 {sar=parts[0]/parts[1]}
                pix=stream["pix_fmt"] as? String ?? "";range=stream["color_range"] as? String ?? ""
                rangeExplicit = range == "tv" || range == "pc"
            } else {
                // ffprobe is optional in the owner's vendor. ffmpeg itself supplies decoder metadata,
                // without installing another binary or using post-render video params.
                guard let meta=decode(ffmpeg,["-hide_banner","-nostdin","-hwaccel","none","-rw_timeout",rwTimeout,"-i",path,"-map","0:v:0","-frames:v","0","-an","-sn","-f","null","-"],epoch:e,cap:4096,killAfter:killAfter) else { finish(nil,false,"probe and metadata open failed: \(lastFailure)");return }
                let text=String(data:meta.1,encoding:.utf8) ?? ""
                guard let line=text.components(separatedBy:"\n").first(where:{$0.contains("Stream #") && $0.contains("Video:")}) else {finish(nil,false,"no video stream line in metadata");return}
                func captures(_ pattern:String,_ text:String) -> [String] {
                    guard let re=try? NSRegularExpression(pattern:pattern),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else{return []}
                    return (1..<m.numberOfRanges).compactMap {Range(m.range(at:$0),in:text).map{String(text[$0])}}
                }
                let size=captures(#"(?:,| )([0-9]{2,5})x([0-9]{2,5})(?:[ ,\[])"#,line)
                guard size.count==2 else {finish(nil,false,"no frame size in metadata");return}
                w=Int(size[0]) ?? 0;h=Int(size[1]) ?? 0
                pix=captures(#", ([a-z0-9]+)(?:\(|,)"#,line).first ?? ""
                range=line.contains("(pc") ? "pc" : "tv"
                rangeExplicit = line.contains("(pc") || line.contains("(tv")
                if d<=0 {
                    let times=captures(#"Duration: ([0-9]+):([0-9]+):([0-9.]+)"#,text)
                    if times.count==3 {d=(Double(times[0]) ?? 0)*3600+(Double(times[1]) ?? 0)*60+(Double(times[2]) ?? 0)}
                }
            }
            guard w>0,h>0,w<=16384,h<=16384,w*h<=50000000 else {finish(nil,false,"unusable frame size \(w)x\(h)");return}
            idDims = "\(w)x\(h) \(pix) \(range)"
            if let c = c0, c.dims != "" , c.dims != idDims {   // same path/duration but a different stream: nothing carried applies
                print("[cropdetect] carried measurement is for a different stream (\(c.dims) vs \(idDims)); discarded")
                c0 = nil; self.lock.lock(); self.carry = nil; self.lock.unlock()
            }
            if let c = c0, c.undelivered { print("[cropdetect] replaying the decisive rect measured earlier (same file, \(idDims), probed just now)"); finish(c.rect,true); return }
            let decodedW=w,decodedH=h
            DispatchQueue.main.async { if self.valid(e) { self.decodedWidth=decodedW;self.decodedHeight=decodedH } }
            let bits:Int = pix.contains("16") ? 16 : pix.contains("14") ? 14 : pix.contains("12") ? 12 : pix.contains("10") ? 10 : pix.contains("9") ? 9 : 8
            let full=range=="pc" || pix.hasPrefix("yuvj") || pix.hasPrefix("rgb") || pix.hasPrefix("gbr") || pix.hasPrefix("gray")
            let black=full ? 0 : 16*(1 << max(0,bits-8))
            // Margins are 8-bit-equivalent luma levels: +2 / +12 levels at ANY bit depth. They used to be raw codes, which at 10 bit
            // is only 0.5 / 3 levels, so a dithered or HDR->SDR near-black letterbox bar (a few codes above black) read as picture.
            let levelUnit = 1 << max(0,bits-8)
            let threshold=UInt16(min(65535,(black+2*levelUnit)*(1 << max(0,16-bits))))
            let strongThreshold=UInt16(min(65535,(black+12*levelUnit)*(1 << max(0,16-bits))))   // clearly non-black: never ignored as a speck
            // Bar floor test: a bar row stays near-black over the floor. A row is content when any pixel is clearly
            // above the floor (strong, +12 levels) or more than ~0.2% of it exceeds the +2-level margin, so isolated
            // encode-noise pixels inside a bar never move the bound and it lands exactly at the bar/picture step.
            // Dark HDR picture rows (8-bit-eq mean ~30, max ~61 8-bit-eq) are content by both tests, never bar.
            let speckTolerance = max(1, w / 512)
            // Split into typed statements: one nil-coalescing + ternary + map-closure expression made the compiler time out.
            var positions: [Double] = [0.0]
            if let op = overridePositions { positions = op }
            else if d > 0 { positions = [0.0] + (1..<40).map { (i: Int) -> Double in let x: Double = d * Double(i); let y: Double = x / 40.0; return max(0.0, min(d - 0.001, y)) } }
            // Opening phase: frame0 starts immediately, followed by distant confirmations.
            // Reorder the same whole-file targets, never infer bars from an adjacent dark intro.
            // Three agreeing source frames can publish before the remaining37 finish.
            let localOpening = !wt && !fresh && !stereo && overridePositions == nil
            if localOpening, positions.count >= 3 {
                let openingIndices = [0, positions.count - 1, positions.count / 2]
                positions = openingIndices.map { positions[$0] } + positions.enumerated().filter { !openingIndices.contains($0.offset) }.map { $0.element }
            }
            if wt, let c = c0, c.sampled > 0 {
                let unseen: [Double] = positions.filter { (p: Double) -> Bool in !c.done.contains { (d: Double) -> Bool in abs(d - p) < 4 } }   // new frames, not repeats of carried ones
                let pool: [Double] = unseen.count >= 3 ? unseen : positions
                positions = Array(pool.prefix(max(3, positions.count - c.sampled)))
            }
            let transferBatching = TransferProbeAdmission.isSource(path)
            var wtBatching = CropDetector.isWTPlayback(path) // same bounded cached source, not a rendered screenshot
            if transferBatching { positions.sort() } // same exact positions, bounded chronological container reuse
            var batchedFrames: [Double: Data] = [:]
            var done: [Double] = c0?.done ?? []
            let window: Double = (positions.max() ?? 0) - (positions.min() ?? 0)   // samples carried from a cancelled scan count: repeated restarts converge instead of re-measuring everything
            var all: SourcePixelBounds.Bounds? = c0?.bounds; var sampled: Int = c0?.sampled ?? 0   // carried samples from an interrupted scan of the same stream
            var halves:[SourcePixelBounds.Bounds]?
            var members: [SourcePixelBounds.Bounds] = c0?.members ?? []; var interimSent = false; var publishedLocalBounds: SourcePixelBounds.Bounds?; let scanStart = ProcessInfo.processInfo.systemUptime; var sampleSum = 0.0, sampleN = 0
            let rgbVeto = pix.hasPrefix("rgb") || pix.hasPrefix("bgr") || pix.hasPrefix("gbr") || pix.isEmpty
            let scanDeadline=expires // includes queue, admission, probing and every decode
            for (positionIndex, t) in positions.enumerated() {
                guard self.valid(e) else { print("[cropdetect] scan cancelled mid-run after \(sampled) of \(positions.count) samples (new scan or cancel)"); return }
                if ProcessInfo.processInfo.systemUptime>=scanDeadline { break }
                // Software decode only. cropdetect runs on original decoded samples, no crop/scale/shader.
                // yuv444p16le preserves full-resolution luma code values for the exact safety veto.
                let vf = "cropdetect=limit=\(black+2):round=2:reset=0:skip=0"
                let sourceGray=pix.hasPrefix("gray")
                // The exact veto, stereo bounds and edge diagnostics read ONLY Y.
                // First make the very same YUV16 samples as the old output, then
                // extract Y without range expansion or downscale. RGB stays on
                // the old path and remains vetoed, never guessed from luma.
                let extractLuma = !sourceGray && !rgbVeto
                let outputGray = sourceGray || extractLuma
                let rawPixelFormat=outputGray ? "gray16le" : "yuv444p16le"
                // Limited-range YUV only. Extract Y before conversion so the
                // discarded chroma is not upsampled to 4:4:4/16-bit first.
                // Explicit limited->limited conversion preserves the old Y
                // codes only when source range and tested pixel format are explicit.
                // Full-range retains the old path: its direct-gray codes differ.
                let fastLuma = rangeExplicit && range == "tv" && ["yuv420p","yuv422p","yuv444p","yuv420p10le","yuv422p12le","yuv444p16le"].contains(pix)
                let lumaTail = fastLuma ? ",extractplanes=y,scale=in_range=tv:out_range=tv,format=gray16le" : ",format=yuv444p16le,extractplanes=y"
                let outputFilter = extractLuma ? vf + lumaTail : vf
                let expectedBytes=w*h*(outputGray ? 2 : 6)
                let args = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(t),"-i",path,"-map","0:v:0","-an","-sn","-dn","-vf",outputFilter,"-frames:v","1","-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                let sampleBegan = ProcessInfo.processInfo.systemUptime
                if transferBatching, batchedFrames[t] == nil {
                    let batch = TransferProbeAdmission.cropBatch(positions,index:positionIndex,frameBytes:expectedBytes)
                    if batch.count > 1, let first = batch.first, let last = batch.last {
                        let select = TransferProbeAdmission.cropSelection(batch)
                        let batchArgs = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(first),"-i",path,"-t",String(last-first+0.5),"-map","0:v:0","-an","-sn","-dn","-vf","select='\(select)',\(outputFilter)","-vsync","0","-frames:v",String(batch.count),"-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                        if let decoded = decode(ffmpeg,batchArgs,epoch:e,cap:expectedBytes*batch.count+65536,killAfter:killAfter), decoded.2 == 0, decoded.0.count == expectedBytes*batch.count {
                            for (i, at) in batch.enumerated() { batchedFrames[at] = decoded.0.subdata(in:i*expectedBytes..<(i+1)*expectedBytes) }
                            print("[cropdetect] transfer container batch frames=\(batch.count) span_s=\(last-first) opens=1")
                        } else { print("[cropdetect] transfer container batch incomplete; bounded single-frame fallback") }
                    }
                }
                if wtBatching, batchedFrames[t] == nil {
                    let cachedBytes = batchedFrames.values.reduce(0) { $0 + $1.count }
                    let pending = Array(positions[positionIndex...]).filter { batchedFrames[$0] == nil }
                    let batch = BoundedCropFrameBatch.plan(pending, current:t,
                        frameBytes:expectedBytes, cachedBytes:cachedBytes)
                    if batch.count > 1, let first=batch.first, let last=batch.last {
                        let select = BoundedCropFrameBatch.selection(batch)
                        let batchArgs = ["-hide_banner","-loglevel","info","-nostdin","-noautorotate","-hwaccel","none","-rw_timeout",rwTimeout,"-threads","2","-ss",String(first),"-i",path,"-t",String(last-first+0.5),"-map","0:v:0","-an","-sn","-dn","-vf","select='\(select)',\(outputFilter)","-vsync","0","-frames:v",String(batch.count),"-pix_fmt",rawPixelFormat,"-f","rawvideo","pipe:1"]
                        if let decoded=decode(ffmpeg,batchArgs,epoch:e,cap:expectedBytes*batch.count+65536,killAfter:killAfter),
                           decoded.2 == 0, decoded.0.count == expectedBytes*batch.count {
                            for (i,at) in batch.enumerated() {
                                batchedFrames[at]=decoded.0.subdata(in:i*expectedBytes..<(i+1)*expectedBytes)
                            }
                            print("[cropdetect] wt bounded batch frames=\(batch.count) span_s=\(last-first) opens=1 cache_bytes=\(cachedBytes+expectedBytes*batch.count)")
                        } else {
                            wtBatching = false // at most one failed batch; never repeated speculative opens
                            print("[cropdetect] wt batch incomplete; original single-target fallback for rest of scan")
                        }
                    }
                }
                let decoded: (Data,Data,Int32)?
                if let frame = batchedFrames.removeValue(forKey:t) { decoded = (frame,Data(),0) }
                else { decoded = decode(ffmpeg,args,epoch:e,cap:expectedBytes+65536,killAfter:killAfter) }
                guard let decoded, decoded.2 == 0, decoded.0.count == expectedBytes else {
                    if let decoded { failure("\(ReadFailure.incomplete.rawValue) expected=\(expectedBytes) received=\(decoded.0.count) status=\(decoded.2)") }
                    print("[cropdetect] sample failed epoch=\(e) position=\(t) reason=\(lastFailure)")
                    continue
                }
                sampleSum += ProcessInfo.processInfo.systemUptime - sampleBegan; sampleN += 1
                done.append(t); sampled += 1; self.lock.lock(); if self.epoch == e { self.liveSamples = sampled;self.lastProgressAt=ProcessInfo.processInfo.systemUptime }; self.lock.unlock()
                // A fully black sampled frame adds no content. An unreadable frame is not claimed sampled.
                if stereo,let current=SourcePixelBounds.scanHalves(decoded.0,width:w,height:h,threshold:threshold,topBottom:topBottom) {
                    halves=halves.map{[$0[0].union(current[0]),$0[1].union(current[1])]} ?? current
                }
                if let b = SourcePixelBounds.scan(decoded.0,width:w,height:h,threshold:threshold,speck:speckTolerance,strong:strongThreshold) {
                    all = all.map { $0.union(b) } ?? b
                    print("[cropdetect] edge rows sample=\(sampled) t=\(Int(t))s bounds y=\(b.y0)..\(b.y1) (8-bit-eq mean/max, black=\(black), levelUnit=\(levelUnit)): \(SourcePixelBounds.edgeRows(decoded.0,width:w,height:h,bounds:b,black:black,bits:bits,gray:outputGray))")
                    if wt || localOpening, !stereo, !rgbVeto { members.append(b); if members.count > 12 { members.removeFirst() } }
                }
                // Speed: apply as soon as three frames agree, then keep refining (the union only widens).
                // An early apply needs agreement, never a time budget: fewer than earlyMinCount agreeing non-black
                // frames is no early decision. The scan keeps refining and the final union over all frames decides.
                let consensus: SourcePixelBounds.Bounds? = SourcePixelBounds.consistent(members)
                // Overcut guard: the frames behind an early apply must span at least half of the planned window, so one quiet corner of the cache cannot define the crop.
                let covered: Double = (done.max() ?? 0) - (done.min() ?? 0)
                let best: SourcePixelBounds.Bounds? = window > 0 && covered < 0.5 * window ? nil : consensus
                if wt || localOpening, !stereo, !rgbVeto, !interimSent, let interim, let u0 = best {
                    let u: SourcePixelBounds.Bounds = all.map { $0.union(u0) } ?? u0   // never narrower than everything measured so far (members is capped at 12, all is not)
                    let ci = SourcePixelBounds.outward(u,width:w,height:h,stereo:stereo,topBottom:topBottom)
                    if !(ci.x0 == 0 && ci.y0 == 0 && ci.x1 == w && ci.y1 == h) {
                        interimSent = true
                        if localOpening { publishedLocalBounds = ci }
                        let ir = CGRect(x:Double(ci.x0)/Double(w),y:Double(ci.y0)/Double(h),width:Double(ci.x1-ci.x0)/Double(w),height:Double(ci.y1-ci.y0)/Double(h))
                        print("[cropdetect] early apply after \(sampled) samples (\(members.count) non-black, agree): bounds=\(ci.x0),\(ci.y0)-\(ci.x1),\(ci.y1) of \(w)x\(h); refining on the remaining samples")
                        DispatchQueue.main.async { if self.valid(e) { interim(ir, -1) } }   // confidence < 0 marks an early apply (the final result still follows)
                    }
                }
                // Once opening bars are shown, any later sampled picture outside them widens
                // immediately. No new consensus can delay restoration of measured picture pixels.
                if localOpening, let previous = publishedLocalBounds, let all, let interim {
                    let widened = SourcePixelBounds.outward(all.union(previous),width:w,height:h,stereo:false)
                    if widened != previous {
                        publishedLocalBounds = widened
                        let rect = CGRect(x:Double(widened.x0)/Double(w),y:Double(widened.y0)/Double(h),width:Double(widened.x1-widened.x0)/Double(w),height:Double(widened.y1-widened.y0)/Double(h))
                        DispatchQueue.main.async { if self.valid(e) { interim(rect,-1) } }
                    }
                }
                if wt, !stereo { self.lock.lock(); if self.epoch == e && !(self.carry?.undelivered == true && self.carry?.key == key) { self.carry = Carry(key: key, dims: idDims, at: ProcessInfo.processInfo.systemUptime, bounds: all, members: members, sampled: sampled, undelivered: false, rect: nil, done: done, ep: e, planned: planPositions) }; self.lock.unlock() }   // progress survives a cancel
            }
            let needSamples: Int = samplePositions == nil ? 1 : min(3, positions.count)
            guard sampled >= needSamples, let b = all else { print("[cropdetect] scan produced no samples: positions=\(positions.count) \(w)x\(h) \(pix)"); finish(nil,false,"\(sampled) of \(needSamples) needed samples decoded; lastFailure=\(lastFailure) deadline=\(ProcessInfo.processInfo.systemUptime >= expires)",starved:true); return }
            // RGB -> luma conversion can hide a chromatic nonblack source pixel. Until exact RGB
            // bounds are supported, veto crop rather than claim original-pixel preservation there.
            if pix.hasPrefix("rgb") || pix.hasPrefix("bgr") || pix.hasPrefix("gbr") || pix.isEmpty {
                finish(nil,true);return
            }
            // An automatic stream scan decides like the early path: fewer than earlyMinCount agreeing non-black
            // frames is no decision. The file stays at the full frame (the frame is sacred); the player-side
            // persistent search re-scans +2s, +5s, +10s, then every 30s while playing, and restarts at once on
            // seek, resolution/aspect change, track switch and cache growth past the scanned range (199az).
            // Manual Detect (fresh) keeps the union rule, and non-stream sources are unchanged.
            if wt, !stereo, !rgbVeto, !fresh, SourcePixelBounds.consistent(members) == nil {
                print("[cropdetect] no agreement among \(members.count) non-black frames - full picture kept, search continues")
                finish(nil,false,"no agreement among \(members.count) non-black frames",starved: members.count < SourcePixelBounds.earlyMinCount);return
            }
            if let eyes=halves {
                let common=eyes[0].union(eyes[1])
                let sx=topBottom ? 1.0 : (Double(w)/Double(h)>=3 ? 1.0:2.0)
                let aspect=Double(common.x1-common.x0)*sx*sar/Double(common.y1-common.y0)
                DispatchQueue.main.async {if self.valid(e){self.perEyeAspect=aspect}}
            }
            let c = SourcePixelBounds.outward(b,width:w,height:h,stereo:stereo,topBottom:topBottom)
            let rect = CGRect(x:Double(c.x0)/Double(w),y:Double(c.y0)/Double(h),
                              width:Double(c.x1-c.x0)/Double(w),height:Double(c.y1-c.y0)/Double(h))
            print("[cropdetect] scan done: sampled=\(sampled)/\(positions.count) bounds=\(c.x0),\(c.y0)-\(c.x1),\(c.y1) of \(w)x\(h) override=\(samplePositions != nil)")
            GeomTrace.log("sourceCrop", "{\"k\":\"sourceCrop\",\"samples\":\(sampled),\"requested\":40,\"unsampledMayBeCut\":true,\"sbs\":\(stereo),\"sbsHorizontalPreserved\":true}")
            if viewportOnly,stereo,let eyes=halves,let viewport=SourcePixelBounds.eyeViewport(eyes,width:w,height:h,topBottom:topBottom) {
                print("[cropdetect] verified per-eye viewport \(viewport) source pixels unchanged")
                finish(viewport == CGRect(x:0,y:0,width:1,height:1) ? nil:viewport,true)
            } else {finish(c.x0 == 0 && c.y0 == 0 && c.x1 == w && c.y1 == h ? nil : rect,true)}
        }
    }
}
enum WTCropSamples {
    static let sampleCount = 12
    /// Distance kept from the end of a range so the one frame decoded after the seek is also downloaded.
    static let tailMargin = 1.5
    static let minRange = 3.0

    /// Cache tail used when the player cannot report a playhead: the newest downloaded seconds. Film start and end
    /// credits are usually black; what was downloaded last is the part most likely to show the real picture.
    static let tailWindow = 240.0
    /// Manual Detect looks this far either side of the frame on screen.
    static let manualHalfSpan = 12.0
    /// Automatic scans cover the newest `2 * autoBaseHalfSpan * 2^widenLevel` seconds of the downloaded
    /// cache, anchored at its frontier (the furthest downloaded second): 24 s, then 48 s, 96 s, ... reaching
    /// backwards. Narrowest window first: the newest seconds are the freshest evidence, and while they
    /// disagree the frontier itself keeps advancing into new content, so the level grows only when the
    /// newest window was starved of bright frames - never because mixed old/new content disagreed, since
    /// reaching further back is what fed intro cards into the sample set. The applied crop only ever
    /// widens and a seek restarts the search (199az), so an early apply from a narrow window cannot
    /// permanently cut a wider geometry that is buffered behind it. The sample count never grows with the window.
    static let autoBaseHalfSpan = 12.0

    /// Usable seconds of each downloaded range (tail margin kept), sorted by start.
    static func usable(_ ranges: [(Double, Double)]) -> [(Double, Double)] {
        ranges.filter { $0.0.isFinite && $0.1.isFinite && $0.1 - $0.0 >= minRange }
            .map { (max(0, $0.0), $0.1 - tailMargin) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }
    }

    /// Evenly spaced positions over the union length of the given segments (chronological order).
    static func spread(_ segs: [(Double, Double)], count: Int) -> [Double] {
        let total = segs.reduce(0.0) { $0 + ($1.1 - $1.0) }
        guard total > 0, count > 0 else { return [] }
        var out: [Double] = []
        for i in 0..<count {
            var u = total * (Double(i) + 0.5) / Double(count)
            for r in segs {
                let len = r.1 - r.0
                if u <= len { out.append(r.0 + u); break }
                u -= len
            }
        }
        return out
    }

    /// Pure: evenly spaced positions over the union length of the usable ranges. Empty when no range is usable.
    static func positions(ranges: [(Double, Double)], count: Int = sampleCount) -> [Double] {
        spread(usable(ranges), count: count)
    }

    /// Sampling order: start at the sample nearest `seed` (newest frame for automatic scans, the frame on screen for manual), then
    /// always take the sample farthest from those already taken. The first three frames therefore span the whole window, so an early
    /// apply cannot be decided by one quiet corner of the cache.
    static func spreadOrder(_ ps: [Double], seed: Double) -> [Double] {
        var rest: [Double] = ps
        var out: [Double] = []
        guard let si = rest.indices.min(by: { (a: Int, b: Int) -> Bool in abs(rest[a] - seed) < abs(rest[b] - seed) }) else { return [] }
        out.append(rest.remove(at: si))
        while !rest.isEmpty {
            let taken: [Double] = out
            let gaps: [Double] = rest.map { (p: Double) -> Double in taken.map { (t: Double) -> Double in abs(t - p) }.min() ?? 0 }
            guard let fi = gaps.indices.max(by: { (a: Int, b: Int) -> Bool in gaps[a] < gaps[b] }) else { break }
            out.append(rest.remove(at: fi))
        }
        return out
    }

    /// Pure plan for a stream scan. Manual: around the playhead (the frame the user sees), inside the downloaded range
    /// nearest to it, nearest samples first. Automatic: the newest `2 * autoBaseHalfSpan * 2^widenLevel` seconds of the
    /// downloaded cache, anchored at the frontier (the furthest downloaded second), intersected with the downloaded
    /// ranges, newest samples first; no playhead needed. Manual with no reported playhead: the last `tailWindow`
    /// seconds of the downloaded ranges, newest first. Every position
    /// is inside a downloaded range with the tail margin kept. Empty when nothing is usable.
    static func plan(ranges: [(Double, Double)], playhead: Double?, manual: Bool, count: Int = sampleCount, widenLevel: Int = 0) -> [Double] {
        let segs = usable(ranges)
        guard !segs.isEmpty, count > 0 else { return [] }
        if manual, let now = playhead, now.isFinite {
            func dist(_ r: (Double, Double)) -> Double { now < r.0 ? r.0 - now : (now > r.1 ? now - r.1 : 0) }
            guard let r = segs.min(by: { dist($0) < dist($1) }) else { return [] }
            let c = min(max(now, r.0), r.1)
            let lo = max(r.0, c - manualHalfSpan), hi = min(r.1, c + manualHalfSpan)
            guard hi > lo else { return [] }
            return spreadOrder(spread([(lo, hi)], count: count), seed: c)
        }
        if !manual {
            // Automatic: anchor at the cache frontier, the furthest actually usable downloaded
            // second, and look backwards from it; the playhead is not consulted. The newest
            // content is the freshest evidence about the file's bars - intro cards sit at the old
            // end of the cache, and a playhead-anchored window kept spreading samples across them
            // (owner session 2026-11-22: 31 indecisive automatic scans while the cache grew to
            // 120 s; manual Detect around the playhead was decisive within seconds).
            // The frontier end is the MAXIMUM usable end, never merely the last listed range.
            guard let frontier = segs.map({ $0.1 }).max(), frontier > 0 else { return [] }
            let span = 2 * autoBaseHalfSpan * pow(2.0, Double(max(0, widenLevel)))
            let lo = frontier - span
            let win: [(Double, Double)] = segs.compactMap { (s: (Double, Double)) -> (Double, Double)? in
                let a = max(s.0, lo), b = min(s.1, frontier)
                return b > a ? (a, b) : nil
            }
            guard !win.isEmpty else { return [] }
            return spreadOrder(spread(win, count: count), seed: frontier)
        }
        var tail: [(Double, Double)] = []
        var left = tailWindow
        for r in segs.reversed() {
            let take = min(r.1 - r.0, left)
            tail.append((r.1 - take, r.1)); left -= take
            if left <= 0 { break }
        }
        let picked: [Double] = spread(tail.reversed(), count: count)
        return spreadOrder(picked, seed: picked.max() ?? 0)
    }

    /// Raw frontier identity of a dispatch: the furthest range end the player reported, in the SAME
    /// coordinate PPController's cache poll uses (maximum raw `end`, no tail margin, no minRange
    /// filter). Never a sample midpoint: at 24 s/12 samples/tail 1.5 the newest midpoint sits more
    /// than 2 s behind the raw end, so booking the midpoint as the scanned end makes the +2 s growth
    /// rule fire on an unchanged cache (Ops bounded execution 2026-11-22: ranges [0,24] -> plan max
    /// 21.5625, 24 > 23.5625 true with zero growth).
    static func rawFrontierEnd(_ ranges: [(Double, Double)]) -> Double? {
        ranges.compactMap { $0.0.isFinite && $0.1.isFinite ? $0.1 : nil }.max()
    }

    /// Positions for a wt playback path from the running player; plan nil for any other source (scanner keeps its
    /// whole-file positions) or when the player cannot say anything about what is downloaded. The raw frontier
    /// end is the dispatch coverage identity for PPController's growth rule, in the poll's own coordinate.
    static func positions(path: String, mainIPCPath: String?, manual: Bool = false, widenLevel: Int = 0) -> (plan: [Double]?, rawFrontierEnd: Double?) {
        guard (CropDetector.isWTPlayback(path) || TransferProbeAdmission.isSource(path)), let ipc = mainIPCPath else { return (nil, nil) }
        let client = IPCClient(path: ipc)
        func property(_ name: String) -> Any? {
            IPCClient.parseFirst(client.queryBatch(MPVCommand.make(["get_property", name]), timeout: 0.5))["data"]
        }
        var ranges: [(Double, Double)] = []
        if let state = property("demuxer-cache-state") as? [String: Any],
           let list = state["seekable-ranges"] as? [[String: Any]] {
            ranges = list.compactMap {
                guard let a = ($0["start"] as? NSNumber)?.doubleValue, let b = ($0["end"] as? NSNumber)?.doubleValue else { return nil }
                return (a, b)
            }
        }
        let playhead = (property("time-pos") as? NSNumber)?.doubleValue
        let frontier = rawFrontierEnd(ranges)
        let spread = plan(ranges: ranges, playhead: playhead, manual: manual, widenLevel: widenLevel)
        // One line per scan so a capture shows what the player said was on disk and where the scan will look.
        let span = ranges.map { String(format: "%.0f-%.0f", $0.0, $0.1) }.joined(separator: ",")
        let hasPlayhead = (playhead ?? .nan).isFinite
        let mode = manual ? (hasPlayhead ? "manual-around-playhead" : "cache-tail") : "auto-cache-frontier"
        print("[cropdetect] wt samples: ranges=[\(span)] positions=\(spread.count) mode=\(mode) playhead=\(playhead.map { String(format: "%.1f", $0) } ?? "?") widen=\(manual ? 0 : max(0, widenLevel))")
        if !spread.isEmpty { return (spread, frontier) }
        if let now = (property("time-pos") as? NSNumber)?.doubleValue, now.isFinite, now >= 0 { return (playedFallback(now: now), frontier) }
        return (nil, frontier)
    }
}
