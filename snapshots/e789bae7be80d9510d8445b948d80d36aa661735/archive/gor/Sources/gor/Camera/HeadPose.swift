import Foundation

// MARK: - PoseContinuity
/// Six channels, independent velocity histories. A one-frame impulse is dropped before filtering.
struct PoseContinuity {
    private var previous:[Double]?, previousT:Double?
    private var velocities=[[Double]](repeating:[],count:6)
    private var held=[Double](repeating:0,count:6)
    private var pendingOutliers=[Bool](repeating:false,count:6)
    private var lost=false, reacquireAt:Double?, reacquireFrom=[Double](repeating:0,count:6)
    mutating func faceLost() { lost=true }
    mutating func accept(_ raw:[Double],t:Double,heldChannels:Set<Int>=[]) -> (values:[Double],outlier:Bool,reacquire:Bool) {
        guard raw.count==6,raw.allSatisfy({$0.isFinite}),t.isFinite else { return (held,true,false) }
        var values=raw; var dropped=false
        if let prev=previous, let pt=previousT, t>pt, t-pt<0.25, !lost {
            let dt=t-pt
            for i in 0..<6 {
                if heldChannels.contains(i) {values[i]=prev[i];continue}
                let v=(raw[i]-prev[i])/dt, h=velocities[i]
                if h.count>=12 {
                    let mean=h.reduce(0,+)/Double(h.count)
                    let variance=h.reduce(0) {$0+($1-mean)*($1-mean)}/Double(h.count)
                    let sigma=sqrt(variance)
                    if abs(v-mean)>4*max(sigma,1e-6), !pendingOutliers[i] {
                        pendingOutliers[i]=true;values[i]=prev[i];dropped=true;continue
                    }
                    pendingOutliers[i]=false
                }
                velocities[i].append(v)
                if velocities[i].count>60 { velocities[i].removeFirst() }
            }
        }
        if lost { reacquireAt=t;reacquireFrom=held;velocities=[[Double]](repeating:[],count:6);lost=false }
        previous=values;previousT=t
        if let start=reacquireAt {
            let a=max(0,min(1,(t-start)/0.150)), ease=a*a*(3-2*a)
            for i in 0..<6 { values[i]=reacquireFrom[i]+(values[i]-reacquireFrom[i])*ease }
            if a>=1 { reacquireAt=nil }
        }
        for i in heldChannels where values.indices.contains(i) {values[i]=held[i]}
        held=values
        return (values,dropped,reacquireAt != nil)
    }
}

/// Owner-authorized pose-only diagnostics: no images, audio, file names, or media content.
final class PoseTraceRing {
    static let shared=PoseTraceRing()
    private let lock=NSLock()
    private var rows:[(Double,String)]=[]
    private let traceSession=UUID().uuidString
    private let traceBuild=BuildID.value()
    private var resetSequence=0
    private var lastLiveWrite=0.0
    private let liveQueue=DispatchQueue(label:"gor.pose.live",qos:.utility)
    func append(t:Double,raw:[Double],filtered:[Double],confidence:Double,faceLost:Bool,outlier:Bool,reacquire:Bool,euro:[Double]=[],bands:[Double]=[],pupils:[Double]=[],distanceMode:Int=0,eyeHold:Bool=false,eyeApertures:[Double]=[],frameQuality:[Double]=[],structureReason:Int=0,pairedPupils:[Double]=[],eyeGeometry:[Double]=[],eyeWidths:[Double]=[],faceBox:[Double]=[],landmarkBox:[Double]=[],poseAngles:[Double]=[],framePTS:Double = -1,action:String="sample") {
        lock.lock()
        if action != "sample" {resetSequence += 1}
        let sequence=resetSequence;lock.unlock()
        func finite(_ values:[Double])->[Double] {values.allSatisfy{$0.isFinite} ? values:[]}
        let obj:[String:Any] = ["traceSession":traceSession,"traceBuild":traceBuild,"resetSequence":sequence,"action":action,"pairedPupils":finite(pairedPupils),"eyeGeometry":finite(eyeGeometry),"eyeWidths":finite(eyeWidths),"faceBox":finite(faceBox),"landmarkBox":finite(landmarkBox),"poseAngles":finite(poseAngles),"framePTS":framePTS,"t":t,"raw":raw,"filtered":filtered,"confidence":confidence,
                              "faceLost":faceLost,"outlier":outlier,"reacquire":reacquire,"euro":euro,"bands":bands,"pupils":pupils,"distanceMode":distanceMode,"eyeHold":eyeHold,"eyeApertures":eyeApertures,"frameQuality":frameQuality,"structureReason":structureReason]
        guard let data=try? JSONSerialization.data(withJSONObject:obj,options:.sortedKeys),let row=String(data:data,encoding:.utf8) else { return }
        lock.lock();rows.append((t,row))
        // 5min at <=120fps; also bound memory if a source reports unreasonable timestamps.
        if let cut=rows.firstIndex(where: {$0.0>=t-300}),cut>0 { rows.removeFirst(cut) }
        if rows.count>36000 { rows.removeFirst(rows.count-36000) }
        let live=t-lastLiveWrite>=5;if live {lastLiveWrite=t};lock.unlock()
        if live {writeLive()}
    }
    private func writeLive() {
        lock.lock();let text=rows.map{$0.1}.joined(separator:"\n");lock.unlock()
        guard let dir=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("gor/pose-traces") else{return}
        // Existing pose-only consent, now also carrying numeric pupil geometry192d.
        liveQueue.async {
            do {
                try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let url=dir.appendingPathComponent("current.jsonl")
                try Data((text+"\n").utf8).write(to:url,options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
            } catch { }
        }
    }
    @discardableResult func writeOnQuit() -> URL? {
        lock.lock();let text=rows.map {$0.1}.joined(separator:"\n");lock.unlock()
        guard !text.isEmpty,let dir=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first?.appendingPathComponent("gor/pose-traces") else { return nil }
        do {
            try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let url=dir.appendingPathComponent("pose-\(UUID().uuidString).jsonl")
            guard FileManager.default.createFile(atPath:url.path,contents:Data((text+"\n").utf8),attributes:[.posixPermissions:0o600]) else { return nil }
            return url
        } catch { return nil }
    }
}

// MARK: - LatestPoseSlot
/// At most one pending continuous-control payload. Discrete commands are never coalesced.
final class LatestPoseSlot {
    struct Value { let payload:String;let at:Double;let epoch:UInt64 }
    private let lock=NSLock()
    private var pending:Value?, draining=false, epoch:UInt64=0
    private var closed=false
    private(set) var replaced=0
    /// true means caller must schedule the one drain. Subsequent offers only replace the pending value.
    func offer(_ payload:String,at:Double)->Bool {
        lock.lock();defer{lock.unlock()}
        if closed{return false}
        if pending != nil {replaced+=1}
        pending=Value(payload:payload,at:at,epoch:epoch)
        if draining{return false};draining=true;return true
    }
    func take()->Value? {lock.lock();defer{lock.unlock()};let v=pending;pending=nil;return v}
    func current(_ e:UInt64)->Bool {lock.lock();defer{lock.unlock()};return !closed && e==epoch}
    /// Called after one send. true schedules another drain at the BACK of the shared command queue,
    /// so a flood of camera updates cannot monopolize keyboard/seek/pause commands.
    func finish()->Bool {lock.lock();defer{lock.unlock()};if pending != nil{return true};draining=false;return false}
    func clear() {lock.lock();epoch &+= 1;pending=nil;lock.unlock()}
    func close() {lock.lock();closed=true;epoch &+= 1;pending=nil;lock.unlock()}
}

/// Continuous camera/UI state has one pending main-queue callback, never a FIFO of old frames.
final class LatestMainFrame {
    private let lock=NSLock()
    private var pending:(()->Void)?,scheduled=false
    func submit(_ work:@escaping ()->Void) {
        lock.lock();pending=work
        if scheduled {lock.unlock();return}
        scheduled=true;lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.drain() }
    }
    private func drain() {
        lock.lock();let work=pending;pending=nil;lock.unlock()
        work?()
        lock.lock()
        if pending != nil {lock.unlock();DispatchQueue.main.async { [weak self] in self?.drain() }}
        else {scheduled=false;lock.unlock()}
    }
}

/// A found frame must not erase an unconsumed loss when continuous frames are coalesced.
final class FrameLossLatch {
    private let lock=NSLock()
    private var lost=false
    func mark() {lock.lock();lost=true;lock.unlock()}
    func consume()->Bool {lock.lock();defer{lock.unlock()};let v=lost;lost=false;return v}
}

// MARK: - BlinkControl
/// Index-free PCA eye aperture and the per-session temporal detector.
enum EyeAperture {
    static func ear(_ pts: [(Double,Double)]) -> Double? {
        guard pts.count >= 6 else { return nil }
        let n = Double(pts.count), cx = pts.reduce(0) {$0+$1.0}/n, cy = pts.reduce(0) {$0+$1.1}/n
        var xx=0.0, yy=0.0, xy=0.0
        for (x,y) in pts { let dx=x-cx,dy=y-cy; xx+=dx*dx; yy+=dy*dy; xy+=dx*dy }
        let a = 0.5 * atan2(2*xy,xx-yy), c=cos(a), s=sin(a)
        let along = pts.map { ($0.0-cx)*c+($0.1-cy)*s }
        let across = pts.map { -($0.0-cx)*s+($0.1-cy)*c }
        let w = (along.max() ?? 0)-(along.min() ?? 0)
        guard w > 1e-9 else { return nil }
        return ((across.max() ?? 0)-(across.min() ?? 0))/w
    }
}
struct BlinkControlDetector {
    enum Event: String { case blink, deliberate, doubleBlink }
    private var openL:[Double]=[], openR:[Double]=[]
    private var closedAt:Double?, lastBlink:Double?, lastT:Double?
    private var armedOpenSince:Double?
    mutating func reset() { self = BlinkControlDetector() }
    private func median(_ a:[Double]) -> Double { let s=a.sorted(); return s[s.count/2] }
    mutating func feed(t:Double,left:Double?,right:Double?) -> Event? {
        defer { lastT=t }
        guard let l=left,let r=right,l.isFinite,r.isFinite,l>=0,r>=0 else { closedAt=nil;lastBlink=nil;armedOpenSince=nil;return nil }
        // A missing interval cannot establish a physical closure duration or a double blink.
        if let lastT, t-lastT > 0.1 {closedAt=nil;lastBlink=nil;armedOpenSince=nil}
        if openL.isEmpty { if l>0 && r>0 {openL=[l];openR=[r]};return nil }
        let bl=median(openL), br=median(openR)
        let closed=l<0.45*bl && r<0.45*br
        if l>=0.65*bl && r>=0.65*br {if armedOpenSince==nil{armedOpenSince=t}}
        if closed {
            guard let armedOpenSince,t-armedOpenSince>=0.35 else{return nil}
            if closedAt == nil {closedAt=t};return nil
        }
        if l>=0.65*bl && r>=0.65*br {
            openL.append(l);openR.append(r)
            if openL.count>121 { openL.removeFirst();openR.removeFirst() }
        }
        guard let start=closedAt else { return nil }; closedAt=nil
        let dur=t-start
        if dur>=0.450 { lastBlink=nil;return .deliberate }
        guard dur>=0.060 && dur<=0.400 else { return nil }
        if let prev=lastBlink,t-prev<=0.700 { lastBlink=nil;return .doubleBlink }
        lastBlink=t;return .blink
    }
}

/// Conservative measured-lid visual channel, separate from the double-blink event recognizer.
/// Timing/thresholds are engineering choices, not physiological measurements.
struct IntentionalEyeClosure {
    /// gor.vr.blinkAnalog (default ON). false = the previous binary 0/1 amount, byte-identical behaviour.
    static var analog = true
    private var open:[Double]=[]
    private var smoothed=1.0,candidateAt:Double?,lastT:Double?
    private var closed=false
    private(set) var amount=0.0
    mutating func reset(){self=IntentionalEyeClosure()}
    mutating func feed(t:Double,left:Double?,right:Double?,reliable:Bool)->Double {
        defer{lastT=t}
        guard reliable,let l=left,l.isFinite,l>=0 else {candidateAt=nil;closed=false;amount=0;return 0}
        if open.count<12 {if l>0{open.append(l)};return 0}
        let b=open.sorted()[open.count*3/4],ratio=max(0,min(1,l/max(b,1e-9)))
        smoothed=0.65*ratio+0.35*smoothed
        if ratio>0.85{open.append(l);if open.count>121{open.removeFirst()}}
        if smoothed<0.45 {if candidateAt==nil{candidateAt=t};if t-candidateAt!>=0.060 {closed=true}}
        else if smoothed>0.65 {candidateAt=nil;closed=false}
        // Analog: the lid follows the measured aperture (no 60 ms hold on the VISUAL amount, which the gesture detector keeps).
        amount=Self.analog ? max(0,min(1,(0.85-smoothed)/(0.85-0.35))) : (closed ? 1:0)
        return amount
    }
}

/// Clean bilateral double blink seeks; Control-held single blink toggles playback.
/// The caller selects seek direction from live Cmd. Reliable fresh frames only; no hold/wink action.
struct EyeGestureCommands {
    /// gor.vr.blinkRobust (default ON). false = the previous thresholds and cancel rules, byte-identical behaviour.
    static var robust = true
    static var seriesWindow: Double { robust ? 1.200 : 0.950 }   // end of blink 1 -> end of blink 2
    static var blinkMin: Double { robust ? 0.025 : 0.060 }       // about one 30 fps frame interval, a fast blink is ~1-2 closed frames
    static var blinkMax: Double { robust ? 0.600 : 0.500 }
    static let maxFrameGap = 0.300
    static var closeBelow: Double { robust ? 0.50 : 0.45 }
    static let openAbove = 0.65
    static var openDwell: Double { robust ? 0.030 : 0.060 }      // open time needed before the next closure may start
    static let toleratedMisses = 2                               // robust: isolated unreliable/landmark-less frames hold state
    // 197i cadence layer (gor.vr.blinkCadence, default ON; OFF = byte-identical
    // shipped behaviour). The 196v thermal stride admits the blink pass every
    // 5th frame (~2 Hz at the 10 fps floor); the shipped gates encode a 30 fps
    // sampling assumption, so at 2 Hz the detector reset on every sample and a
    // double blink could NEVER fire (measured 0% at all speeds in
    // tools/head_pose/blink_cadence.py). Each constant below wraps a shipped
    // gate in max(shipped, k * measured sample interval), so 30/10 fps
    // behaviour is unchanged and only the throttled regime adapts.
    static var cadenceAdaptive = true
    static let cadenceGapK = 1.25      // one missing sample never cancels; a true stall still does
    static let cadenceFreshK = 0.75    // the freshest frame at 2 Hz is ~0.5 s old and still current
    static let cadenceEpisodeK = 1.25  // a one-sample closure's observed duration is the interval
    static let cadenceSeriesK = 1.0    // beyond the 10 fps floor cadence the window extends by the extra interval
    static let cadenceSeriesFloor = 0.1
    static let cadenceSoftBelow = 0.80 // weak closure edge: lid falling but above closeBelow
    /// While set, the helper should admit every blink frame (not 1-in-5) so
    /// the episode in progress resolves at full cadence. Read by Sensing
    /// after each feed; sent as the additive "blink-boost" helper command.
    private(set) var blinkBoostUntil: Double? = nil
    enum Command: Equatable {
        case seek(Int), playPause
        var diagnosticFields: String {
            switch self {
            case let .seek(seconds): return "\"seconds\":\(seconds)"
            case .playPause: return "\"action\":\"playPause\""
            }
        }
    }
    private var previousControlHeld = false
    private var baselineL:[Double]=[],baselineR:[Double]=[]
    private var start:Double?,lastT:Double?,openSince:Double?,lastAt:Double?,misses=0
    private var gaps:[Double]=[]
    private var softArmed = true
    mutating func reset(){self=EyeGestureCommands()}
    private mutating func cancel(){start=nil;lastAt=nil;openSince=nil;blinkBoostUntil=nil}
    /// Median of the last 7 usable sample intervals, nil until 3 are measured.
    private var cadence: Double? {
        let usable = gaps.suffix(7)
        guard usable.count >= 3 else { return nil }
        return usable.sorted()[usable.count / 2]
    }
    /// (gapCancel, freshness, blinkMax, seriesWindow) with the cadence layer
    /// applied. Without cadenceAdaptive, or at 30/10 fps, these are exactly
    /// the shipped constants.
    private var limits: (Double, Double, Double, Double) {
        guard Self.cadenceAdaptive, let c = cadence else {
            return (Self.maxFrameGap, Self.maxFrameGap, Self.blinkMax, Self.seriesWindow)
        }
        return (max(Self.maxFrameGap, Self.cadenceGapK * c),
                max(Self.maxFrameGap, Self.cadenceFreshK * c),
                max(Self.blinkMax, Self.cadenceEpisodeK * c),
                Self.seriesWindow + Self.cadenceSeriesK * max(0.0, c - Self.cadenceSeriesFloor))
    }
    private func median(_ v:[Double])->Double {let s=v.sorted();return s[s.count/2]}
    mutating func feed(t:Double,left:Double?,right:Double?,reliable:Bool,frameAge:Double=0)->Int? {
        if case let .seek(seconds)? = feedCommand(t:t,left:left,right:right,reliable:reliable,frameAge:frameAge) { return seconds }
        return nil
    }
    mutating func feedCommand(t:Double,left:Double?,right:Double?,reliable:Bool,frameAge:Double=0,controlHeld:Bool=false)->Command? {
        // A modifier change cannot convert half a gesture or join blink series.
        if controlHeld != previousControlHeld { cancel(); previousControlHeld = controlHeld }
        let (gapLimit, freshLimit, blinkMaxEff, seriesEff) = limits
        let prevT=lastT;lastT=t
        let fresh=frameAge.isFinite && frameAge>=0 && frameAge<=freshLimit
        let usable=reliable && fresh && (left.map{$0.isFinite && $0>=0} ?? false) && (right.map{$0.isFinite && $0>=0} ?? false)
        guard usable,let l=left,let r=right else {
            misses+=1
            // robust: a single dropped landmark frame between two blinks must not erase the series
            if !(Self.robust && fresh && misses<=Self.toleratedMisses) {cancel()}
            return nil
        }
        misses=0
        if let prevT {
            let gap = t - prevT
            // Bootstrap: with fewer than 3 measured intervals there is no
            // cadence estimate, so a slow stream must not cancel yet (the
            // shipped gate cancels every 2 Hz sample and the 12-sample
            // baseline never fills - measured in blink_cadence.py).
            let bootstrapped = !Self.cadenceAdaptive || gaps.count >= 3
            if bootstrapped && (gap > gapLimit || t <= prevT) {cancel();return nil}
            if !bootstrapped && t <= prevT {cancel();return nil}
            if Self.cadenceAdaptive {
                gaps.append(min(gap, 1.0))   // clamp: a stall must not inflate the estimate
                if gaps.count > 21 { gaps.removeFirst() }
            }
        }
        if baselineL.count<12 {
            if l>0,r>0 {baselineL.append(l);baselineR.append(r)}
            return nil
        }
        let lr=l/max(median(baselineL),1e-9),rr=r/max(median(baselineR),1e-9)
        let closed=lr<Self.closeBelow && rr<Self.closeBelow, opened=lr>Self.openAbove && rr>Self.openAbove
        if let lastAt,t-lastAt>seriesEff {self.lastAt=nil;if start==nil {blinkBoostUntil=nil}}
        if opened {
            if openSince==nil {openSince=t}
            if Self.cadenceAdaptive,t-(openSince ?? t)>=Self.openDwell {softArmed=true}
            baselineL.append(l);baselineR.append(r)
            if baselineL.count>121 {baselineL.removeFirst();baselineR.removeFirst()}
            if let start {
                self.start=nil
                guard t-start>=Self.blinkMin,t-start<=blinkMaxEff else {lastAt=nil;return nil}
                if controlHeld { lastAt=nil; blinkBoostUntil=nil; return .playPause }
                if lastAt != nil {lastAt=nil;blinkBoostUntil=nil;return .seek(60)}
                lastAt=t
                // A completed first blink: hold full cadence for the series window.
                if Self.cadenceAdaptive {blinkBoostUntil=t+seriesEff}
            } else if Self.cadenceAdaptive,lastAt==nil {
                blinkBoostUntil=nil   // episode resolved, eyes open
            }
            return nil
        }
        guard closed else {
            // robust: the half-open frames of a reopening lid belong to the same blink (the old code cancelled here,
            // so any blink that reopened over 2+ frames was dropped); only the blinkMax dwell ends it
            if Self.robust,let st=start,t-st<=blinkMaxEff {return nil}
            start=nil
            // Weak edge (197i): lid clearly falling but not yet below
            // closeBelow. At 2 Hz a 0.2 s closure is sampled only ~1/3 of
            // the time (measured), so boost on the falling edge too;
            // re-arms only after a clean open sample, so a held squint
            // boosts once.
            if Self.cadenceAdaptive,softArmed,openSince != nil,min(lr,rr)<Self.cadenceSoftBelow {
                softArmed=false
                blinkBoostUntil=t+max(0.4,2.0*(cadence ?? 0.0))
            }
            return nil
        }
        if start==nil {
            guard let openSince,t-openSince>=Self.openDwell else {return nil}
            start=t;self.openSince=nil
            // Closure edge: hold full cadence until the episode resolves.
            if Self.cadenceAdaptive {blinkBoostUntil=t+blinkMaxEff+2.0*(cadence ?? 0.0)}
        }
        return nil
    }
}

// BEGIN camera-helper IPC (arch-195z Z3, owner-approved; arch-196b C6)
// The camera runs in a child process: the same gor executable with
// --camera-helper (no new SwiftPM target, G5 holds). Parent and helper
// exchange newline-delimited JSON on pipes: commands parent->helper on
// the child's stdin, events helper->parent on its stdout. Camera bytes
// never cross; only the typed readings below do, each carrying the
// consumer generation and ambient window id so a stale helper answer is
// rejected, never applied. Guaranteed camera-off comes from process
// exit releasing the device: on zero consumers the parent asks the
// helper to stop, and a stop not reported within 2 s is followed by
// SIGKILL (CameraHelperClient below, QuitChildKiller pattern). This is
// not proof every OS camera-service/driver hang clears the LED; that
// still needs real-device failure testing.
// Pure Foundation: compiled by the macOS app AND the Linux test driver
// (Tests/Harness/ScreenCamera/helper_link_test.py).
enum CameraHelperIPC {
    /// Bumped when the wire schema changes; a version mismatch refuses
    /// the child rather than decoding against the wrong shape.
    static let protocolVersion = 1

    /// VNDetectFaceRectanglesRequest result, Vision normalized
    /// bottom-left-origin box. yaw/pitch/roll nil when Vision did not
    /// estimate a pose for this face.
    struct FaceRect: Codable, Equatable {
        var box: [Double]            // [minX, minY, width, height]
        var yaw: Double? = nil
        var pitch: Double? = nil
        var roll: Double? = nil
        var confidence: Double
        var faceCount: Int
    }

    /// VNDetectFaceLandmarksRequest result: same identity fields plus
    /// the four landmark point lists the parent's blink/distance/gaze
    /// math consumes. Points are Vision normalized coordinates relative
    /// to `box`, exactly VNFaceLandmarkRegion2D.normalizedPoints.
    struct FaceLandmarks: Codable, Equatable {
        var box: [Double]
        var yaw: Double? = nil
        var pitch: Double? = nil
        var roll: Double? = nil
        var confidence: Double
        var landmarksConfidence: Double
        var faceCount: Int
        var leftEye: [[Double]]? = nil
        var rightEye: [[Double]]? = nil
        var leftPupil: [[Double]]? = nil
        var rightPupil: [[Double]]? = nil
    }

    /// Two-region luma (face box vs everything else), 0...255 encoded
    /// units; mirrors TwoRegionLuma in ScreenCaptureEngine.swift.
    struct Luma2: Codable, Equatable { var face: Double; var room: Double; var combined: Double }

    /// PoseFrameQuality.measure result (bounded face/eye luma samples).
    struct Quality: Codable, Equatable { var mean: Double; var contrast: Double; var clipped: Double }

    /// One camera frame's typed readings. `processed == false` is a
    /// minimal tick: the single Vision slot was busy, so only the
    /// scalar and settle fields are meaningful. Ticks keep the 0.25 s
    /// ambient scalar fallback and the settle gate advancing while a
    /// Vision call is hung; they carry no face data (a stuck request
    /// must never be represented by a cached box).
    struct Frame: Codable, Equatable {
        var generation: UInt64       // consumer lifecycle generation
        var window: UInt64           // ambient settle window id
        var now: Double              // CACurrentMediaTime in the helper (same mach clock base)
        var pts: Double              // frame presentation time in seconds, -1 when unknown
        var age: Double              // host - pts at capture, -1 when unknown
        var pixelWidth: Int
        var pixelHeight: Int
        var ambientOnly: Bool
        var settled: Bool            // this frame's AE/AWB converged
        var consecutiveSettled: Int
        var seenFirstSettled: Bool
        var ambientSettled: Bool     // consecutiveSettled >= required streak
        var processed: Bool          // Vision ran on this frame
        var visionFailed: Bool       // perform() threw
        var visionMS: Double         // perform() wall time, 0 when not run
        /// Bounded-watchdog token (arch-196b C2): the helper's Vision
        /// epoch at admission. A frame whose token the helper later
        /// reports via "vision-cancelled" must be dropped by the
        /// parent, exactly the in-process visionEpochIsCurrent gate.
        var visionToken: UInt64 = 0
        /// Empty = legacy/ambient frame; head = independent rectangles; blink = landmark worker.
        var delivery: String? = nil
        var rect: FaceRect? = nil
        var landmarks: FaceLandmarks? = nil
        var lumaFull: Double? = nil
        var lumaRectFace: Luma2? = nil      // two-region around the rect face box
        var lumaLandmarkFace: Luma2? = nil  // two-region around the landmark face box
        var quality: Quality? = nil
        var exposureChanging: Double // 1/0, -1 when the device is unknown
    }

    /// Parent -> helper. Only cmd is required; the remaining fields are
    /// read for cmd == "configure" and window for "reset-settling".
    struct Command: Codable, Equatable {
        var cmd: String              // configure | reset-settling | stop | shutdown | blink-boost
        var generation: UInt64 = 0
        var window: UInt64 = 0
        var headPose: Bool = false
        var blink: Bool = false
        var ambientOnly: Bool = false
        // 197i: additive and optional (decodeIfPresent), so an old helper
        // ignores the field and a new helper tolerates its absence; the
        // unknown cmd string is a no-op on an old helper (default: break).
        var blinkBoostUntil: Double? = nil
    }

    /// Helper -> parent. Only ev is always meaningful; the rest apply
    /// per kind: hello (version, pid), state (state, generation,
    /// running, reason), log (channel, message), frame (frame),
    /// vision-cancelled (token: the expired watchdog token, C2).
    struct Event: Codable, Equatable {
        var ev: String               // hello | state | frame | log | vision-cancelled
        var version: Int = 0
        var pid: Int32 = 0
        var state: String = ""       // running | stopped | failed
        var generation: UInt64 = 0
        var running: Bool = false    // for stopped: hardware still running (stop failed)
        var reason: String = ""
        var channel: String = ""     // media -> Diag.mediaRecord, diag -> Diag.log
        var message: String = ""
        var frame: Frame? = nil
        var token: UInt64 = 0        // for vision-cancelled
    }

    static func encode<T: Encodable>(_ value: T) -> Data {
        var data = (try? JSONEncoder().encode(value)) ?? Data()
        data.append(0x0A)
        return data
    }
    static func decodeCommand(_ line: Data) -> Command? {
        guard !line.isEmpty, line.count <= maxLineBytes else { return nil }
        return try? JSONDecoder().decode(Command.self, from: line)
    }
    static func decodeEvent(_ line: Data) -> Event? {
        guard !line.isEmpty, line.count <= maxLineBytes else { return nil }
        return try? JSONDecoder().decode(Event.self, from: line)
    }

    /// A single frame line is a few KB; 1 MB rejects garbage without
    /// bounding a legitimate reading.
    static let maxLineBytes = 1_000_000

    /// Incremental NDJSON splitter for pipe reads: partial lines wait
    /// for their newline; an over-long line without a newline is
    /// dropped rather than accumulated without bound.
    struct LineSplitter {
        private var buffer = Data()
        mutating func push(_ chunk: Data) -> [Data] {
            buffer.append(chunk)
            var lines: [Data] = []
            while let nl = buffer.firstIndex(of: 0x0A) {
                lines.append(Data(buffer[buffer.startIndex..<nl]))
                buffer.removeSubrange(buffer.startIndex...nl)
            }
            if buffer.count > CameraHelperIPC.maxLineBytes { buffer.removeAll(keepingCapacity: false) }
            return lines
        }
    }
}
// END camera-helper IPC

// 197i: output-side hold lock (gimbal), the final stage of the pose output
// chain. Python reference and measurement harness: tools/head_pose/pose_filter.py
// (HoldLock) + tools/head_pose/synth_tilt_hold_clip.py, rerun by
// Tests/HeadPose/test_hold_lock.py (24 measured configs + mutants; constants
// below pinned by text). gor.vr.poseHoldLock (default ON) removes the stage
// from the chain when OFF, byte-identical output. Pure Foundation: compiled
// by the macOS app and the Linux blink/camera test drivers.
//
// Two-state Schmitt, the house pattern of the proven 191a Z hysteresis:
// LOCKED holds the committed value (zero output jitter); TRACKING passes the
// chain output through untouched (zero added lag, zero steady-state offset).
// Release on the FIRST sample at least `band` from the committed value, so a
// real movement pays no latency; the cost is the sub-band displacement eaten
// at movement start (measured <= band, capped at 0.05 rad ~ 2.9 deg). The band
// is adaptive: max(floor, holdEnterK * EMA|per-sample delta| * sqrt(settle/dt)),
// capped - the sqrt term is the measured AR cadence factor (0.5 s wander is
// 2.6-2.8x mean|delta| * sqrt(0.5/dt) across 30/10 fps and sigma .01/.02/.05),
// so 3x wander holds at any cadence with one K. The EMA accepts only deltas
// below holdMadGate x the estimate, so a slow pan (a deliberate movement)
// cannot inflate the band (measured mutant: ungated EMA eats ~cap on a
// low-noise pan). Re-lock on displacement stability: output within half the
// band of a window anchor for holdSettleSeconds (a per-sample speed test
// cannot separate high noise from a slow pan: measured 30 fps noise speed
// ~0.4 rad/s > 0.1 rad/s pan).
struct PoseHoldLock {
    static let holdEnterK = 8.1
    static let holdEnterFloorRad = 0.010
    static let holdEnterFloorBox = 0.005
    static let holdSettleSeconds = 0.50
    static let holdNoiseTauSeconds = 0.6
    static let holdBandCapRad = 0.05
    static let holdBandCapBox = 0.025
    static let holdMadGate = 3.0

    private let floor: Double
    private let cap: Double
    private var committed: Double? = nil
    private var tracking = true
    private var mad: Double? = nil
    private var prev: Double? = nil
    private var tPrev: Double? = nil
    private var winVal: Double? = nil
    private var winT: Double? = nil
    private(set) var band: Double

    init(box: Bool) {
        floor = box ? Self.holdEnterFloorBox : Self.holdEnterFloorRad
        cap = box ? Self.holdBandCapBox : Self.holdBandCapRad
        band = floor
    }

    mutating func reset() { self = PoseHoldLock(box: cap == Self.holdBandCapBox) }

    mutating func filter(_ x: Double, t: Double) -> Double {
        guard let c0 = committed else {
            committed = x; prev = x; tPrev = t; winVal = x; winT = t
            return x
        }
        let dt = min(max(t - (tPrev ?? t), 1.0 / 240.0), 0.5)
        tPrev = t
        let d = abs(x - (prev ?? x))
        prev = x
        if mad == nil || d < Self.holdMadGate * (mad ?? 0) {
            let alpha = 1.0 - exp(-dt / Self.holdNoiseTauSeconds)
            mad = mad.map { $0 + alpha * (d - $0) } ?? d
        }
        if let mad {
            band = min(cap, max(floor, Self.holdEnterK * mad * sqrt(Self.holdSettleSeconds / dt)))
        }
        if tracking {
            committed = x
            if let wv = winVal, let wt = winT, abs(x - wv) < 0.5 * band {
                if t - wt >= Self.holdSettleSeconds {
                    tracking = false
                    committed = x
                }
            } else {
                winVal = x; winT = t
            }
        } else if abs(x - c0) >= band {
            tracking = true
            winVal = x; winT = t
            committed = x
        }
        return committed ?? x
    }
}
