// ThreeD/Prepare.swift - 3D station "Prepare": prepare orchestration: runner, support, launcher, spawn, assembly, telemetry and cache memo.
// Move-only split of the former ThreeD.swift (arch-199s). The sections below are byte-identical to their former BEGIN/END spans,
// in their original relative order. The import list is the union of the former file (a deliberate superset; narrow it only with a Darwin compile).
#if canImport(AVFoundation)
import AVFoundation
#endif
#if canImport(Accelerate)
import Accelerate
#endif
import AppKit
#if canImport(Compression)
import Compression
#endif
import CoreGraphics
#if canImport(CoreML)
import CoreML
#endif
#if canImport(CoreMedia)
import CoreMedia
#endif
#if canImport(CoreVideo)
import CoreVideo
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif
import Darwin
import Foundation
#if canImport(Glibc)
import Glibc
#endif
#if canImport(ImageIO)
import ImageIO
#endif
#if canImport(Metal)
import Metal
#endif
import QuartzCore
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(VideoToolbox)
import VideoToolbox
#endif
#if canImport(Vision)
import Vision
#endif

// BEGIN relocated ThreeDThermalGate.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190v s19: thermal duty cycle for the prepare path. Pure state machine (`ThermalDutyPolicy`, injected clock) plus a blocking gate the runner calls at
/// every frame boundary. thermalState >= .serious (rank 2), per owner192c: the caller checkpoints once (WindowState + the s16 resume prefix, owned by the runner), then
/// the gate holds for at least 60 s and releases only after the state has stayed below .fair for a 30 s dwell. Resume is exact (no recompute).
/// Not compiled or run on a Mac; the real thermalState behaviour is unmeasured.
struct ThermalDutyPolicy {
    enum Action: Equatable { case run, suspend, hold, resume }
    static let suspendRank = 2, resumeRank = 1, minSuspend = 60.0, dwell = 30.0
    private(set) var suspendedAt: Double?, clearSince: Double?
    var isSuspended: Bool { suspendedAt != nil }

    /// `rank`: ProcessInfo.ThermalState raw value (0 nominal, 1 fair, 2 serious, 3 critical). `now`: monotonic seconds.
    mutating func step(rank: Int, now: Double) -> Action {
        guard let s = suspendedAt else {
            if rank >= Self.suspendRank { suspendedAt = now; clearSince = nil; return .suspend }
            return .run
        }
        if rank >= Self.resumeRank { clearSince = nil; return .hold }
        if clearSince == nil { clearSince = now }
        if now - s >= Self.minSuspend, now - (clearSince ?? now) >= Self.dwell { suspendedAt = nil; clearSince = nil; return .resume }
        return .hold
    }
}

final class ThreeDThermalGate {
    private var policy = ThermalDutyPolicy()
    private let rank: () -> Int, now: () -> Double, wait: (Double) -> Void
    private let wake = DispatchSemaphore(value: 0)
    private var observer: NSObjectProtocol?
    private(set) var suspends = 0, resumes = 0     // for the Mac verification log

    init(rank: @escaping () -> Int = { ProcessInfo.processInfo.thermalState.rawValue }, now: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         wait: ((Double) -> Void)? = nil) {
        self.rank = rank; self.now = now
        self.wait = wait ?? { [wake] s in _ = wake.wait(timeout: .now() + s) }
        if wait == nil { observer = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [wake] _ in wake.signal() } }
    }
    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) } }

    /// Call at a frame or shot boundary, after the current frame is finished. Returns immediately while cool; on the first hot reading it runs `checkpoint`
    /// once, reports `paused(true)` and blocks (polling every second, or on thermalStateDidChange) until the policy resumes. false only when `cancelled()`.
    func boundary(checkpoint: () -> Void, paused: (Bool) -> Void, cancelled: () -> Bool) -> Bool {
        while true {
            if cancelled() { return false }
            switch policy.step(rank: rank(), now: now()) {
            case .run: return true
            case .suspend: suspends += 1; checkpoint(); paused(true)
            case .hold: break
            case .resume: resumes += 1; paused(false); return true
            }
            wait(1)
        }
    }
}
// END relocated ThreeDThermalGate.swift
// BEGIN relocated NativePrepareRunner.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate)
import AVFoundation
import CoreML
import CoreVideo
import Accelerate

/// 190t/190v native prepare runner: the ShotPrepareRunner the delivery lane's ThreeDRunnerRegistry takes. Composition only; every piece it uses is tested elsewhere
/// (cache_key, cuts and fov_track files in PrepareSupport; ShotCuts; ShotPrepare/ShotCheckpoint; DZC writer). UNCOMPILED AND UNRUN (no Mac): AVAssetReader, vImage, CoreML and
/// VideoToolbox calls here are parse-only. Differences from the Python path, all on purpose and recorded in the commit note:
///  - frames reach VDA (154x266) and MoGe (518x294 / 518x518) through vImage high-quality resampling, not cv2 bicubic (small numeric difference, same geometry);
///  - the source proxy is encoded in a second decode pass after the depth container is complete (the VT encoder cannot resume mid-file), 8-bit video range widened
///    to 10-bit MSB-aligned (v8 << 8), no tone or range change;
///  - no per-film numbers: MoGe shape is picked from the source aspect (MoGeInput.pick), quality-first, fp32 fallback inside MoGeKeyframeRunner.
final class NativePrepareRunner: ShotPrepareRunner {
    struct Failure: Error { let reason: String }
    /// `kitDir` = the directory holding the A-D kit packages named in kit_manifest.json (encoder_fp16, bootstrap_fp16, stream_fp16, moge2_vits_WxH_{fp16,fp32}.mlpackage).
    let kitDir: URL, cacheRoot: URL
    private(set) var vda: VDAStreamRunner?, moge: MoGeKeyframeRunner?
    private var windowed: VDAWindowRunner?                  // 190w W4: nil = streaming prepare (kit lacks the windowed packages, or they failed to load)
    private let reuseContext:ShotPrepareReuseContext
    init(kitDir: URL, cacheRoot: URL = DepthCachePaths.root, reuseContext:ShotPrepareReuseContext = .deliveredLegacy) {
        self.kitDir = kitDir; self.cacheRoot = cacheRoot;self.reuseContext=reuseContext
    }

    /// Compiled-model cache under `modelsDir/kit-compiled/<manifest sha>` (pruned of older kit versions); `modelsDir` = ThreeDModels.modelsDir.
    var modelsDir: URL?
    /// Self-test only: stage timings, depth stats and verbatim shot errors (nil = no cost beyond a nil check).
    var telemetry: PrepareTelemetry?
    var externallyHeldModelLane = false // headless self-test holds through realtime/render probes
    /// arch-196b C3: the cooperative-pause flag, set by the prepare-worker CLI. Checked at every ShotSink frame boundary
    /// (the worker parks there with no in-flight model call); default = never paused.
    var pauseRequested: () -> Bool = { false }
    private func loadModels() throws {
        if let m = modelsDir, let sha = KitCompiledCache.manifestSha(kitDir: kitDir) { KitCompiledCache.dir = KitCompiledCache.cacheDir(modelsDir: m, sha: sha); KitCompiledCache.prune(modelsDir: m, keep: sha) }
        if vda == nil {
            let k = VDAStreamRunner.Kit(encoder: kitDir.appendingPathComponent("encoder_fp16.mlpackage"), bootstrap: kitDir.appendingPathComponent("bootstrap_fp16.mlpackage"),
                                        stream: kitDir.appendingPathComponent("stream_fp16.mlpackage"))
            guard let r = VDAStreamRunner(kit: k) else { throw Failure(reason: "VDA CoreML kit did not load") }
            vda = r
        }
        if moge == nil {
            let names = ((try? FileManager.default.contentsOfDirectory(atPath: kitDir.path)) ?? []).filter { $0.hasPrefix("moge2_vits_") && $0.hasSuffix(".mlpackage") }
            var by: [String: (fp16: URL?, fp32: URL?)] = [:]
            for n in names {
                let parts = n.replacingOccurrences(of: ".mlpackage", with: "").split(separator: "_")          // moge2 vits 518x294 fp16
                guard parts.count == 4, parts[2].contains("x") else { continue }
                let key = String(parts[2]), u = kitDir.appendingPathComponent(n); var e = by[key] ?? (nil, nil)
                if parts[3] == "fp16" { e.fp16 = u } else if parts[3] == "fp32" { e.fp32 = u }
                by[key] = e
            }
            let pk: [MoGeKeyframeRunner.Package] = by.compactMap { k, v in
                let wh = k.split(separator: "x").compactMap { Int($0) }; guard wh.count == 2 else { return nil }
                return MoGeKeyframeRunner.Package(shape: MoGeInput.Shape(w: wh[0], h: wh[1]), fp16: v.fp16, fp32: v.fp32)
            }
            guard let r = MoGeKeyframeRunner(packages: pk) else { throw Failure(reason: "MoGe CoreML kit did not load") }
            moge = r
        }
    }

    final class LumaBox { var v: [Float]? }

    // MARK: frames

    /// Sequential decode of frames [first, first + count) of the film. Reopens when asked for a frame out of order (resume from a checkpoint).
    final class FrameReader {
        let fps:Double,format:OSType,facts:SourceFacts?,fallbackFormat:OSType?
        private let url:URL,source:SourceFacts,cancelled:()->Bool
        private var pipe:PrepareRawPipe?
        private var needsFirstFrame=true
        private(set) var nextFrame=0,last=0
        init?(url:URL,fps:Double,format:OSType,facts:SourceFacts?=nil,fallbackFormat:OSType?=nil,decodeFacts:SourceFacts?=nil,cancelled:@escaping ()->Bool={false}) {
            guard let source=decodeFacts ?? facts ?? SourceFormatProbe.pipeFacts(url:url,cancelled:cancelled),fps.isFinite,fps>0,
                  abs(source.avgFps-fps)/fps<0.002 else {return nil}
            self.url=url;self.fps=fps;self.format=format;self.facts=facts;self.fallbackFormat=fallbackFormat;self.source=source;self.cancelled=cancelled
        }
        var size:(w:Int,h:Int) {if let f=facts {let n=SourceFormat.normalizedSize(f);return(n.w,n.h)};return(source.width,source.height)}
        func open(first:Int,last:Int)->Bool {
            close()
            let deep=format==kCVPixelFormatType_420YpCbCr10BiPlanarFullRange || format==kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            let full=format==kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format==kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
            let bgra=format==kCVPixelFormatType_32BGRA
            guard bgra || [kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange].contains(format),
                  size.w>0,size.h>0 else {return false}
            var filters:[String]=[]
            let matrix=SourceFormat.matrixKey(source)
            let inputRange=source.fullRange.map {$0 ? "full":"limited"} ?? "auto"
            if let f=facts {
                let width=Int((Double(f.width)*f.sar).rounded(.toNearestOrEven))
                guard width>0,width<=16384 else {return false}
                filters.append("scale=\(width):\(f.height):in_range=\(inputRange):out_range=\(bgra || full ? "full":"limited"):in_color_matrix=\(matrix):out_color_matrix=\(matrix)")
                if f.rotation==90 {filters.append("transpose=clock")}
                else if f.rotation==180 {filters += ["hflip","vflip"]}
                else if f.rotation==270 {filters.append("transpose=cclock")}
                filters.append("setsar=1")
            } else {
                filters.append("scale=iw:ih:in_range=\(inputRange):out_range=\(full ? "full":"limited"):in_color_matrix=\(matrix):out_color_matrix=\(matrix)")
            }
            let pixel=bgra ? "bgra":deep ? "p010le":"nv12"
            let filterNames=filters.map {String($0.split(separator:"=")[0])}
            guard PrepareDecodeDiagnostics.capability(codec:source.codec,pixel:pixel,filters:filterNames,cancelled:cancelled) else {
                PrepareDecodeDiagnostics.firstFrame(container:url.pathExtension,okay:false,reason:"required decoder, pixel format or filter unavailable");return false
            }
            guard let args=PrepareDecodeContract.arguments(source:url.path,first:first,last:last,fps:fps,startPTS:source.firstPTS,pixel:pixel,filters:filters),
                  let p=PrepareRawPipe(binary:GORResources.vendorPath("ffmpeg/bin/ffmpeg"),arguments:args,cancelled:cancelled) else {return false}
            pipe=p;nextFrame=first;self.last=last;return true
        }
        func frame(_ k:Int,last:Int)->CVPixelBuffer? {
            if pipe==nil || k != nextFrame {guard open(first:k,last:last) else {return nil}}
            guard k<=self.last else {return nil}
            let w=size.w,h=size.h,bgra=format==kCVPixelFormatType_32BGRA
            let deep=format==kCVPixelFormatType_420YpCbCr10BiPlanarFullRange || format==kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            let word=deep ? 2:1,row=w*(bgra ? 4:word),chromaRow=((w+1)/2)*2*word
            let chromaHeight=(h+1)/2,bytes=bgra ? row*h:row*h+chromaRow*chromaHeight
            guard let raw=pipe?.frame(bytes:bytes,expectedPTS:source.firstPTS+Double(k)/fps,tolerance:max(source.ptsTickMs/1000,0.001)+0.0000001) else {
                if needsFirstFrame {PrepareDecodeDiagnostics.firstFrame(container:url.pathExtension,okay:false,reason:"decode failed, cancelled or source PTS mismatch")};return nil
            }
            var pb:CVPixelBuffer?
            guard CVPixelBufferCreate(nil,w,h,format,nil,&pb)==kCVReturnSuccess,let pb else {return nil}
            CVPixelBufferLockBaseAddress(pb,[]);defer {CVPixelBufferUnlockBaseAddress(pb,[])}
            var copied=true
            raw.withUnsafeBytes {src in
                guard let base=src.baseAddress else {copied=false;return}
                if bgra {
                    guard let dst=CVPixelBufferGetBaseAddress(pb) else {copied=false;return}
                    let stride=CVPixelBufferGetBytesPerRow(pb)
                    guard stride>=row else {copied=false;return}
                    for y in 0..<h {memcpy(dst.advanced(by:y*stride),base.advanced(by:y*row),row)}
                } else {
                    guard CVPixelBufferGetPlaneCount(pb)==2 else {copied=false;return}
                    for plane in 0..<2 {
                        guard let dst=CVPixelBufferGetBaseAddressOfPlane(pb,plane) else {copied=false;return}
                        let stride=CVPixelBufferGetBytesPerRowOfPlane(pb,plane),height=plane==0 ? h:chromaHeight,offset=plane==0 ? 0:row*h,planeRow=plane==0 ? row:chromaRow
                        guard stride>=planeRow,CVPixelBufferGetHeightOfPlane(pb,plane)==height else {copied=false;return}
                        for y in 0..<height {memcpy(dst.advanced(by:y*stride),base.advanced(by:offset+y*planeRow),planeRow)}
                    }
                }
            }
            guard copied else {return nil}
            if let color=SourceFormatProbe.pipeColorProperties(source) {
                let pairs=[(AVVideoColorPrimariesKey,kCVImageBufferColorPrimariesKey),(AVVideoTransferFunctionKey,kCVImageBufferTransferFunctionKey),(AVVideoYCbCrMatrixKey,kCVImageBufferYCbCrMatrixKey)]
                for (key,attachment) in pairs {if let value=color[key] {CVBufferSetAttachment(pb,attachment,value as CFString,.shouldPropagate)}}
            }
            if needsFirstFrame {PrepareDecodeDiagnostics.firstFrame(container:url.pathExtension,okay:true,reason:"actual pixel buffer and source PTS verified");needsFirstFrame=false}
            nextFrame+=1;return pb
        }
        func close() {pipe?.close();pipe=nil}
        deinit {close()}
    }

    /// BGRA pixel buffer -> RGBA8 [w * h * 4] at (w, h), vImage high-quality resampling.
    static func resizeRGBA(_ pb: CVPixelBuffer, w: Int, h: Int) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        var src = vImage_Buffer(data: base, height: vImagePixelCount(CVPixelBufferGetHeight(pb)), width: vImagePixelCount(CVPixelBufferGetWidth(pb)), rowBytes: CVPixelBufferGetBytesPerRow(pb))
        var scaled = [UInt8](repeating: 0, count: w * h * 4), rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = scaled.withUnsafeMutableBytes { (sp: UnsafeMutableRawBufferPointer) -> Bool in rgba.withUnsafeMutableBytes { (rp: UnsafeMutableRawBufferPointer) -> Bool in
            var d = vImage_Buffer(data: sp.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
            guard vImageScale_ARGB8888(&src, &d, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else { return false }
            var o = vImage_Buffer(data: rp.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
            let map: [UInt8] = [2, 1, 0, 3]                      // BGRA -> RGBA
            return vImagePermuteChannels_ARGB8888(&d, &o, map, vImage_Flags(kvImageNoFlags)) == kvImageNoError
        } }
        return ok ? rgba : nil
    }

    /// 8-bit 4:2:0 biplanar -> 10-bit biplanar of the SAME range (SourceFormat.widen8To10: video range v8 << 8, full range scaled to 1023), same size. A buffer that is already 10-bit passes through.
    static func widen10(_ src: CVPixelBuffer) -> CVPixelBuffer? {
        let pf = CVPixelBufferGetPixelFormatType(src)
        if pf == kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange || pf == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange { return src }
        let full = pf == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let w = CVPixelBufferGetWidth(src), h = CVPixelBufferGetHeight(src); var dst: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, w, h, full ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange : kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, nil, &dst) == kCVReturnSuccess, let d = dst else { return nil }
        CVPixelBufferLockBaseAddress(src, .readOnly); CVPixelBufferLockBaseAddress(d, []); defer { CVPixelBufferUnlockBaseAddress(d, []); CVPixelBufferUnlockBaseAddress(src, .readOnly) }
        for plane in 0..<2 {
            guard let sb = CVPixelBufferGetBaseAddressOfPlane(src, plane), let db = CVPixelBufferGetBaseAddressOfPlane(d, plane) else { return nil }
            let rows = CVPixelBufferGetHeightOfPlane(src, plane), cols = CVPixelBufferGetWidthOfPlane(src, plane) * (plane == 0 ? 1 : 2)
            let ss = CVPixelBufferGetBytesPerRowOfPlane(src, plane), ds = CVPixelBufferGetBytesPerRowOfPlane(d, plane)
            for j in 0..<rows {
                let sr = sb.advanced(by: j * ss).assumingMemoryBound(to: UInt8.self), dr = db.advanced(by: j * ds).assumingMemoryBound(to: UInt16.self)
                for i in 0..<cols { dr[i] = SourceFormat.widen8To10(sr[i], fullRange: full) }
            }
        }
        return d
    }

    /// Luma plane of an 8-bit biplanar buffer as a dense [w * h] array (the scdet input).
    static func luma(_ pb: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0), s = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        guard let b = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return [] }
        var out = [UInt8](repeating: 0, count: w * h)
        for j in 0..<h { out.withUnsafeMutableBufferPointer { p in memcpy(p.baseAddress! + j * w, b.advanced(by: j * s), w) } }
        return out
    }

    // MARK: prepare

    func prepare(_ request: ThreeDPrepareLauncher.Request, cancelled: @escaping () -> Bool) throws {
        guard let key = PrepareSupport.cacheKey(path: request.film.path) else { throw Failure(reason: "cannot read the film for its cache key") }
        let entry = cacheRoot.appendingPathComponent(key, isDirectory: true), fps = request.fps, n = request.nFrames
        let cachePin = try DepthCacheBudget.pin(root: cacheRoot, key: key, create: true)
        defer { withExtendedLifetime(cachePin) {} }
        try? FileManager.default.removeItem(at:cacheRoot.appendingPathComponent(".budget-failure"))
        let diskWatch = DepthCacheBudget.Watch(root: cacheRoot)
        defer {if let failure=diskWatch.failure {DepthCacheBudget.recordFailure(failure,root:cacheRoot)}}
        guard diskWatch.allowed(force: true) else { throw diskWatch.failure! }
        // The same cancellation callback is observed by depth, proxy and cuts.
        let callerCancelled = cancelled
        let cancelled: () -> Bool = { callerCancelled() || !diskWatch.allowed() }
        let lane = externallyHeldModelLane ? nil : PrepareProcessLifetime.acquireLane(root: cacheRoot, cancelled: cancelled)
        if !externallyHeldModelLane && lane == nil { return }
        defer { if let lane { PrepareProcessLifetime.releaseLane(lane) } }
        // All three readers decode the original source. Metadata failure is a
        // refusal, never an HDR/Dolby Vision/VFR guard bypass.
        guard let facts = SourceFormatProbe.pipeFacts(url:request.film,cancelled:cancelled) else {
            throw Failure(reason:"source metadata or presentation grid could not be verified; staying 2D")
        }
        let why=SourceFormat.refuseReasons(facts)
        guard why.isEmpty else {throw Failure(reason:why.joined(separator:"; "))}
        let readableFilm=request.film
        // 195h r3 + Delivery 5 + A-1: the frozen prepare identity of the REQUEST is parsed FIRST - the DAV2 path never touches the VDA/MoGe kit.
        let expOptions = ThreeDExperimentOptions(experiments: request.experiments)
        // 195h A (Delivery A-5/A-1): the DAV2 producer is independent - a DAV2-only install (no VDA/MoGe kit) runs it. A requested DAV2 job with a
        // missing package FAILS LOUDLY instead of silently preparing default-mode depth under an experimental request (honesty rule).
        var dav2Runner: CoreMLDepthRunner? = nil
        if expOptions.dav2Depth {
            guard let r = CoreMLDepthRunner(modelsDir: ThreeDModels.modelsDir) else { throw Failure(reason: "dav2-small-coreml package missing; run tools/gor-fetch-models.sh or turn off the DAV2 experiment") }
            dav2Runner = r
        }
        if expOptions.requiresVDAMoGeKit {
            try ThreeDStageLog.time("load models (all kit packages)") { try loadModels() }
            if windowed == nil, VDAWindowRunner.available(kitDir: kitDir) { windowed = VDAWindowRunner(kitDir: kitDir); if windowed == nil { telemetry?.note("vda_mode", "windowed kit present but did not load; streaming") } }
            telemetry?.note("vda_mode", windowed != nil ? "windowed (32/10 overlap)" : "streaming")
        }
        guard expOptions.dav2Depth || (vda != nil && moge != nil) else { throw Failure(reason: "models") }

        // 1. cuts (cached in the entry, like prepare_film._cuts_for)
        var shots = PrepareSupport.readCuts(entry: entry) ?? []
        if shots.isEmpty {
            guard let lr = FrameReader(url: readableFilm, fps: fps, format: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, decodeFacts:facts, cancelled:cancelled) else { throw Failure(reason: "no video track") }
            var k = 0, stopped = false
            let tCuts = DispatchTime.now()
            let r = ShotCuts.detect(next: {
                if cancelled() { stopped = true; return nil }
                guard k < n, let pb = lr.frame(k, last: n - 1) else { return nil }
                k += 1; ThreeDStageLog.progress("cuts-frames", done: k, total: n); return NativePrepareRunner.luma(pb)
            })
            ThreeDStageLog.progress("cuts-reader-close", done: 0, total: 1)
            lr.close(); ThreeDStageLog.progress("cuts-reader-close", done: 1, total: 1); telemetry?.add("cuts_detect", ms: Double(DispatchTime.now().uptimeNanoseconds - tCuts.uptimeNanoseconds) / 1e6)
            if stopped { return }
            guard k==n else {throw Failure(reason:"source decode ended before the requested frame count; staying 2D")}
            ThreeDStageLog.progress("cuts-persist", done: 0, total: 1)
            shots = ShotCuts.shots(nFrames: n, cuts: r.cuts)
            guard !shots.isEmpty, PrepareSupport.writeCuts(entry: entry, cuts: r.cuts, shots: shots) else { throw Failure(reason: "cut detection produced no shots") }
            ThreeDStageLog.progress("cuts-persist", done: 1, total: 1)
        }
        ThreeDStageLog.progress("depth-setup", done: 0, total: 1)
        guard let sink = ShotSink(entry: entry, shots: shots, fps: fps) else { throw Failure(reason: "cannot open the cache entry") }
        sink.pauseRequested = pauseRequested
        sink.writeCurrentFilm(root: cacheRoot, key: key, nFrames: n)
        var hooks = ShotPrepareHooks.sink(sink, cancelled: cancelled)
        hooks.progress = { ThreeDStageLog.progress($0, done: $1, total: $2) }
        if let t = telemetry { hooks.stage = { t.add($0, ms: $1); ThreeDStageLog.done("prepare " + $0, ms: $1) }; hooks.depthMetres = { t.depthFrame($0) } }

        // 2. shots, nearest the playhead first
        let fm = FileManager.default
        func ready(_ i: Int) -> Bool { reuseContext.mayReuseExisting(DZCFile.isComplete(ShotSink.depthURL(entry, i)) && PrepareSupport.optionsMatch(dzc: ShotSink.depthURL(entry, i), options: expOptions) && fm.fileExists(atPath: ShotSink.sidecarURL(entry, i).path)) }   // 199h D2: depth+sidecar readiness (no proxy); 195h: a container prepared in another experiment mode is NOT ready
        let done = Set(shots.indices.filter(ready))
        let order = PrepareSupport.pendingOrder(shots: shots, done: done, playheadFrame: Int((request.startPTS * fps).rounded()))
        guard let bgra = FrameReader(url: readableFilm, fps: fps, format: kCVPixelFormatType_32BGRA, facts: facts, cancelled:cancelled) else { throw Failure(reason: "no video track") }
        let src = bgra.size
        let mogeShape: MoGeInput.Shape? = expOptions.dav2Depth ? nil : moge!.shape(srcW: src.w, srcH: src.h)   // 195h A: DAV2 needs no MoGe shape
        if !expOptions.dav2Depth, mogeShape == nil { throw Failure(reason: "no MoGe shape for \(src.w)x\(src.h)") }
        let box = VDAStream.letterbox(srcW: src.w, srcH: src.h)           // s22: letterbox into 266x154, depth cropped back to box.nw x box.nh (DAV2 output is resized onto the same grid, so sidecar/render geometry is uniform)
        ThreeDStageLog.progress("depth-setup", done: 1, total: 1)
        for i in order {
            if cancelled() { return }
            let s = shots[i][0], e = shots[i][1], count = e - s + 1
            let alignURL = entry.appendingPathComponent(String(format: "shot_%05d.align.json", i))
            // 2a. depth (VDA stream + MoGe keyframes -> .dzc), resumable; skipped when the container is already complete
            if !DZCFile.isComplete(ShotSink.depthURL(entry, i)) || !PrepareSupport.optionsMatch(dzc: ShotSink.depthURL(entry, i), options: expOptions) {   // 195h r3-2: a mismatched container is re-prepared (rebuilt inside ShotPrepare.run, never resumed)
                if PrepareSupport.containerAction(dzc: ShotSink.depthURL(entry, i), options: expOptions) == .rebuild { try? fm.removeItem(at: alignURL) }   // 195h A (Delivery A-3): the other mode's align track never survives a rebuild
                var cache: (k: Int, pb: CVPixelBuffer)? = nil
                func pixels(_ k: Int) -> CVPixelBuffer? {
                    if let c = cache, c.k == k { return c.pb }
                    guard let pb = (self.telemetry?.time("decode") { bgra.frame(s + k, last: e) } ?? bgra.frame(s + k, last: e)) else { return nil }
                    cache = (k, pb); return pb
                }
                // frame k is read for the VDA step; the MoGe keyframe of the same k reuses the cached buffer (frames are requested strictly in order)
                let lumaBox = LumaBox()          // s35: the depth-resolution luma of the frame the VDA step just consumed (guards: texture weights, sky, overlay)
                let mogeIn: (Int) -> (rgba: [UInt8], shape: MoGeInput.Shape)? = { k in mogeShape.flatMap { ms in pixels(k).flatMap { NativePrepareRunner.resizeRGBA($0, w: ms.w, h: ms.h) }.map { (rgba: $0, shape: ms) } } }
                let backend: ShotPrepareBackend
                if let dav2 = dav2Runner {
                    // 195h A: DAV2-Small CoreML producer. One fresh backend per shot = the item-3 EMA's shot-boundary reset; its accumulator
                    // resumes EXACTLY through the checkpointed window. mogeKeyframe is nil by design (monocular model).
                    backend = DAV2Backend(runner: dav2, pixels: pixels, outW: box.nw, outH: box.nh, ema: expOptions.dav2TemporalEMA ? ModelDepthEMA() : nil)
                } else if let wr = windowed {
                    // the window source reads ahead: luma + MoGe input are captured per frame at read time (see VDAWindowedBackend)
                    let cur = LumaBox()
                    let wb = VDAWindowedBackend(runner: wr, moge: moge!, frameCount: count, crop: box,
                        vdaInput: { k in pixels(k).flatMap { NativePrepareRunner.resizeRGBA($0, w: box.nw, h: box.nh) }.map { cur.v = DepthGuards.meanLuma(rgba: $0); return VDAStream.chwLetterboxed(rgba: $0, box: box) } },
                        lumaNow: { cur.v }, mogeInput: mogeIn)
                    wb.progress = { ThreeDStageLog.progress("depth-windows", done: $0, total: $1) }
                    wb.stage = { [weak self] n, v in self?.telemetry?.add(n, ms: v) }
                    backend = wb
                } else {
                    let lumaBox = LumaBox()          // s35: the depth-resolution luma of the frame the VDA step just consumed (guards: texture weights, sky, overlay)
                    let nb = NativeShotBackend(vda: vda!, moge: moge!,
                        vdaInput: { k in pixels(k).flatMap { NativePrepareRunner.resizeRGBA($0, w: box.nw, h: box.nh) }.map { lumaBox.v = DepthGuards.meanLuma(rgba: $0); return VDAStream.chwLetterboxed(rgba: $0, box: box) } },
                        mogeInput: mogeIn)
                    nb.crop = box; nb.lumaSource = { lumaBox.v }
                    nb.stage = { [weak self] n, v in self?.telemetry?.add(n, ms: v) }
                    backend = nb
                }
                var job = ShotPrepareJob(shot: i, startFrame: s, frames: count, fps: fps, dzc: ShotSink.depthURL(entry, i),
                                         spool: entry.appendingPathComponent(String(format: "shot_%05d.spool", i)), checkpointURL: entry.appendingPathComponent(String(format: "shot_%05d.ck", i)))
                job.depthW = box.nw; job.depthH = box.nh
                job.experiments = expOptions   // 195h r3: the frozen snapshot travels with the job
                switch ShotPrepare.runResumable(job: job, backend: backend, hooks: hooks, reuseContext:reuseContext) {
                case .cancelled: bgra.close(); return
                case .suspended: bgra.close(); throw Failure(reason: "unexpected suspension")
                case .failed(let why): telemetry?.error("shot \(i) depth: \(why)"); sink.fail(shot: i, why); continue                        // the film goes on; the shot stays unprepared (2D) and is reported in render-ready.json
                case .done(let r):
                    _ = PrepareSupport.mergeFov(entry: entry, fps: fps, firstPts: facts.firstPTS, shot: i, r.fov)
                    var al: [String: Any] = [:]; if let a = r.alignScale { al["align_scale"] = a }; if let b = r.alignShift { al["align_shift"] = b }; if !r.alignTrack.isEmpty { al["align_track"] = r.alignTrack }   // s30: render reads baked metres; the track is for seek/audit
                    _ = PrepareSupport.writeJSON(al, to: alignURL)
                    try? fm.removeItem(at: job.spool); try? fm.removeItem(at: job.checkpointURL!)
                }
            }
            // 2b. 199h D2 (DISK-LAW): no source proxy. A shot publishes when its complete depth container stands: geometry sidecar,
            // progress.json and render-ready.json. The renderer reads the original film by frame index (RenderShotWriter).
            if DZCFile.isComplete(ShotSink.depthURL(entry, i)), PrepareSupport.optionsMatch(dzc: ShotSink.depthURL(entry, i), options: expOptions),
               !fm.fileExists(atPath: ShotSink.sidecarURL(entry, i).path) {
                let extra = ((try? Data(contentsOf: alignURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
                sink.finishShot(shot: i, depthSize: (w: box.nw, h: box.nh), sourceSize: src, extra: extra)
            }
        }
        bgra.close()
    }
}
#endif

// BEGIN relocated PrepareProcessLifetime.swift (195y G2, behavior unchanged)
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A model probe must not outlive the worker that requested it. Process groups
/// alone are insufficient: Foundation may spawn each Process in its own group.
enum PrepareProcessLifetime {
    static let ownerFlag = "--gor-owner-pid"
    static func watchOwner(arguments: [String]) {
        guard let at = arguments.firstIndex(of: ownerFlag), at + 1 < arguments.count,
              let owner = Int32(arguments[at + 1]), owner > 1 else { return }
        // Check before starting CoreML, then independently of its blocked load.
        guard getppid() == owner else { _exit(125) }
        Thread.detachNewThread {
            while getppid() == owner { Thread.sleep(forTimeInterval: 0.1) }
            _exit(125)
        }
    }

    struct Node { let pid: Int32, parent: Int32; let command: String }
    static func processTable() -> [Node] {
        let p=Process(), out=Pipe(); p.executableURL=URL(fileURLWithPath:"/bin/ps")
        p.arguments=["-axo","pid=,ppid=,command="];p.standardOutput=out;p.standardError=FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data=out.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit()
        return String(decoding:data,as:UTF8.self).split(separator:"\n").compactMap { line in
            let parts=line.split(maxSplits:2,whereSeparator:{$0 == " " || $0 == "\t"})
            guard parts.count==3,let pid=Int32(parts[0]),let parent=Int32(parts[1]) else{return nil}
            return Node(pid:pid,parent:parent,command:String(parts[2]))
        }
    }
    static func descendants(of root: Int32, nodes: [Node]) -> [Int32] {
        var result:[Int32]=[], frontier=[root]
        while let parent=frontier.popLast() {
            for node in nodes where node.parent==parent && node.pid != root && !result.contains(node.pid) {
                result.append(node.pid);frontier.append(node.pid)
            }
        }
        return result.reversed()
    }
    static func stopDescendants(of root: Int32) {
        for pid in descendants(of:root,nodes:processTable()) { _ = kill(pid,SIGKILL) }
    }
    /// Upgrade cleanup is restricted to orphaned helper modes of this project,
    /// never an interactive app, another project, or a still-owned worker.
    static func reapOrphanedHelpers(executable: URL) {
        let appRoot=executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let current=executable.path
        let previous=appRoot.appendingPathComponent(".gor-stage/gor.app.last/Contents/MacOS/gor").path
        for node in processTable() where node.parent==1 {
            if [current,previous].contains(where:{node.command.hasPrefix($0+" --gor-model-load-probe ") || node.command.hasPrefix($0+" --gor-prepare-worker ")}) {
                _ = kill(node.pid,SIGKILL)
                print("3d-helper reaped_orphan pid=\(node.pid)");fflush(stdout)
            }
        }
    }

    /// Shared by interactive prepare and the background self-test. Cancellation
    /// while waiting is cheap; neither path can load a second model stack.
    static func acquireLane(root: URL, cancelled: () -> Bool) -> Int32? {
        let fd = open(root.appendingPathComponent(".prepare-model-lane.lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { return nil }
        while !cancelled() {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 { return fd }
            Thread.sleep(forTimeInterval: 0.1)
        }
        close(fd); return nil
    }
    static func releaseLane(_ fd: Int32) { _ = flock(fd, LOCK_UN); close(fd) }
}
// END relocated PrepareProcessLifetime.swift


// END relocated NativePrepareRunner.swift
// BEGIN relocated PrepareSupport.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Pure helpers of the native prepare runner (190t/190v), tested on Linux against the Python they mirror: SHA-256 and cache_key (tools/depth_analysis/cache.py), the
/// nearest-playhead-first shot order (prepare_film.work_chunk), and the cuts.json / fov_track.json entry files (prepare_film._cuts_for / work_chunk).
enum SHA256Pure {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]
    struct Hasher {
        private var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        private var buf: [UInt8] = [], total: UInt64 = 0
        mutating func update(_ d: [UInt8]) { total += UInt64(d.count); buf += d; var o = 0; while buf.count - o >= 64 { block(Array(buf[o..<(o + 64)])); o += 64 }; buf.removeFirst(o) }
        mutating func update(_ s: String) { update(Array(s.utf8)) }
        private mutating func block(_ b: [UInt8]) {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 { w[i] = UInt32(b[4 * i]) << 24 | UInt32(b[4 * i + 1]) << 16 | UInt32(b[4 * i + 2]) << 8 | UInt32(b[4 * i + 3]) }
            func rr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
            for i in 16..<64 { let s0 = rr(w[i - 15], 7) ^ rr(w[i - 15], 18) ^ (w[i - 15] >> 3), s1 = rr(w[i - 2], 17) ^ rr(w[i - 2], 19) ^ (w[i - 2] >> 10); w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1 }
            var a = h[0], b_ = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rr(e, 6) ^ rr(e, 11) ^ rr(e, 25), ch = (e & f) ^ (~e & g), t1 = hh &+ S1 &+ ch &+ SHA256Pure.k[i] &+ w[i]
                let S0 = rr(a, 2) ^ rr(a, 13) ^ rr(a, 22), mj = (a & b_) ^ (a & c) ^ (b_ & c), t2 = S0 &+ mj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b_; b_ = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b_; h[2] = h[2] &+ c; h[3] = h[3] &+ d; h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        mutating func hex() -> String {
            let bits = total * 8; var pad: [UInt8] = [0x80]; while (buf.count + pad.count) % 64 != 56 { pad.append(0) }
            for i in (0..<8).reversed() { pad.append(UInt8((bits >> (8 * UInt64(i))) & 0xFF)) }
            let t = total; update(pad); total = t
            return h.map { String(format: "%08x", $0) }.joined()
        }
    }
}

enum PrepareSupport {
    /// cache.py cache_key: sha256 over "size:mtime_ns", the first 1 MiB and (size > 2 MiB) the last 1 MiB. nil when the file cannot be read.
    static func cacheKey(path: String) -> String? {
        var st = stat(); guard stat(path, &st) == 0, let fh = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? fh.close() }
        #if canImport(Darwin)
        let ns = Int64(st.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(st.st_mtimespec.tv_nsec)
        #else
        let ns = Int64(st.st_mtim.tv_sec) * 1_000_000_000 + Int64(st.st_mtim.tv_nsec)
        #endif
        var h = SHA256Pure.Hasher(); let size = Int64(st.st_size), mb = 1024 * 1024
        h.update("\(size):\(ns)")
        h.update([UInt8]((try? fh.read(upToCount: mb)) ?? Data()))
        if size > 2 * Int64(mb) { try? fh.seek(toOffset: UInt64(size - Int64(mb))); h.update([UInt8]((try? fh.read(upToCount: mb)) ?? Data())) }
        return h.hex()
    }

    /// prepare_film.work_chunk order: shots missing depth or source, nearest the playhead first (the shot holding it, then by distance, ties to the lower index).
    static func pendingOrder(shots: [[Int]], done: Set<Int>, playheadFrame: Int?) -> [Int] {
        let pending = shots.indices.filter { !done.contains($0) }
        guard let p = playheadFrame else { return pending }
        func dist(_ i: Int) -> Int { let s = shots[i][0], e = shots[i][1]; return (s <= p && p <= e) ? 0 : min(abs(p - s), abs(p - e)) }
        return pending.sorted { (dist($0), $0) < (dist($1), $1) }
    }

    static func readJSON(_ url: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
    /// 195h r2-5/r3-2 + Delivery block 2: does one prepared depth CONTAINER match this request's PREPARE identity? Prepare identity is the
    /// depth-mode switches alone (today: B depth-range EMA; item A adds the depth model). E/G/hole are render-only: they re-RENDER through
    /// the render key but must never mark a depth container mismatched. An absent marker is pre-195h depth: EMA off, whatever E/G/hole say.
    static func optionsMatch(dzc: URL, options: ThreeDExperimentOptions) -> Bool {
        identityMatch(readJSON(dzc.appendingPathExtension("options.json")), options: options)
    }
    /// 195h A (Delivery A-4): the prepare identity recorded in BOTH markers (the container's options.json and the pre-phase-1
    /// spool identity.json). The marker names the depth MODEL and smoother too; an absent marker is pre-195h work, matching only the all-off identity.
    static func prepareIdentity(_ options: ThreeDExperimentOptions) -> [String: Any] {
        ["depth_range_ema": options.depthRangeEMA,
         "depth_model": options.dav2Depth ? DepthModelID.dav2_small_coreml.rawValue : DepthModelID.luma_y_prior.rawValue,
         "dav2_temporal_ema": options.dav2TemporalEMA]
    }
    static func identityMatch(_ o: [String: Any]?, options: ThreeDExperimentOptions) -> Bool {
        guard let o = o else { return !options.depthRangeEMA && !options.dav2Depth && !options.dav2TemporalEMA }
        return (o["depth_range_ema"] as? Bool ?? false) == options.depthRangeEMA
            && (o["depth_model"] as? String ?? DepthModelID.luma_y_prior.rawValue) == (options.dav2Depth ? DepthModelID.dav2_small_coreml.rawValue : DepthModelID.luma_y_prior.rawValue)
            && (o["dav2_temporal_ema"] as? Bool ?? false) == options.dav2TemporalEMA
    }
    /// 195h r3-2: what the prepare job must do with the container at `dzc`, decided BEFORE the writer opens. .rebuild = a mismatched
    /// existing container is never resumed: the caller removes it and writes a fresh one in the request's mode.
    enum ContainerAction: String { case fresh, resume, rebuild }
    static func containerAction(dzc: URL, options: ThreeDExperimentOptions) -> ContainerAction {
        guard FileManager.default.fileExists(atPath: dzc.path) else { return .fresh }
        return optionsMatch(dzc: dzc, options: options) ? .resume : .rebuild
    }
    /// 195h A (Delivery A-4): the identity marker written BEFORE phase 1 next to the spool/checkpoint it covers. The container's
    /// options.json exists only once phase 2 opened the writer, so a phase-1 interruption leaves per-shot work no container fence can
    /// see; the next job in another mode checks THIS marker before touching that work.
    static func spoolIdentityURL(spool: URL) -> URL { spool.appendingPathExtension("identity.json") }
    /// The same shot's align sidecar (shot_NNNNN.spool -> shot_NNNNN.align.json, NativePrepareRunner).
    static func alignURL(spool: URL) -> URL { spool.deletingPathExtension().appendingPathExtension("align.json") }
    /// What to do with per-shot phase-1 work when NO container exists yet: a mismatched spool/checkpoint is never resumed.
    static func spoolAction(spool: URL, checkpoint: URL?, options: ThreeDExperimentOptions) -> ContainerAction {
        let fm = FileManager.default
        let hasWork = fm.fileExists(atPath: spool.path) || checkpoint.map { fm.fileExists(atPath: $0.path) } == true
        guard hasWork else { return .fresh }
        return identityMatch(readJSON(spoolIdentityURL(spool: spool)), options: options) ? .resume : .rebuild
    }
    static func writeJSON(_ obj: Any, to url: URL) -> Bool {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return false }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-" + url.lastPathComponent)
        guard (try? DepthCacheIO.write(d,to:tmp,atomic:false)) != nil else { return false }
        try? FileManager.default.removeItem(at: url); return (try? FileManager.default.moveItem(at: tmp, to: url)) != nil
    }
    /// cuts.json = {"cuts": [...], "shots": [[s, e], ...]} (prepare_film._cuts_for). Returns the cached shots when present.
    static func readCuts(entry: URL) -> [[Int]]? {
        guard let d = try? Data(contentsOf: entry.appendingPathComponent("cuts.json")), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let s = o["shots"] as? [[Int]], !s.isEmpty else { return nil }
        return s
    }
    static func writeCuts(entry: URL, cuts: [Int], shots: [[Int]]) -> Bool { writeJSON(["cuts": cuts, "shots": shots], to: entry.appendingPathComponent("cuts.json")) }
    /// fov_track.json = {"fps": fps, "first_pts": first film PTS, "shots": [entry or null per shot]}: set shot `i`, padding with null (work_chunk).
    /// 199h D2: first_pts maps the pipeline's zero-based frame PTS back onto film PTS for the renderer's original-film read window.
    static func mergeFov(entry: URL, fps: Double, firstPts: Double = 0, shot i: Int, _ e: FovTrackBuilder.Entry) -> Bool {
        let u = entry.appendingPathComponent("fov_track.json")
        var shots = ((try? Data(contentsOf: u)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["shots"] as? [Any]) ?? []
        while shots.count <= i { shots.append(NSNull()) }
        shots[i] = e.json
        return writeJSON(["fps": fps, "first_pts": firstPts, "shots": shots], to: u)
    }
}

// BEGIN relocated PrepareWorkerJob.swift (195y G2, behavior unchanged)
/// 195h Delivery (process boundary): the prepare-worker job file contract, isolated pure-Foundation so production AND the Linux test
/// driver compile this exact type (no shadow copy). `experiments` (the prepare-component string, e.g. "ema") is written by
/// PrepareWorker.spawn from req.experiments and read back through `request`; pre-195h job files without the key decode to the default
/// mode (""), never as an error.
struct PrepareWorkerJob: Codable {
    let film: String, fps: Double, frames: Int, start: Double, quality: String
    let kit: String, cache: String, models: String?
    let experiments: String
    /// arch-196b C3: the cooperative-pause flag path (a sibling of this job file). The worker polls it at every frame boundary;
    /// "" = never paused. Pre-C3 job files without the key decode to "", never as an error.
    let pauseFlag: String
    init(film: String, fps: Double, frames: Int, start: Double, quality: String, kit: String, cache: String, models: String?, experiments: String = "", pauseFlag: String = "") {
        self.film = film; self.fps = fps; self.frames = frames; self.start = start; self.quality = quality
        self.kit = kit; self.cache = cache; self.models = models; self.experiments = experiments; self.pauseFlag = pauseFlag
    }
    /// 195h Delivery (process boundary): the prepare-mode identity crosses to the worker in this file; a pre-195h job file without
    /// the key decodes as the default mode (""), never as an error.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        film = try c.decode(String.self, forKey: .film); fps = try c.decode(Double.self, forKey: .fps)
        frames = try c.decode(Int.self, forKey: .frames); start = try c.decode(Double.self, forKey: .start)
        quality = try c.decode(String.self, forKey: .quality); kit = try c.decode(String.self, forKey: .kit)
        cache = try c.decode(String.self, forKey: .cache); models = try c.decodeIfPresent(String.self, forKey: .models)
        experiments = try c.decodeIfPresent(String.self, forKey: .experiments) ?? ""
        pauseFlag = try c.decodeIfPresent(String.self, forKey: .pauseFlag) ?? ""
    }
    var request: ThreeDPrepareLauncher.Request { .init(film: URL(fileURLWithPath: film), fps: fps, nFrames: frames, startPTS: start, quality: quality, experiments: experiments) }
}
// END relocated PrepareWorkerJob.swift
// END relocated PrepareSupport.swift
// BEGIN relocated PrepareTelemetry.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 3D self-test telemetry (Main 09:04): stage timings, notes, thermal transitions, depth stats and verbatim errors, rendered as stable `gor3d-selftest` log lines
/// the next iteration parses (`PrepareTelemetry.parse`). Pure Foundation: the format is pinned on Linux. Thread-safe (prepare thread, thermal observer, render).
final class PrepareTelemetry {
    static let tag = "gor3d-selftest", version = 1
    struct Stage: Equatable { var ms = 0.0, n = 0, max = 0.0 }
    struct Thermal: Equatable { var tMs: Double; var level: Int }
    struct DepthStats: Equatable { var min = Double.infinity, max = -Double.infinity, nan = 0, inf = 0, count = 0 }

    private let lock = NSLock()
    private(set) var stages: [(name: String, s: Stage)] = []
    private(set) var notes: [(key: String, value: String)] = []
    private(set) var errors: [String] = []
    private(set) var thermal: [Thermal] = []
    private(set) var depth = DepthStats()
    private let t0 = DispatchTime.now()

    var elapsedMs: Double { Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6 }
    func add(_ name: String, ms: Double) {
        lock.lock(); defer { lock.unlock() }
        if let i = stages.firstIndex(where: { $0.name == name }) { stages[i].s.ms += ms; stages[i].s.n += 1; stages[i].s.max = Swift.max(stages[i].s.max, ms) }
        else { stages.append((name, Stage(ms: ms, n: 1, max: ms))) }
    }
    func time<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        let s = DispatchTime.now(); defer { add(name, ms: Double(DispatchTime.now().uptimeNanoseconds - s.uptimeNanoseconds) / 1e6) }
        return try body()
    }
    /// s31 (CONTRACT-190v real-time budget): turns the measured stage totals into per-frame milliseconds beside the ANALYTICAL s31 estimates (VR180 worst: VDA 8.2, MoGe amortised 9.6,
    /// post 0.4, VT ~2 ms/frame; MoGe keyframe burst 114.6 ms), so the first Mac run shows how far the model is off. `frames` = frames the shot's prepare covered. Missing stages are
    /// simply omitted. The render stage is the self-test's small eyeN=256 clip: its per-frame ms is a lower bound, not the 60 fps VR180 post cost.
    func addRealtimeBudget(frames: Int, keyframeStride: Int = 12) {
        guard frames > 0 else { return }
        func st(_ n: String) -> Stage? { lock.lock(); defer { lock.unlock() }; return stages.first(where: { $0.name == n })?.s }
        func ms(_ v: Double) -> String { String(format: "%.2f", v) }
        var model = 0.0, haveModel = false
        if let v = st("vda_step_total"), v.n > 0 { note("rt_vda_ms_per_frame", ms(v.ms / Double(v.n)) + " (s31 est 8.2 VR180)"); model += v.ms / Double(frames); haveModel = true }
        if let m = st("moge_step_total"), m.n > 0 {
            note("rt_moge_ms_per_keyframe", ms(m.ms / Double(m.n)) + " max " + ms(m.max) + " (s31 est 28.6 16:9, 114.6 VR180)")
            note("rt_moge_ms_amortized", ms(m.ms / Double(frames)) + " per frame at stride \(keyframeStride) (s31 est 9.6)"); model += m.ms / Double(frames); haveModel = true
        }
        if let r = st("render_shot") { note("rt_render_ms_per_frame", ms(r.ms / Double(frames)) + " (eyeN 256 clip, lower bound)") }
        if haveModel {
            note("rt_model_ms_per_frame", ms(model) + " (VDA + amortised MoGe)")
            for fps in [24.0, 30.0, 60.0] { note("rt_budget_\(Int(fps))fps", ms(1000 / fps) + " ms/frame: " + (model <= 1000 / fps ? "model pair fits" : "model pair BREAKS")) }
            if let m = st("moge_step_total"), m.n > 0 { note("rt_keyframe_burst_vs_frame_60fps", m.max > 1000.0 / 60 ? "burst exceeds a 60 fps frame (must stay off the playback thread)" : "burst fits a 60 fps frame") }
        }
    }
    /// s32 `rtstage` lines (CONTRACT-190v s32): per-stage real-time ms, `ms` = MEAN per unit (per frame; per keyframe for moge), n units, max_ms the worst one. Emit order = `rtOrder`.
    static let rtOrder = ["vda", "moge", "upsample", "surround", "render", "vt_decode", "vt_encode"]
    private(set) var rtStages: [(name: String, s: Stage)] = []
    func rtStage(_ name: String, meanMs: Double, n: Int, maxMs: Double) {
        lock.lock(); defer { lock.unlock() }
        rtStages.removeAll { $0.name == name }; rtStages.append((name, Stage(ms: meanMs, n: n, max: maxMs)))
    }
    /// Mean-per-unit rtstage from a recorded stage total (vda per frame, moge per keyframe).
    func rtStageFromTotal(_ name: String, stage: String) {
        lock.lock(); let st = stages.first(where: { $0.name == stage })?.s; lock.unlock()
        if let s = st, s.n > 0 { rtStage(name, meanMs: s.ms / Double(s.n), n: s.n, maxMs: s.max) }
    }
    func note(_ key: String, _ value: String) { lock.lock(); notes.append((key, value)); lock.unlock() }
    func error(_ text: String) { lock.lock(); errors.append(text); lock.unlock() }
    /// Records a thermal level (0 nominal ... 3 critical); only changes are kept, the first sample is always kept.
    func thermalSample(level: Int) { lock.lock(); if thermal.last?.level != level { thermal.append(Thermal(tMs: elapsedMs, level: level)) }; lock.unlock() }
    var peakThermal: Int { lock.lock(); defer { lock.unlock() }; return thermal.map { $0.level }.max() ?? -1 }
    private var jitter = DepthGuards.JitterAccumulator(pixelStride: 2)       // s35: depth jitter per frame (failure_probes jitter_rel), reported once in the log
    func depthFrame(_ z: [Float]) {
        var mn = Double.infinity, mx = -Double.infinity, nan = 0, inf = 0
        for v in z { if v.isNaN { nan += 1 } else if v.isInfinite { inf += 1 } else { let d = Double(v); if d < mn { mn = d }; if d > mx { mx = d } } }
        lock.lock(); jitter.add(z: z); depth.min = Swift.min(depth.min, mn); depth.max = Swift.max(depth.max, mx); depth.nan += nan; depth.inf += inf; depth.count += z.count; lock.unlock()
    }

    // MARK: log format. One line per fact: `gor3d-selftest v1 <kind> k=v k=v`; values never contain spaces except `error`/`note` text, which is the line tail after `msg=`/`value=`.
    static func escape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") }
    static func unescape(_ s: String) -> String {
        var out = "", it = s.makeIterator()
        while let c = it.next() { if c == "\\", let n = it.next() { out.append(n == "n" ? "\n" : (n == "r" ? "\r" : n)) } else { out.append(c) } }
        return out
    }
    private static func f(_ v: Double) -> String { v.isFinite ? String(format: "%.3f", v) : (v.isNaN ? "nan" : (v > 0 ? "inf" : "-inf")) }

    func lines(header: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        let p = "\(Self.tag) v\(Self.version) "
        var out = [p + "begin " + Self.escape(header)]
        for (n, s) in stages { out.append(p + "stage name=\(n) ms=\(Self.f(s.ms)) n=\(s.n) max_ms=\(Self.f(s.max))") }
        for t in thermal { out.append(p + "thermal t_ms=\(Self.f(t.tMs)) level=\(t.level)") }
        out.append(p + "thermal_peak level=\(thermal.map { $0.level }.max() ?? -1) transitions=\(Swift.max(0, thermal.count - 1))")
        out.append(p + "depth min=\(Self.f(depth.min)) max=\(Self.f(depth.max)) nan=\(depth.nan) inf=\(depth.inf) count=\(depth.count)")
        for (k, v) in notes { out.append(p + "note key=\(k) value=" + Self.escape(v)) }
        if let j = jitter.value { out.append(p + "note key=jitter_rel value=" + Self.f(j) + " (median |d inv|/median inv per frame, pixel stride 2; dark/noisy scenes measured 0.25, healthy < 0.05)") }
        for n in Self.rtOrder { if let r = rtStages.first(where: { $0.name == n }) { out.append(p + "rtstage name=\(n) ms=\(Self.f(r.s.ms)) n=\(r.s.n) max_ms=\(Self.f(r.s.max))") } }
        for (i, e) in errors.enumerated() { out.append(p + "error i=\(i) msg=" + Self.escape(e)) }
        out.append(p + "end errors=\(errors.count) total_ms=\(Self.f(elapsedMs))")
        return out
    }

    struct Parsed: Equatable {
        var header = "", stages: [String: Stage] = [:], thermal: [Thermal] = [], peak = -2, transitions = -1, depth = DepthStats(), notes: [String: String] = [:], errors: [String] = [], ended = false, rtstages: [String: Stage] = [:]
    }
    /// Reads back any lines of this version out of a larger log (other lines are ignored).
    static func parse(_ log: [String]) -> Parsed {
        var r = Parsed(); let p = "\(tag) v\(version) "
        func kv(_ s: Substring) -> [String: String] { var d: [String: String] = [:]; for part in s.split(separator: " ") { if let e = part.firstIndex(of: "=") { d[String(part[..<e])] = String(part[part.index(after: e)...]) } }; return d }
        func num(_ s: String?) -> Double { switch s { case "nan": return .nan; case "inf": return .infinity; case "-inf": return -.infinity; default: return Double(s ?? "") ?? .nan } }
        for line in log {
            guard let rng = line.range(of: p) else { continue }
            let rest = line[rng.upperBound...]
            if rest.hasPrefix("begin ") { r.header = unescape(String(rest.dropFirst(6))) }
            else if rest.hasPrefix("stage ") { let d = kv(rest.dropFirst(6)); if let n = d["name"] { r.stages[n] = Stage(ms: num(d["ms"]), n: Int(d["n"] ?? "") ?? 0, max: num(d["max_ms"])) } }
            else if rest.hasPrefix("rtstage ") { let d = kv(rest.dropFirst(8)); if let n = d["name"] { r.rtstages[n] = Stage(ms: num(d["ms"]), n: Int(d["n"] ?? "") ?? 0, max: num(d["max_ms"])) } }
            else if rest.hasPrefix("thermal_peak ") { let d = kv(rest.dropFirst(13)); r.peak = Int(d["level"] ?? "") ?? -2; r.transitions = Int(d["transitions"] ?? "") ?? -1 }
            else if rest.hasPrefix("thermal ") { let d = kv(rest.dropFirst(8)); r.thermal.append(Thermal(tMs: num(d["t_ms"]), level: Int(d["level"] ?? "") ?? -1)) }
            else if rest.hasPrefix("depth ") { let d = kv(rest.dropFirst(6)); r.depth = DepthStats(min: num(d["min"]), max: num(d["max"]), nan: Int(d["nan"] ?? "") ?? 0, inf: Int(d["inf"] ?? "") ?? 0, count: Int(d["count"] ?? "") ?? 0) }
            else if rest.hasPrefix("note key=") { let t = rest.dropFirst(9); if let sp = t.range(of: " value=") { r.notes[String(t[..<sp.lowerBound])] = unescape(String(t[sp.upperBound...])) } }
            else if rest.hasPrefix("error i=") { if let m = rest.range(of: " msg=") { r.errors.append(unescape(String(rest[m.upperBound...]))) } }
            else if rest.hasPrefix("end ") { r.ended = true }
        }
        return r
    }
}
// END relocated PrepareTelemetry.swift
// BEGIN relocated FilmPrepareStatus.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// OSD text for "Prepare film" (190u U2). Reads <cacheRoot>/current-film.json
/// {"progress_path","n_frames","cache_key"} and the progress.json it names
/// {"prepared":[[first,last],...]} (inclusive ranges). The string matches
/// PrepareFilm.status() in tools/depth_analysis/prepare_film.py.
/// Not wired to a cache root or an OSD surface yet; pure and side-effect free.
enum FilmPrepareStatus {
    static func text(prepared: Int, total: Int) -> String {
        prepared < total ? "3D prepared: \(prepared)/\(total) frames" : "3D prepared: full film"
    }

    static func preparedFrames(_ ranges: [[Int]]) -> Int {
        ranges.reduce(0) { $0 + (($1.count == 2 && $1[1] >= $1[0]) ? $1[1] - $1[0] + 1 : 0) }
    }

    /// nil when no 3D film is open or the files are unreadable (OSD shows nothing).
    static func read(cacheRoot: URL) -> String? {
        guard let ptrData = try? Data(contentsOf: cacheRoot.appendingPathComponent("current-film.json")),
              let ptr = try? JSONSerialization.jsonObject(with: ptrData) as? [String: Any],
              let path = ptr["progress_path"] as? String, let total = ptr["n_frames"] as? Int, total > 0 else { return nil }
        var ranges: [[Int]] = []
        if let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let r = j["prepared"] as? [[Int]] { ranges = r }
        return text(prepared: min(preparedFrames(ranges), total), total: total)
    }
}

/// CONTRACT-190v section 4. Cache root = Application Support/gor/depth-cache (the analysis lane writes
/// current-film.json and progress.json there; this app only reads them and writes render-prefs.json).
enum DepthCachePaths {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("gor/depth-cache", isDirectory: true)
    }
}

/// <cache_root>/render-prefs.json, atomic tmp+rename. Defaults match the contract; E-G re-reads on change.
enum RenderPrefs {
    static let modes = ["off", "sbs", "full_sbs", "half_sbs", "over_under", "anaglyph", "vr180"]   // s36: "sbs" = legacy alias of full_sbs
    static func json(mode: String, depthScale: Double = 1.0, ipdM: Double = 0.063, convergenceM: Double? = nil, screenDeg: Double? = nil, surroundSoft: Bool? = nil, overBudget: Bool = false) -> Data? {
        guard modes.contains(mode), depthScale.isFinite, depthScale >= 0, ipdM.isFinite, ipdM > 0 else { return nil }
        if let d = screenDeg, !(d.isFinite && (d == 0 || (d >= 20 && d <= 150))) { return nil }   // screen_deg: 0 = legacy shot fov, else 20...150
        var o: [String: Any] = ["mode": mode, "depth_scale": depthScale, "ipd_m": ipdM]
        o["convergence_m"] = convergenceM ?? NSNull()
        if let d = screenDeg { o["screen_deg"] = d }
        if let v = surroundSoft { o["surround"] = v ? "soft" : "off" }
        if overBudget { o["over_budget"] = true }
        return try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])
    }
    @discardableResult
    static func write(mode: String, depthScale: Double = 1.0, ipdM: Double = 0.063, convergenceM: Double? = nil, screenDeg: Double? = nil, surroundSoft: Bool? = nil, overBudget: Bool = false, root: URL = DepthCachePaths.root) -> Bool {
        guard let data = json(mode: mode, depthScale: depthScale, ipdM: ipdM, convergenceM: convergenceM, screenDeg: screenDeg, surroundSoft: surroundSoft, overBudget: overBudget) else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let tmp = root.appendingPathComponent("render-prefs.json.tmp"), dst = root.appendingPathComponent("render-prefs.json")
        do { try DepthCacheIO.write(data,to:dst); return true } catch { return false }
    }
}

/// Shows the prepared-range text through mpv show-text, only when it changes. Polls every 2 s on the main run loop;
/// does nothing until current-film.json exists (3D mode open). Reads only; never touches the analysis cache.
final class FilmPrepareOSD {
    static let shared = FilmPrepareOSD()
    private var timer: Timer?
    private var lastShown: String?
    func start(send: @escaping (String) -> Void) {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            if UserDefaults.standard.object(forKey: "gor.3d.osdLine") != nil, !UserDefaults.standard.bool(forKey: "gor.3d.osdLine") { return }   // menu: osd line off
            guard let self, let t = FilmPrepareStatus.read(cacheRoot: DepthCachePaths.root), t != self.lastShown else { return }
            self.lastShown = t
            send(t)
        }
        timer?.tolerance = 0.5
    }
}

/// CONTRACT-190v section 4 availability: SBS and VR180 are enabled for a frame range iff it lies inside ONE prepared range.
enum PreparedRanges {
    static func covers(_ ranges: [[Int]], first: Int, last: Int) -> Bool {
        last >= first && ranges.contains { $0.count == 2 && $0[0] <= first && last <= $0[1] }
    }
    static func load(cacheRoot: URL) -> [[Int]] {
        guard let p = try? Data(contentsOf: cacheRoot.appendingPathComponent("current-film.json")),
              let ptr = try? JSONSerialization.jsonObject(with: p) as? [String: Any], let path = ptr["progress_path"] as? String,
              let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let r = j["prepared"] as? [[Int]] else { return [] }
        return r
    }
}
// END relocated FilmPrepareStatus.swift
// BEGIN relocated ThreeDPreflight.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(VideoToolbox)
import VideoToolbox
#endif

/// 190t preflight: can this machine prepare and play 3D? Runtime check only, no install, no network, no brew, never touches playback.
/// Prepare writes its HEVC files in-app with VideoToolbox (VTShotEncoder), so no ffmpeg/libx265 is needed. Checks: (1) VideoToolbox lists an HEVC
/// encoder; (2) VideoToolbox can hardware-decode HEVC (AVFoundation reads the depth and source files with it); (3) the player lists an HEVC decoder
/// (`<player> --vd=help`, same probe as RenderedShotMPV) to play the render files. When one is missing the 3d mode entries show the plain reason and
/// stay disabled, so playback stays 2D. Probed once, off the main thread. Not compiled or run on a Mac.
final class ThreeDPreflight {
    static let shared = ThreeDPreflight()
    private let lock = NSLock()
    private var started = false
    private var result: String??                          // nil = not probed yet; .some(nil) = fine; .some(reason) = unavailable

    /// nil while unprobed or fine; otherwise the plain reason the 3d modes are off.
    var reason: String? { lock.lock(); defer { lock.unlock() }; if case .some(.some(let r)) = result { return r }; return nil }

    /// Pure decision from the three probe results.
    static func decide(vtEncodesHEVC: Bool, vtDecodesHEVC: Bool, decoders: [String]) -> String? {
        if !vtEncodesHEVC { return "3d needs the HEVC encoder in VideoToolbox (not available), staying 2d" }
        if !vtDecodesHEVC { return "3d needs HEVC decoding in VideoToolbox (not available), staying 2d" }
        if !decoders.contains("hevc") { return "3d needs an HEVC decoder in the player (none listed), staying 2d" }
        return nil
    }

    #if canImport(VideoToolbox)
    static func vtEncodesHEVC() -> Bool {
        var list: CFArray?
        guard VTCopyVideoEncoderList(nil, &list) == noErr, let items = list as? [[String: Any]] else { return false }
        return items.contains { ($0[kVTVideoEncoderList_CodecType as String] as? UInt32) == kCMVideoCodecType_HEVC }
    }
    static func vtDecodesHEVC() -> Bool { VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) }
    #endif

    /// Idempotent. `mpvExecutable` is the same closure the coordinator uses; called on the probe thread.
    func start(mpvExecutable: @escaping () -> URL?) {
        lock.lock(); if started { lock.unlock(); return }; started = true; lock.unlock()
        DispatchQueue.global(qos: .utility).async { [self] in
            #if canImport(VideoToolbox)
            let enc = Self.vtEncodesHEVC(), dec = Self.vtDecodesHEVC()
            #else
            let enc = false, dec = false
            #endif
            // The player process may not exist yet when this starts (wiring runs before the first launch): wait for it, up to 90 s, and never
            // report "no decoder" for a player that was not probed; an unprobed player leaves the modes enabled (reason stays nil).
            var exe = mpvExecutable(), waited = 0
            while exe == nil, waited < 90 { Thread.sleep(forTimeInterval: 1); waited += 1; exe = mpvExecutable() }
            guard let player = exe else { return }
            var pl = RenderedShotMPV.probeDecoders(executable: player)
            if pl.isEmpty { Thread.sleep(forTimeInterval: 2); pl = RenderedShotMPV.probeDecoders(executable: player) }   // one retry for a transient empty read
            let r = Self.decide(vtEncodesHEVC: enc, vtDecodesHEVC: dec, decoders: pl)
            lock.lock(); result = .some(r); lock.unlock()
        }
    }
}
// END relocated ThreeDPreflight.swift
// BEGIN relocated ThreeDPrepareLauncher.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190t A: the app-side seam that starts and stops the prepare step (tools/depth_analysis/prepare_driver.run_prepare) for the open film.
/// Only the RUNTIME is left open: `spawn` is injected (python + checkpoints, a bundled helper, ...). With no spawn the launcher says so once on the OSD
/// and the film stays 2D. It never touches playback. Progress comes from render-ready.json (CONTRACT-190v s8), read by `progress(entry:)`.
final class ThreeDPrepareLauncher {
    struct Request: Equatable { let film: URL; let fps: Double; let nFrames: Int; let startPTS: Double; let quality: String; var experiments = "" }   // 195h r3: the experiment-mode component; a flip restarts prepare
    struct Handle { let stop: () -> Void; var pause: () -> Void = {}; var resume: () -> Void = {} }
    enum Decision: Equatable { case none, stop, start(Request), report(String) }

    /// Pure rule. `running` = the film the current job prepares (nil = none), `failedFor` = a film whose last job exited with failure.
    static func decide(mode: String, film: URL?, playhead: Double?, info: (fps: Double, frames: Int)?, quality: String, experiments: String = "", preflightReason: String?,
                       running: URL?, failedFor: URL?, hasRuntime: Bool) -> Decision {
        let wanted = mode != "off" && preflightReason == nil && film != nil
        if let r = running { return (!wanted || film != r) ? .stop : .none }
        guard wanted, let f = film else { return .none }
        if failedFor == f { return .none }                            // no retry loop; a new film or a mode toggle clears it
        guard let i = info, i.fps > 0, i.frames > 0 else { return .none }
        guard hasRuntime else { return .report("3D: no prepare runtime on this build, staying 2D") }
        return .start(Request(film: f, fps: i.fps, nFrames: i.frames, startPTS: max(0, playhead ?? 0), quality: quality, experiments: experiments))
    }

    /// (ready, failed, total) shots from <entry>/render-ready.json; nil when absent or unreadable.
    static func progress(entry: URL) -> (ready: Int, failed: Int, total: Int)? {
        guard let d = try? Data(contentsOf: entry.appendingPathComponent("render-ready.json")),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let n = o["n_shots"] as? Int, let r = o["n_ready"] as? Int else { return nil }
        return (r, (o["n_failed"] as? Int) ?? 0, n)
    }

    typealias Spawn = (Request, @escaping (Bool) -> Void) -> Handle?
    private let spawn: () -> Spawn?                         // late-bound: the runner may register after wiring
    private let report: (String) -> Void
    private var handle: Handle?, running: URL?, failedFor: URL?, lastMode = "off", told = Set<String>(), runningExperiments = "", lastExperiments = "", generation = 0
    private var pendingIdentity = "", settleAt = 0.0
    var settleDelay = ThreeDPrepareLauncher.settleSeconds
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }
    static let settleSeconds = 0.5 // same coalescing window as the render lane

    init(spawn: @escaping () -> Spawn?, report: @escaping (String) -> Void) { self.spawn = spawn; self.report = report }

    /// Call from a timer on the main thread with the current state. Idempotent.
    func cancelForMediaTransition() {
        generation += 1
        handle?.stop();handle=nil;running=nil;failedFor=nil
        pendingIdentity="";settleAt=0;pausedAt=nil
    }
    /// arch-196b C3: a cooperative pause parks the worker at a frame boundary holding no in-flight model call. Past this long
    /// parked, the worker is cancelled instead (cancelForMediaTransition path); turning 3D back on starts a fresh job, which
    /// resumes exactly from the persisted GORCK003 checkpoint.
    static let pauseCancelSeconds = 30.0
    private var pausedAt: Double? = nil
    func setPaused(_ paused:Bool) {
        if paused { if pausedAt == nil { pausedAt = clock() }; handle?.pause() }   // transition-only: repeated polls never reset the clock
        else { pausedAt = nil; handle?.resume() }
    }
    var isPreparing: Bool { running != nil }
    /// 195h r3-4 + Delivery block 1: the render lane found a prepared container in another experiment mode and reports the CURRENT mode
    /// (`experiments`). Stop a running job only when it runs in a DIFFERENT mode; a job already preparing the current mode (the rebuild
    /// itself) is never stopped, so the render lane may report on every 250 ms tick while the rebuild runs. With nothing running this is a
    /// no-op: the periodic update() starts the current-mode prepare, which rebuilds mismatched containers (never resumes them).
    func noteModeMismatch(current experiments: String) {
        if running != nil, runningExperiments != experiments { handle?.stop(); handle = nil; running = nil; generation += 1; pausedAt = nil }
    }
    func update(mode: String, film: URL?, playhead: Double?, info: (fps: Double, frames: Int)?, quality: String, experiments: String = "", preflightReason: String?) {
        let identity = (film?.absoluteString ?? "none") + "|" + experiments
        if identity != pendingIdentity { pendingIdentity=identity; settleAt=clock()+settleDelay }
        if experiments != lastExperiments { failedFor=nil; lastExperiments=experiments }
        if running != nil, experiments != runningExperiments { handle?.stop(); handle = nil; running = nil; generation += 1; pausedAt = nil }   // 195h r3-4: a prepare-mode flip stops the old-mode job; decide below starts the current-mode one
        if let t = pausedAt, clock() - t > Self.pauseCancelSeconds { cancelForMediaTransition() }   // C3: parked longer than 30 s -> cancel; the next start resumes from the checkpoint
        if let active=running,film==active,mode=="off" {setPaused(true);lastMode=mode;return}
        if mode != "off",lastMode=="off" {setPaused(false)}
        if mode != lastMode { failedFor = nil; lastMode = mode }
        // Stop stale work immediately, but start only the final settled choice.
        if mode != "off", clock() < settleAt { return }
        let sp = spawn()
        switch Self.decide(mode: mode, film: film, playhead: playhead, info: info, quality: quality, experiments: experiments, preflightReason: preflightReason,
                           running: running, failedFor: failedFor, hasRuntime: sp != nil) {
        case .none: break
        case .stop: handle?.stop(); handle = nil; running = nil; generation += 1; pausedAt = nil
        case .report(let t): if told.insert(t).inserted { report(t) }
        case .start(let req):
            generation += 1; let g = generation   // Delivery 4: the completion of a stopped/older job must never clear or fail the current one
            running = req.film; runningExperiments = req.experiments
            handle = sp?(req) { [weak self] ok in
                DispatchQueue.main.async { guard let self, g == self.generation else { return }; if !ok { self.failedFor = self.running; self.report(DepthCacheBudget.failure(root:DepthCachePaths.root)?.description ?? "3D depth preparation failed; staying on the last good image or 2D (see log)") }; self.running = nil; self.handle = nil }
            }
            if handle == nil { running = nil; failedFor = req.film; report("3D: could not start the prepare step, staying 2D") }
        }
    }
}
// END relocated ThreeDPrepareLauncher.swift
// BEGIN relocated ThreeDPrepareSpawn.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// 190t A: the in-app prepare path that replaces the Python driver on the Mac. E-G's native runner (CoreML depth, shot detection, alignment) implements
/// `ShotPrepareRunner`; it must call `ShotSink.boundary(checkpoint:cancelled:)` at every frame boundary and wrap each model request in `runModel` (s19); it calls `ShotSink` per shot, and the sink owns every file the renderer reads: 199h D2 (DISK-LAW) removed the source proxy; the depth
/// container (depth_shot_NNNNN.dzc, CONTRACT s16, E-G's DZCWriter; a depth file counts only once complete), the depth_shot_NNNNN.json sidecar, progress.json, render-ready.json (CONTRACT-190v s8) and current-film.json. The runner must
/// supply the cache entry directory and key itself: cache_key is Python-only today. Not compiled or run on a Mac.
protocol ShotPrepareRunner: AnyObject {
    /// Blocking. Call `cancelled()` between shots/frames; throw to fail (the launcher then does not retry this film in a loop).
    func prepare(_ request: ThreeDPrepareLauncher.Request, cancelled: @escaping () -> Bool) throws
}

enum ThreeDRunnerRegistry { static var runner: ShotPrepareRunner? }       // E-G sets this once its runner exists

enum ThreeDPrepareSpawn {
    private final class Flag {
        private let condition=NSCondition();private var cancelled=false,paused=false
        var set:Bool {
            get {condition.lock();defer {condition.unlock()};while paused && !cancelled {condition.wait()};return cancelled}
            set {condition.lock();cancelled=newValue;condition.broadcast();condition.unlock()}
        }
        func pause(_ value:Bool) {condition.lock();paused=value;condition.broadcast();condition.unlock()}
    }


    /// The `spawn` closure for ThreeDPrepareLauncher; nil while no runner is registered (the launcher then reports "no prepare runtime").
    static func make(runner: ShotPrepareRunner?) -> ((ThreeDPrepareLauncher.Request, @escaping (Bool) -> Void) -> ThreeDPrepareLauncher.Handle?)? {
        guard let runner else { return nil }
        #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate)
        if let native = runner as? NativePrepareRunner { return PrepareWorker.spawn(kit: native.kitDir, cache: native.cacheRoot, models: native.modelsDir) }
        #endif
        return { req, done in
            let cancel = Flag()
            DispatchQueue.global(qos: .utility).async {
                var ok = true
                do { try runner.prepare(req, cancelled: { cancel.set }) } catch { ok = false }
                done(ok && !cancel.set)
            }
            return ThreeDPrepareLauncher.Handle(stop: { cancel.set = true },pause:{cancel.pause(true)},resume:{cancel.pause(false)})
        }
    }
}

/// Whole-prepare subprocess: model state never enters the app; existing cache files are the IPC.
/// Worker alone owns writes/checkpoints under a cache-root flock. Parent only reads them.
enum PrepareWorker {
    static let flag = "--gor-prepare-worker"
    typealias Job = PrepareWorkerJob   // 195h Delivery: the worker boundary contract lives in PrepareWorkerJob.swift (pure Foundation, compiled by production AND the Linux test driver)
    final class Child {
        private let lock = NSLock()
        private var process: Process?, cancelled = false, pauseRequested = false
        /// arch-196b C3: the cooperative-pause flag path (job-file sibling), set by spawn before the job is written.
        var pauseFlag: String?
        func install(_ p: Process) -> Bool { lock.lock(); defer { lock.unlock() }; if cancelled { return false }; process = p; return true }
        func stop() {
            lock.lock(); cancelled = true; let p = process, flag = pauseFlag; lock.unlock()
            #if canImport(Darwin)
            if let p, p.isRunning { PrepareProcessLifetime.stopDescendants(of:p.processIdentifier); kill(-p.processIdentifier, SIGKILL); kill(p.processIdentifier, SIGKILL) }
            #endif
            if let flag { try? FileManager.default.removeItem(atPath: flag) }
        }
        /// arch-196b C3: cooperative pause, never a signal. The flag file is the whole IPC: the worker polls it at the per-frame
        /// boundary (ShotSink.boundary) and waits there with no in-flight model call; removing it resumes. Works before run() too,
        /// and a worker or model-load-probe child is never frozen mid-call (the Neural Engine stall this replaces).
        func paused(_ value:Bool) {
            lock.lock();pauseRequested=value;let flag=pauseFlag;lock.unlock()
            guard let flag else { return }
            if value { try? Data().write(to: URL(fileURLWithPath: flag), options: .atomic) } else { try? FileManager.default.removeItem(atPath: flag) }
        }
        func applyPendingPause() {lock.lock();let value=pauseRequested;lock.unlock();if value {paused(true)}}
        var stopped: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }
    static func spawn(kit: URL, cache: URL, models: URL?) -> ThreeDPrepareLauncher.Spawn {
        return { req, done in
            guard let exe = Bundle.main.executableURL else { return nil }
            let child = Child()
            DispatchQueue.global(qos: .utility).async {
                PrepareProcessLifetime.reapOrphanedHelpers(executable:exe)
                let fm = FileManager.default
                do {try fm.createDirectory(at:cache,withIntermediateDirectories:true);try DepthCacheBudget.reapLegacyInputs(root:cache,source:req.film);try ShotGenerationStore.reapAbandoned(root:cache)}
                catch {DepthCacheBudget.recordFailure(.unsafe,root:cache);print("3d-prepare-worker reaper_error=\(error)");fflush(stdout);done(false);return}
                let jobURL = fm.temporaryDirectory.appendingPathComponent("gor-prepare-" + UUID().uuidString + ".json")
                let pauseURL = jobURL.appendingPathExtension("pause")
                child.pauseFlag = pauseURL.path
                defer { try? fm.removeItem(at: jobURL); try? fm.removeItem(at: pauseURL) }
                let job = Job(film: req.film.path, fps: req.fps, frames: req.nFrames, start: req.startPTS, quality: req.quality, kit: kit.path, cache: cache.path, models: models?.path, experiments: req.experiments, pauseFlag: pauseURL.path)   // 195h: the mode identity crosses the process boundary with the job; C3: so does the cooperative-pause flag path
                do {
                    try JSONEncoder().encode(job).write(to: jobURL, options: .atomic)
                    let p = Process(); p.executableURL = exe; p.arguments = [flag, jobURL.path, PrepareProcessLifetime.ownerFlag, String(ProcessInfo.processInfo.processIdentifier)]
                    p.standardInput = FileHandle.nullDevice
                    p.standardOutput = FileHandle.standardOutput; p.standardError = FileHandle.standardError
                    guard child.install(p), !child.stopped else { done(false); return }
                    try p.run()
                    #if canImport(Darwin)
                    _ = setpgid(p.processIdentifier, p.processIdentifier)
                    #endif
                    if child.stopped { child.stop() } else {child.applyPendingPause()}
                    let deadline = Date().addingTimeInterval(6 * 3600) // total worker ceiling, never an app wait
                    while p.isRunning && !child.stopped && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
                    if p.isRunning { child.stop() }
                    let reap = Date().addingTimeInterval(2)
                    while p.isRunning && Date() < reap { Thread.sleep(forTimeInterval: 0.01) }
                    if !p.isRunning {
                        p.waitUntilExit()
                        do {try DepthCacheBudget.reapLegacyInputs(root:cache,source:req.film);try ShotGenerationStore.reapAbandoned(root:cache)}
                        catch {DepthCacheBudget.recordFailure(.unsafe,root:cache);print("3d-prepare-worker reaper_error=\(error)");fflush(stdout);done(false);return}
                    }
                    let ok = !p.isRunning && !child.stopped && p.terminationReason == .exit && p.terminationStatus == 0
                    print("3d-prepare-worker end outcome=\(ok ? "complete" : "failed_or_cancelled")"); fflush(stdout)
                    done(ok)
                } catch { print("3d-prepare-worker spawn_error=\(error)"); fflush(stdout); done(false) }
            }
            return ThreeDPrepareLauncher.Handle(stop: { child.stop() },pause:{child.paused(true)},resume:{child.paused(false)})
        }
    }
    static func cli(arguments: [String]) -> Int32? {
        guard let at = arguments.firstIndex(of: flag) else { return nil }
        #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate) && canImport(Darwin)
        _ = setpgid(0, 0) // own group; parent cancellation kills model-probe descendants too
        PrepareProcessLifetime.watchOwner(arguments: arguments)
        guard arguments.count == at + 2 || arguments.count == at + 4,
              let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[at + 1])),
              let job = try? JSONDecoder().decode(Job.self, from: data), job.fps > 0, job.frames > 0 else { return 64 }
        let root = URL(fileURLWithPath: job.cache, isDirectory: true)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch { return 2 }
        do {try DepthCacheBudget.reapLegacyInputs(root:root,source:URL(fileURLWithPath:job.film));try ShotGenerationStore.reapAbandoned(root:root)}
        catch {print("3d-prepare-worker reaper_error=\(error)");fflush(stdout);return 2}
        let fd = open(root.appendingPathComponent(".prepare-worker.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { return 2 }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { print("3d-prepare-worker busy cache_owner_exists"); fflush(stdout); return 75 }
        defer { flock(fd, LOCK_UN) }
        ThreeDStageLog.enabled = true; ThreeDStageLog.start(); defer { ThreeDStageLog.stop() }
        let runner = NativePrepareRunner(kitDir: URL(fileURLWithPath: job.kit), cacheRoot: root)
        runner.modelsDir = job.models.map { URL(fileURLWithPath: $0) }
        if !job.pauseFlag.isEmpty { runner.pauseRequested = { FileManager.default.fileExists(atPath: job.pauseFlag) } }   // C3: cooperative pause, checked at every frame boundary
        do { try runner.prepare(job.request, cancelled: { false }); return DepthCacheBudget.failure(root:root) == nil ? 0 : 2 }
        catch { if let failure=error as? DepthCacheBudget.Failure {DepthCacheBudget.recordFailure(failure,root:root)}; print("3d-prepare-worker error=\(error)"); fflush(stdout); return 2 }
        #else
        return 4
        #endif
    }
}

/// Everything the runner needs to publish a shot. One per film. Not thread-safe: call from the runner's single prepare thread.
final class ShotSink {
    let entry: URL, fps: Double, shots: [[Int]]
    private var failures: [Int: String] = [:]
    /// CONTRACT s19: one model at a time (VDA stream and MoGe keyframes never overlap) and the thermal duty cycle.
    let thermal = ThreeDThermalGate()
    private static let modelLane = NSLock()

    init?(entry: URL, shots: [[Int]], fps: Double) {
        guard fps > 0, !shots.isEmpty, (try? FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)) != nil else { return nil }
        self.entry = entry; self.fps = fps; self.shots = shots
        writeReady()
    }

    /// Runs one model request (a VDA frame or a MoGe keyframe) on the single model lane: never two at once.
    func runModel<T>(_ body: () throws -> T) rethrows -> T { Self.modelLane.lock(); defer { Self.modelLane.unlock() }; return try body() }

    /// arch-196b C3: the cooperative-pause flag, set by the prepare worker's runner. Checked at every frame boundary; default = never paused.
    var pauseRequested: () -> Bool = { false }

    /// Call at EVERY frame boundary (and before each shot) from the prepare thread. Blocks while the machine is hot (thermalState >= .serious): `checkpoint` runs once
    /// on the way in (VDA WindowState + the .dzc resume prefix) and progress.json carries "paused": "thermal" meanwhile. false = cancelled, stop the film.
    /// arch-196b C3: while the cooperative-pause flag is set the worker waits HERE, at the boundary with no in-flight model call
    /// (the app never SIGSTOPs it). `checkpoint` runs once on the way in, so the persisted GORCK003 state is current if the
    /// 30 s pause limit cancels the worker: the next job resumes exactly. progress.json carries "paused": "pause" meanwhile.
    func boundary(checkpoint: () -> Void, cancelled: () -> Bool) -> Bool {
        if pauseRequested() {
            checkpoint()
            setUserPaused(true)
            while pauseRequested() {
                if cancelled() { setUserPaused(false); return false }
                Thread.sleep(forTimeInterval: 0.2)
            }
            setUserPaused(false)
        }
        return thermal.boundary(checkpoint: checkpoint, paused: { [self] p in setPaused(p) }, cancelled: cancelled)
    }

    private func setUserPaused(_ p: Bool) {
        let pj = entry.appendingPathComponent("progress.json")
        var d = ((try? Data(contentsOf: pj)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        if p { d["paused"] = "pause" } else { d.removeValue(forKey: "paused") }
        ThreeDStageLog.progress(p ? "prepare-pause" : "prepare-resumed", done: 0, total: 1)
        Self.writeAtomic(d, to: pj)
    }

    private func setPaused(_ p: Bool) {
        let pj = entry.appendingPathComponent("progress.json")
        var d = ((try? Data(contentsOf: pj)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        if p { d["paused"] = "thermal" } else { d.removeValue(forKey: "paused") }
        ThreeDStageLog.progress(p ? "thermal-pause" : "thermal-resumed", done: ProcessInfo.processInfo.thermalState.rawValue, total: 3)
        Self.writeAtomic(d, to: pj)
    }

    static func depthURL(_ e: URL, _ i: Int) -> URL { e.appendingPathComponent(String(format: "depth_shot_%05d.dzc", i)) }
    /// 199h D2: legacy proxy name, cleanup/reap only; nothing produces or reads this file any more.
    static func sourceURL(_ e: URL, _ i: Int) -> URL { e.appendingPathComponent(String(format: "source_shot_%05d.mp4", i)) }
    static func sidecarURL(_ e: URL, _ i: Int) -> URL { e.appendingPathComponent(String(format: "depth_shot_%05d.json", i)) }

    static func writeAtomic(_ obj: Any, to url: URL) {
        guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return }
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".tmp-" + url.lastPathComponent)
        do { try DepthCacheIO.write(d,to:url) } catch { try? FileManager.default.removeItem(at: tmp) }
    }

    /// Pure: the render-ready.json document (CONTRACT s8) from which files exist and which shots failed.
    /// Explicit local-v2 publication is not admitted by filename presence.
    enum ReadyTimeline {case legacyFilmPTS, localV2}
    static func readyDocument(shots: [[Int]], existing: Set<String>, failures: [Int: String], now: Double, timeline: ReadyTimeline = .legacyFilmPTS) -> [String: Any] {
        let legacy:Bool
        switch timeline {case .legacyFilmPTS:legacy=true;case .localV2:legacy=false}
        var rows: [[String: Any]] = []
        for (i, r) in shots.enumerated() {
            let d = legacy && existing.contains(String(format: "depth_shot_%05d.dzc", i))   // 199h D2 (DISK-LAW): depth-only readiness; no source proxy exists
            let err = failures[i]; let errV: Any = (d ? nil : err) ?? NSNull()
            rows.append(["shot": i, "start": r[0], "end": r[1], "depth_ready": d, "ready": d,
                         "failed": err != nil && !d, "error": errV])
        }
        return ["shots": rows, "n_shots": shots.count, "n_ready": rows.filter { $0["ready"] as? Bool == true }.count,
                "n_failed": rows.filter { $0["failed"] as? Bool == true }.count, "updated_at": now]
    }
    /// Pure: merge a [first,last] frame range into progress.json's "prepared" list (sorted, adjacent/overlapping ranges joined).
    static func merge(_ ranges: [[Int]], adding r: [Int]) -> [[Int]] {
        var out: [[Int]] = []
        for x in (ranges + [r]).sorted(by: { $0[0] < $1[0] }) {
            if let l = out.last, x[0] <= l[1] + 1 { out[out.count - 1][1] = max(l[1], x[1]) } else { out.append(x) }
        }
        return out
    }

    private func writeReady() {
        let names = Set(((try? FileManager.default.contentsOfDirectory(atPath: entry.path)) ?? []).filter { !$0.hasSuffix(".dzc") || DZCFile.isComplete(entry.appendingPathComponent($0)) })   // a half-written container is not ready
        Self.writeAtomic(Self.readyDocument(shots: shots, existing: names, failures: failures, now: Date().timeIntervalSince1970), to: entry.appendingPathComponent("render-ready.json"))
    }

    /// Points <cache_root>/current-film.json at this film (the key comes from the runner).
    func writeCurrentFilm(root: URL = DepthCachePaths.root, key: String, nFrames: Int) {
        Self.writeAtomic(["progress_path": entry.appendingPathComponent("progress.json").path, "n_frames": nFrames, "cache_key": key], to: root.appendingPathComponent("current-film.json"))
    }

    #if canImport(AVFoundation) && canImport(CoreVideo) && canImport(VideoToolbox)
    /// 199h D2 (DISK-LAW): publishes a depth-complete shot. Writes the geometry sidecar first (a ready shot always has its sidecar),
    /// merges the shot into progress.json and refreshes render-ready.json. No source proxy is written anywhere.
    @discardableResult
    func finishShot(shot i: Int, depthSize: (w: Int, h: Int), sourceSize: (w: Int, h: Int), extra: [String: Any] = [:]) -> Bool {
        var side = extra
        side["start"] = shots[i][0]; side["end"] = shots[i][1]
        side["depth_width"] = depthSize.w; side["depth_height"] = depthSize.h
        side["source_width"] = sourceSize.w; side["source_height"] = sourceSize.h
        Self.writeAtomic(side, to: Self.sidecarURL(entry, i))      // before ready: a ready shot always has its sidecar
        failures.removeValue(forKey: i)
        let pj = entry.appendingPathComponent("progress.json")
        let cur = ((try? Data(contentsOf: pj)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["prepared"] as? [[Int]]) ?? []
        var pd = (try? Data(contentsOf: pj)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        pd["prepared"] = Self.merge(cur, adding: [shots[i][0], shots[i][1]]); Self.writeAtomic(pd, to: pj)
        writeReady(); return true
    }
    #endif

    /// Records a failed shot (its depth file and any legacy source proxy are removed so the shot is never half-ready); the runner may retry it later.
    func fail(shot i: Int, _ error: String) {
        failures[i] = error
        try? FileManager.default.removeItem(at: Self.depthURL(entry, i)); try? FileManager.default.removeItem(at: Self.sourceURL(entry, i))
        writeReady()
    }
}
// END relocated ThreeDPrepareSpawn.swift
// BEGIN relocated ShotPrepareAssembly.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// 190t/190v native prepare, per-shot assembly (contract s13/s16/s19). Pure Foundation: runs and is tested on Linux with fake model backends; the real CoreML
/// backend adapter is at the bottom (parse-checked only, UNVERIFIED on a Mac).
///
/// Flow per shot (mirrors prepare_film._analyze_shot): phase 1 walks the frames in order, ONE MODEL AT A TIME (VDA-S stream step, then, on every FOV_KEYFRAME_STRIDE-th
/// frame, the MoGe-2 keyframe; never concurrent: s19 rule 1). The raw relative depth of every frame is spooled to disk, the keyframe fov and the (VDA, MoGe)
/// alignment sample pairs are kept. Phase 2 fits the per-shot scale/shift (ShotAlignerSwift, EMA over the keyframes in order), converts the spool to metres and
/// writes the lossless .dzc. The alignment is shot-global (as in Python), so the container cannot be written before phase 1 ends: the spool is what makes phase 1
/// resumable. After every frame the thermal hook may suspend the shot with a serialisable checkpoint (s19 rules 2-4); resuming recomputes nothing.

/// ProcessInfo.ThermalState without the platform dependency in the policy code.
enum ThermalLevel: Int, Comparable { case nominal = 0, fair, serious, critical
    static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
    #if canImport(Darwin)
    static func current() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .serious
        }
    }
    #endif
}

/// s19 duty cycle: suspend when state >= .fair; resume only after the minimum suspend (60 s) AND state < .fair held for the 30 s dwell. Time is injected.
struct ThermalDutyGate {
    static let minSuspend = 60.0, dwell = 30.0
    private(set) var suspendedAt: Double? = nil, coolSince: Double? = nil
    var isSuspended: Bool { suspendedAt != nil }
    /// Call at every frame boundary (running) or on the delivery lane's resume poll (suspended). true = may run.
    mutating func mayRun(level: ThermalLevel, now: Double) -> Bool {
        if let at = suspendedAt {
            if level >= .fair { coolSince = nil; return false }
            if coolSince == nil { coolSince = now }
            if now - at >= Self.minSuspend, now - coolSince! >= Self.dwell { suspendedAt = nil; coolSince = nil; return true }
            return false
        }
        if level >= .fair { suspendedAt = now; coolSince = nil; return false }
        return true
    }
}

protocol ShotPrepareBackend: AnyObject {
    /// Next VDA-S stream step for `frame` (frames are requested strictly in order from the checkpoint's nextFrame). Relative depth [depthH * depthW].
    func vdaStep(frame: Int) -> [Float]?
    /// The VDA sliding window, for checkpoint/restore.
    var window: VDAWindowState { get set }
    /// MoGe-2 keyframe at `frame` (fp32 fallback inside), or nil when no plausible result.
    func mogeKeyframe(frame: Int) -> MoGeKeyframe?
    /// s35: mean-RGB luma (depth resolution, depthW * depthH) of the frame the LAST vdaStep consumed; nil = no guards (the default, and every test fake).
    func guardLuma() -> [Float]?
}
extension ShotPrepareBackend { func guardLuma() -> [Float]? { nil } }

struct ShotCheckpoint: Equatable {
    var shot: Int, nextFrame: Int, nFrames: Int
    var window: [[[Float]]] = []; var windowID = -1
    var pairsVDA: [[Float]] = [], pairsMoGe: [[Float]] = []
    var fovFrames: [Int] = [], fovValues: [Double] = []
    var pairFrames: [Int] = []          // s30: shot-relative frame of each alignment pair (keyframes whose MoGe step succeeded), for the align track
    var keyframesTried = 0
    var pairWeights: [[Float]] = []     // s35 (GORCK003): per pair, texture weights on the same subsampled grid as pairsVDA ([] = none)
    var pairSky: [[UInt32]] = []        // s35 (GORCK003): per pair, packed sky-candidate bits at depth resolution ([] = no sky guard for that keyframe)

    // Binary (little-endian) so a 32-bundle window (~33 MB) is not text-expanded.
    func encode() -> Data {
        var d = Data("GORCK003".utf8)
        func i(_ v: Int) { var x = Int64(v).littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } }
        func f(_ a: [Float]) { i(a.count); a.withUnsafeBufferPointer { p in for v in p { var b = v.bitPattern.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } } } }
        func dbl(_ v: Double) { var b = v.bitPattern.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
        i(shot); i(nextFrame); i(nFrames); i(windowID); i(keyframesTried)
        i(window.count); for b in window { i(b.count); for a in b { f(a) } }
        i(pairsVDA.count); for a in pairsVDA { f(a) }; i(pairsMoGe.count); for a in pairsMoGe { f(a) }
        i(fovFrames.count); for v in fovFrames { i(v) }; i(fovValues.count); for v in fovValues { dbl(v) }
        i(pairFrames.count); for v in pairFrames { i(v) }
        i(pairWeights.count); for a in pairWeights { f(a) }
        i(pairSky.count); for a in pairSky { i(a.count); for v in a { var x = v.littleEndian; withUnsafeBytes(of: &x) { d.append(contentsOf: $0) } } }
        return d
    }
    static func decode(_ data: Data) -> ShotCheckpoint? {
        let b = [UInt8](data); var o = 0
        let magic = b.count >= 8 ? Array(b[0..<8]) : []
        guard magic == Array("GORCK003".utf8) || magic == Array("GORCK002".utf8) || magic == Array("GORCK001".utf8) else { return nil }
        let v3 = magic == Array("GORCK003".utf8), v2 = v3 || magic == Array("GORCK002".utf8)          // 001 (pre-s30) has no pairFrames: derived below as index * keyframe stride
        o = 8; var bad = false
        func raw(_ n: Int) -> UInt64 { guard !bad, o + n <= b.count else { bad = true; return 0 }; var v: UInt64 = 0; for k in 0..<n { v |= UInt64(b[o + k]) << (8 * UInt64(k)) }; o += n; return v }
        func i() -> Int { Int(Int64(bitPattern: raw(8))) }
        func cnt() -> Int { let n = i(); if n < 0 || n > b.count { bad = true; return 0 }; return n }
        func f() -> [Float] { let n = cnt(); var a = [Float](); a.reserveCapacity(n); for _ in 0..<n { a.append(Float(bitPattern: UInt32(raw(4)))) }; return a }
        var c = ShotCheckpoint(shot: i(), nextFrame: i(), nFrames: i())
        c.windowID = i(); c.keyframesTried = i()
        for _ in 0..<cnt() { var bundle: [[Float]] = []; for _ in 0..<cnt() { bundle.append(f()) }; c.window.append(bundle) }
        for _ in 0..<cnt() { c.pairsVDA.append(f()) }; for _ in 0..<cnt() { c.pairsMoGe.append(f()) }
        for _ in 0..<cnt() { c.fovFrames.append(i()) }; for _ in 0..<cnt() { c.fovValues.append(Double(bitPattern: raw(8))) }
        if v2 { for _ in 0..<cnt() { c.pairFrames.append(i()) } } else { c.pairFrames = (0..<c.pairsVDA.count).map { $0 * FovTrackBuilder.keyframeStride } }
        if v3 {
            for _ in 0..<cnt() { c.pairWeights.append(f()) }
            for _ in 0..<cnt() { var a: [UInt32] = []; for _ in 0..<cnt() { a.append(UInt32(truncatingIfNeeded: raw(4))) }; c.pairSky.append(a) }
        }
        return bad ? nil : c
    }
}

struct ShotPrepareJob {
    var shot: Int, startFrame: Int, frames: Int, fps: Double
    var depthW = VDAStream.exportW, depthH = VDAStream.exportH
    var dzc: URL, spool: URL
    var codec: DZCWriter.Codec = DZCWriter.lzfse
    /// 195h B/r3: the frozen experiment snapshot for this job (default all-off = pre-195h bytes). The menu toggle can only change the NEXT job.
    var experiments = ThreeDExperimentOptions()
    var alignSubsample = 8
    /// Where the boundary checkpoint is persisted (atomic replace); nil = in-memory suspension only. A process restart resumes from it with `runResumable`.
    var checkpointURL: URL? = nil
}

struct ShotPrepareResult { var dzc: URL; var fov: FovTrackBuilder.Entry; var alignScale: Double?; var alignShift: Double?; var alignSkipped: Int; var keyframesUsed: Int; var alignTrack: [[Double]] = [] }   // s30: [[k, scale, shift]]
enum ShotPrepareOutcome { case done(ShotPrepareResult), suspended(ShotCheckpoint), cancelled, failed(String) }

/// The delivery lane's ShotSink contract (ThreeDPrepareSpawn.swift): `boundary` is called before the shot and at EVERY frame boundary; it may block while the machine is hot,
/// running `checkpoint` once on the way in, and returns false when cancelled. `lane` wraps every model request (ShotSink.runModel: one model at a time).
struct ShotPrepareHooks {
    var boundary: (_ checkpoint: () -> Void) -> Bool = { _ in true }
    var lane: (() -> Void) -> Void = { $0() }
    var shouldSuspend: (Int) -> Bool = { _ in false }       // return-style suspension (tests, schedulers that re-enter)
    var stage: (String, Double) -> Void = { _, _ in }       // (stage name, milliseconds): self-test telemetry
    var progress: (String, Int, Int) -> Void = { _, _, _ in }
    var depthMetres: ([Float]) -> Void = { _ in }           // each aligned metric frame, before it is quantised (self-test depth stats)
}

enum ShotPrepare {
    /// MoGe metric depth (mw x mh, +inf at masked pixels) sampled on the VDA grid's every `step`-th pixel: bilinear at the pixel centre, NaN when any of the four
    /// neighbours is not finite (an inf must not enter the fit). Same indices as align.update(depth_rel[::8, ::8], md[::8, ::8]).
    static func sampleSub(_ src: [Float], mw: Int, mh: Int, dw: Int, dh: Int, step: Int) -> [Float] {
        var out: [Float] = []
        for y in stride(from: 0, to: dh, by: step) { for x in stride(from: 0, to: dw, by: step) {
            let fx = min(max((Double(x) + 0.5) / Double(dw) * Double(mw) - 0.5, 0), Double(mw - 1)), fy = min(max((Double(y) + 0.5) / Double(dh) * Double(mh) - 0.5, 0), Double(mh - 1))
            let x0 = Int(fx), y0 = Int(fy), x1 = min(x0 + 1, mw - 1), y1 = min(y0 + 1, mh - 1), tx = Float(fx - Double(x0)), ty = Float(fy - Double(y0))
            let a = src[y0 * mw + x0], b = src[y0 * mw + x1], c = src[y1 * mw + x0], d = src[y1 * mw + x1]
            guard a.isFinite, b.isFinite, c.isFinite, d.isFinite else { out.append(.nan); continue }
            out.append((a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty)
        } }
        return out
    }
    static func subsample(_ v: [Float], w: Int, h: Int, step: Int) -> [Float] {
        var out: [Float] = []; for y in stride(from: 0, to: h, by: step) { for x in stride(from: 0, to: w, by: step) { out.append(v[y * w + x]) } }; return out
    }
    static func rawBytes(_ a: [Float]) -> Data { a.withUnsafeBufferPointer { Data(buffer: $0) } }

    /// Runs (or resumes from `checkpoint`) one shot. `shouldSuspend(frame)` is called after each finished phase-1 frame (the thermal hook: typically
    /// `!gate.mayRun(level: ThermalLevel.current(), now: ...)`); true returns .suspended with the checkpoint to pass back later. Phase 2 (CPU + LZFSE) is not suspended.
    /// Resumes from job.checkpointURL when one is present and matches the job, otherwise starts the shot.
    static func runResumable(job: ShotPrepareJob, backend: ShotPrepareBackend, hooks: ShotPrepareHooks = ShotPrepareHooks(), reuseContext:ShotPrepareReuseContext = .deliveredLegacy) -> ShotPrepareOutcome {
        do {try reuseContext.requireLegacyCheckpointResume()}
        catch {return .failed("local-v2 checkpoint generation admission required")}
        // 195h A (Delivery A-3, fixed at the right point): the mode fence runs BEFORE any checkpoint or spool is read. A container written
        // in another mode makes every per-shot artifact of that mode stale; deleting them after phase 1 would be too late (an open fd keeps
        // reading the unlinked spool). Wipe container + mode marker + EMA state + spool + checkpoint here, then decide resume from scratch.
        let fm = FileManager.default
        if PrepareSupport.containerAction(dzc: job.dzc, options: job.experiments) == .rebuild {
            var stale = [job.dzc, job.dzc.appendingPathExtension("options.json"), job.dzc.appendingPathExtension("ema.json"), job.spool,
                         PrepareSupport.spoolIdentityURL(spool: job.spool), PrepareSupport.alignURL(spool: job.spool)]
            if let cku = job.checkpointURL { stale.append(cku) }
            for u in stale where fm.fileExists(atPath: u.path) {
                do { try fm.removeItem(at: u) } catch { return .failed("cannot remove \(u.lastPathComponent) for rebuild") }   // abort; never proceed on a partial wipe
            }
        } else if !fm.fileExists(atPath: job.dzc.path), PrepareSupport.spoolAction(spool: job.spool, checkpoint: job.checkpointURL, options: job.experiments) == .rebuild {
            // 195h A (Delivery A-4): phase 1 was interrupted before the container existed, so the container fence above saw nothing. The
            // spool/checkpoint on disk carry the identity marker written before THEIR phase 1; a mismatch never resumes across modes.
            var stale = [job.spool, PrepareSupport.spoolIdentityURL(spool: job.spool), PrepareSupport.alignURL(spool: job.spool)]
            if let cku = job.checkpointURL { stale.append(cku) }
            for u in stale where fm.fileExists(atPath: u.path) {
                do { try fm.removeItem(at: u) } catch { return .failed("cannot remove \(u.lastPathComponent) for rebuild") }
            }
        }
        // Record THIS job's identity before phase 1 writes a byte, so an interrupted run is recognized by the next job in any mode.
        guard PrepareSupport.writeJSON(PrepareSupport.prepareIdentity(job.experiments), to: PrepareSupport.spoolIdentityURL(spool: job.spool)) else { return .failed("cannot write the prepare identity marker") }
        var ck: ShotCheckpoint? = nil
        if let u = job.checkpointURL, let d = try? Data(contentsOf: u), let c = ShotCheckpoint.decode(d), c.shot == job.shot, c.nFrames == job.frames { ck = c }
        return run(job: job, backend: backend, checkpoint: ck, hooks: hooks)
    }
    private static func persist(_ ck: ShotCheckpoint, job: ShotPrepareJob, backend: ShotPrepareBackend, spool: FileHandle?) {
        guard let u = job.checkpointURL else { return }
        var c = ck; c.windowID = backend.window.id; c.window = backend.window.list
        try? spool?.synchronize()                               // the spool prefix is part of the checkpoint
        let tmp = u.deletingLastPathComponent().appendingPathComponent(".tmp-" + u.lastPathComponent)
        guard (try? DepthCacheIO.write(c.encode(),to:tmp,atomic:false)) != nil else { return }
        try? FileManager.default.removeItem(at: u); try? FileManager.default.moveItem(at: tmp, to: u)      // rename; a crash between the two leaves .tmp-, never a torn file
    }

    static func run(job: ShotPrepareJob, backend: ShotPrepareBackend, checkpoint: ShotCheckpoint? = nil, hooks: ShotPrepareHooks = ShotPrepareHooks()) -> ShotPrepareOutcome {
        let fm = FileManager.default, n = job.frames, plane = job.depthW * job.depthH, frameBytes = plane * 4
        var ck = checkpoint ?? ShotCheckpoint(shot: job.shot, nextFrame: 0, nFrames: n)
        guard ck.shot == job.shot, ck.nFrames == n, ck.nextFrame >= 0, ck.nextFrame <= n else { return .failed("checkpoint does not match the job") }
        if checkpoint != nil { var w = backend.window; w.restore(id: ck.windowID, list: ck.window); backend.window = w }
        // spool: keep exactly the finished frames (a crash may have left a partial or extra frame)
        if checkpoint == nil || !fm.fileExists(atPath: job.spool.path) {
            if checkpoint != nil && ck.nextFrame > 0 { return .failed("spool missing for checkpoint") }
            guard (try? DepthCacheIO.write(Data(),to:job.spool,atomic:false)) != nil else { return .failed("cannot create spool") }
        }
        guard let h = try? FileHandle(forUpdating: job.spool) else { return .failed("cannot open spool") }
        defer { try? h.close() }
        do {
            let size = try h.seekToEnd(); guard size >= UInt64(ck.nextFrame * frameBytes) else { return .failed("spool shorter than checkpoint") }
            try h.truncate(atOffset: UInt64(ck.nextFrame * frameBytes)); try h.seekToEnd()
        } catch { return .failed("spool I/O") }

        let stride_ = FovTrackBuilder.keyframeStride
        var overlay: DepthGuards.OverlayAccumulator? = nil          // s35: not checkpointed (a resumed shot accumulates from its resume point; needs >= 24 frames to act)
        hooks.progress("depth-boundary", ck.nextFrame, n)
        if !hooks.boundary({ persist(ck, job: job, backend: backend, spool: h) }) { return .cancelled }          // before the shot
        while ck.nextFrame < n {
            let k = ck.nextFrame
            hooks.progress("depth-frames", k, n)
            var vdaOut: [Float]? = nil; let tV = DispatchTime.now(); hooks.lane { vdaOut = backend.vdaStep(frame: k) }; hooks.stage("vda_step_total", Double(DispatchTime.now().uptimeNanoseconds - tV.uptimeNanoseconds) / 1e6)
            hooks.progress("depth-frames", k + 1, n)
            guard let d = vdaOut, d.count == plane else { return .failed("VDA step failed at frame \(k)") }
            do { try DepthCacheIO.append(rawBytes(d),to:h,url:job.spool) } catch { return .failed("spool write at frame \(k)") }
            let lum: [Float]? = { guard let l = backend.guardLuma(), l.count == plane else { return nil }; return l }()
            if let l = lum, DepthGuards.overlayFlatten { if overlay == nil { overlay = DepthGuards.OverlayAccumulator(w: job.depthW, h: job.depthH) }; overlay!.add(luma: l) }
            if k % stride_ == 0 {                                  // serial: the VDA step above has returned before MoGe starts
                hooks.progress("moge-keyframes", k / stride_, (n + stride_ - 1) / stride_)
                ck.keyframesTried += 1
                var kfOut: MoGeKeyframe? = nil; let tM = DispatchTime.now(); hooks.lane { kfOut = backend.mogeKeyframe(frame: k) }; hooks.stage("moge_step_total", Double(DispatchTime.now().uptimeNanoseconds - tM.uptimeNanoseconds) / 1e6)
                hooks.progress("moge-keyframes", k / stride_ + 1, (n + stride_ - 1) / stride_)
                if let kf = kfOut {
                    if kf.hfovDeg.isFinite { ck.fovFrames.append(k); ck.fovValues.append(kf.hfovDeg) }
                    ck.pairFrames.append(k); ck.pairsVDA.append(subsample(d, w: job.depthW, h: job.depthH, step: job.alignSubsample))
                    ck.pairsMoGe.append(sampleSub(kf.depth, mw: kf.width, mh: kf.height, dw: job.depthW, dh: job.depthH, step: job.alignSubsample))
                    var wts: [Float] = [], sky: [UInt32] = []                // s35: texture weights for the fit; MoGe-invalid + flat top-region candidates for the sky clamp
                    if let l = lum {
                        if DepthGuards.weightedFit { wts = subsample(DepthGuards.textureWeights(luma: l, w: job.depthW, h: job.depthH), w: job.depthW, h: job.depthH, step: job.alignSubsample) }
                        if DepthGuards.skyClamp {
                            let fin = DepthGuards.finiteMask(kf.depth, mw: kf.width, mh: kf.height, dw: job.depthW, dh: job.depthH)
                            if fin.contains(false) { let m = DepthGuards.skyMaskMoGe(luma: l, finite: fin, w: job.depthW, h: job.depthH); if m.reduce(0, { $0 + ($1 ? 1 : 0) }) >= 64 { sky = DepthGuards.pack(m) } }
                        }
                    }
                    ck.pairWeights.append(wts); ck.pairSky.append(sky)
                }
            }
            ck.nextFrame = k + 1
            if ck.nextFrame < n {
                if !hooks.boundary({ persist(ck, job: job, backend: backend, spool: h) }) { return .cancelled }        // every frame boundary
                if hooks.shouldSuspend(k) { ck.windowID = backend.window.id; ck.window = backend.window.list; return .suspended(ck) }
            }
        }
        try? h.synchronize()
        // (the spool + container prefix below are recoverable; the phase-1 checkpoint stays valid until the shot is finished)
        if let u = job.checkpointURL { var c = ck; c.windowID = backend.window.id; c.window = backend.window.list; try? DepthCacheIO.write(c.encode(),to:u) }

        // phase 2: shot-global alignment, metres, lossless container (resumable through the DZC prefix)
        let al = ShotAlignerSwift(ema: 0.9); let tA = DispatchTime.now()
        var trackRaw: [(k: Int, scale: Double?, shift: Double?)] = []
        let overlayMask: [Bool]? = DepthGuards.overlayFlatten ? overlay?.mask(minFrames: 24) : nil
        var fitMask: [Bool]? = nil          // s35: overlay pixels do not enter the fit (same grid as the pairs)
        if let om = overlayMask { var s: [Bool] = []; for y in Swift.stride(from: 0, to: job.depthH, by: job.alignSubsample) { for x in Swift.stride(from: 0, to: job.depthW, by: job.alignSubsample) { s.append(!om[y * job.depthW + x]) } }; fitMask = s }
        for (idx, (v, m)) in zip(ck.pairsVDA, ck.pairsMoGe).enumerated() {
            let wt: [Float]? = idx < ck.pairWeights.count && ck.pairWeights[idx].count == v.count ? ck.pairWeights[idx] : nil
            al.update(vda: v, moge: m, mask: fitMask, weights: wt)
            trackRaw.append((idx < ck.pairFrames.count ? ck.pairFrames[idx] : idx * stride_, al.scale, al.shift))
        }
        // s30: eased per-keyframe application (nil entries -> the shot's final EMA, as prepare_film passes default=(scale, shift))
        let track = AlignTrack(keyframes: trackRaw, defaultScale: al.scale ?? 1.0, defaultShift: al.shift ?? 0.0)
        hooks.stage("align_fit", Double(DispatchTime.now().uptimeNanoseconds - tA.uptimeNanoseconds) / 1e6)
        // s35 sky clamp: the nearest keyframe's MoGe-invalid candidates (first keyframe on a tie, like min() over the sorted keyframes in the probe harness)
        func nearestPair(_ f: Int) -> Int? { var best: Int? = nil, bd = Int.max; for (i, k) in ck.pairFrames.enumerated() where abs(k - f) < bd { bd = abs(k - f); best = i }; return best }
        func skyClamped(_ z: [Float], frame f: Int) -> [Float] {
            guard DepthGuards.skyClamp, let i = nearestPair(f), i < ck.pairSky.count, !ck.pairSky[i].isEmpty else { return z }
            return DepthGuards.clampSkyMetres(z: z, mask: DepthGuards.unpack(ck.pairSky[i], count: plane))
        }
        func aligned(_ raw: [Float], _ fi: Int) -> [Float] { track.entries.isEmpty ? al.apply(raw) : track.apply(raw, frame: fi, defaultScale: al.scale ?? 1.0, defaultShift: al.shift ?? 0.0) }
        var zScreen: Float? = nil
        if overlayMask != nil {                  // convergence plane of this shot: median metres over every keyframe-stride-th frame (the render lane re-derives its own from the container)
            var sample: [[Float]] = []
            do { for fi in Swift.stride(from: 0, to: n, by: stride_) { try h.seek(toOffset: UInt64(fi * frameBytes)); guard let data = try h.read(upToCount: frameBytes), data.count == frameBytes else { break }
                sample.append(skyClamped(aligned(data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }, fi), frame: fi)) } } catch {}
            if let zc = ShotComfort.median(sample) { zScreen = Float(zc) }
        }
        let q = DZC.quantise(z: [Float](repeating: 1, count: plane), h: job.depthH, w: job.depthW)
        let meta = DZC.Meta(shot: UInt32(job.shot), fpsNum: DZC.fpsPair(job.fps).0, fpsDen: DZC.fpsPair(job.fps).1, startFrame: UInt64(job.startFrame),
                            width: UInt32(q.width), height: UInt32(q.height), depthWidth: UInt32(job.depthW), depthHeight: UInt32(job.depthH), nFrames: UInt32(n))
        // 195h r3-2: the container action is decided BEFORE the writer opens, from the per-container mode marker. A mismatched existing
        // container is never resumed: it is removed and rebuilt in this job's mode, and only then marked.
        let expOptions = job.experiments
        var rangeEMA = DepthTemporalEMA.State(active: expOptions.depthRangeEMA)   // 195h B: one state per prepare job = the shot-boundary reset
        let modeMarker = job.dzc.appendingPathExtension("options.json"), emaStateURL = job.dzc.appendingPathExtension("ema.json")
        if PrepareSupport.containerAction(dzc: job.dzc, options: expOptions) == .rebuild {
            do { try fm.removeItem(at: job.dzc) } catch { return .failed("cannot remove the mismatched container for rebuild") }   // Delivery 6: abort; never proceed or mark when the removal failed
            if fm.fileExists(atPath: emaStateURL.path) { do { try fm.removeItem(at: emaStateURL) } catch { return .failed("cannot remove the stale EMA state for rebuild") } }
        }
        guard let w = DZCWriter(url: job.dzc, meta: meta, resume: true, codec: job.codec) else { return .failed("cannot open container") }
        _ = PrepareSupport.writeJSON(PrepareSupport.prepareIdentity(expOptions), to: modeMarker)   // marked only once the writer's container is this job's mode (195h A: model + smoother)
        var prevOut: [Float]? = nil          // F2b: previous output frame of this shot (recursive smoothing); a resumed shot primes it from the previous spooled frame (approximate, no seam beyond the EMA tail)
        do {
            try h.seek(toOffset: UInt64(w.framesWritten * frameBytes))
            if w.framesWritten > 0, TemporalDepth.enabled || rangeEMA.active {
                let savedEMA: DepthTemporalEMA.State? = {   // 195h r3-3: an exact restore requires the container's frame count and restores primed as persisted
                    guard rangeEMA.active, let st = PrepareSupport.readJSON(emaStateURL), let lo = st["lo"] as? Double, let hi = st["hi"] as? Double,
                          let pr = st["primed"] as? Bool, (st["frames"] as? Int) == w.framesWritten else { return nil }
                    return DepthTemporalEMA.State(active: true, lo: Float(lo), hi: Float(hi), primed: pr)
                }()
                if rangeEMA.active, savedEMA == nil {
                    // 195h r3-3 + Delivery 7: no valid persisted state (a crash between append and persist, or a lost file) -> EXACT replay of the
                    // deterministic prefix from the spool (align + sky clamp + F2b smoothing + EMA, frame by frame), never an approximate re-prime.
                    for rfi in 0..<w.framesWritten {
                        try h.seek(toOffset: UInt64(rfi * frameBytes))
                        guard let rd = try h.read(upToCount: frameBytes), rd.count == frameBytes else { return .failed("spool short in the EMA replay") }
                        let rr: [Float] = rd.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                        var rm = skyClamped(aligned(rr, rfi), frame: rfi)
                        if let rp = prevOut { rm = TemporalDepth.smooth(prev: rp, cur: rm) }; prevOut = rm
                        _ = rangeEMA.apply(rm)
                    }
                } else {
                    try h.seek(toOffset: UInt64((w.framesWritten - 1) * frameBytes))
                    if let pd = try h.read(upToCount: frameBytes), pd.count == frameBytes {
                        let pf = skyClamped(aligned(pd.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }, w.framesWritten - 1), frame: w.framesWritten - 1)
                        if TemporalDepth.enabled { prevOut = pf }   // F2b's own single-frame prime (its documented approximate resume)
                        if let se = savedEMA { rangeEMA = se }
                    }
                }
                try h.seek(toOffset: UInt64(w.framesWritten * frameBytes))
            }
            for fi in w.framesWritten..<n {
                guard let data = try h.read(upToCount: frameBytes), data.count == frameBytes else { return .failed("spool short in phase 2") }
                let raw: [Float] = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
                let tD = DispatchTime.now(); var metres = skyClamped(aligned(raw, fi), frame: fi)
                if let po = prevOut { metres = TemporalDepth.smooth(prev: po, cur: metres) }; prevOut = metres          // F2b
                metres = rangeEMA.apply(metres)                                                    // 195h B depth-range EMA (default off: unchanged)
                if let om = overlayMask, let zs = zScreen { metres = DepthGuards.flattenOverlay(z: metres, mask: om, zScreen: zs) }
                hooks.depthMetres(metres)
                guard w.append(zMetres: metres) else { return .failed("container append failed") }
                if rangeEMA.active { _ = PrepareSupport.writeJSON(["lo": rangeEMA.lo, "hi": rangeEMA.hi, "primed": rangeEMA.primed, "frames": fi + 1], to: emaStateURL) }   // 195h r3-3: persisted only AFTER the append landed, with the container's new frame count
                hooks.stage("align_apply_dzc_append", Double(DispatchTime.now().uptimeNanoseconds - tD.uptimeNanoseconds) / 1e6)
                if !hooks.boundary({ w.synchronize() }) { return .cancelled }       // the container prefix is its own checkpoint (s16 resume)
            }
        } catch { return .failed("spool read in phase 2") }
        guard w.finish() else { return .failed("container finish failed") }
        try? fm.removeItem(at: job.spool); if let u = job.checkpointURL { try? fm.removeItem(at: u) }
        let fov = FovTrackBuilder.entry(startFrame: job.startFrame, endFrame: job.startFrame + n - 1, fps: job.fps,
                                        keyframes: zip(ck.fovFrames, ck.fovValues).map { (frame: $0.0, fov: $0.1) })
        return .done(ShotPrepareResult(dzc: job.dzc, fov: fov, alignScale: al.scale, alignShift: al.shift, alignSkipped: al.skipped, keyframesUsed: ck.pairsVDA.count, alignTrack: track.json))
    }
}

extension VDAWindowState {
    mutating func restore(id: Int, list: [[[Float]]]) { self.setState(id: id, list: list) }
}

#if canImport(CoreML)
/// Real backend: one VDAStreamRunner + one MoGeKeyframeRunner, frames from the caller (decoded source frames: `vdaChw` 154x266 bicubic-resized and normalised, `mogeRGBA`
/// resized to the picked shape). Both models share this single object, so they can never overlap. UNVERIFIED on a Mac.
final class NativeShotBackend: ShotPrepareBackend {
    private let vda: VDAStreamRunner, moge: MoGeKeyframeRunner
    private let vdaInput: (Int) -> [Float]?, mogeInput: (Int) -> (rgba: [UInt8], shape: MoGeInput.Shape)?
    init(vda: VDAStreamRunner, moge: MoGeKeyframeRunner, vdaInput: @escaping (Int) -> [Float]?, mogeInput: @escaping (Int) -> (rgba: [UInt8], shape: MoGeInput.Shape)?) {
        self.vda = vda; self.moge = moge; self.vdaInput = vdaInput; self.mogeInput = mogeInput
    }
    var window: VDAWindowState { get { vda.window } set { vda.window = newValue } }
    var stage: (String, Double) -> Void = { _, _ in }       // self-test: "input_prep" (decode + resize + CHW), "vda_model", "moge_model"
    private func ms(_ t: DispatchTime) -> Double { Double(DispatchTime.now().uptimeNanoseconds - t.uptimeNanoseconds) / 1e6 }
    /// s22: when set, the stream canvas is letterboxed (the vdaInput closure does that) and the output is cropped to the picture area before anything else sees it.
    var crop: VDAStream.Box?
    var lumaSource: () -> [Float]? = { nil }
    func guardLuma() -> [Float]? { lumaSource() }
    func vdaStep(frame: Int) -> [Float]? {
        let t = DispatchTime.now(); guard let c = vdaInput(frame) else { return nil }; stage("input_prep", ms(t))
        let m = DispatchTime.now(); defer { stage("vda_model", ms(m)) }
        guard let d = vda.process(chw: c) else { return nil }
        return crop.map { VDAStream.cropDepth(d, box: $0) } ?? d
    }
    func mogeKeyframe(frame: Int) -> MoGeKeyframe? {
        let t = DispatchTime.now(); guard let i = mogeInput(frame) else { return nil }; stage("input_prep", ms(t))
        let m = DispatchTime.now(); defer { stage("moge_model", ms(m)) }; return moge.run(rgba: i.rgba, shape: i.shape)
    }
}
#endif

#if canImport(Darwin)
extension ShotPrepareHooks {
    /// Binds a film's ShotSink (delivery lane, ThreeDPrepareSpawn.swift): its thermal-aware boundary and its single model lane. UNVERIFIED on a Mac.
    static func sink(_ sink: ShotSink, cancelled: @escaping () -> Bool) -> ShotPrepareHooks {
        var h = ShotPrepareHooks()
        h.boundary = { cp in sink.boundary(checkpoint: cp, cancelled: cancelled) }
        h.lane = { body in sink.runModel { body() } }
        return h
    }
}
#endif
// END relocated ShotPrepareAssembly.swift
// BEGIN relocated ThreeDSelfTest.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// One-shot 3D self-test (Main 09:04): after an update, with 3D enabled, prepares a short synthetic clip through the real NativePrepareRunner and the real RenderShotWriter
/// and writes the numbers to the gor log as `gor3d-selftest` lines (PrepareTelemetry format), so the log zip the owner already sends carries real measurements.
/// No owner step. The pure policy (when to run, the marker) is tested on Linux; the clip, the run and the render are parse-only (no Mac).
enum ThreeDSelfTest {
    /// The fixture's storage pixels are not its prepared display geometry (ToS has SAR120:89).
    /// Read the same committed sidecar contract as the playback render coordinator.
    struct PreparedGeometry {
        let source: (w: Int, h: Int), depth: (w: Int, h: Int)
        init?(sidecar: [String: Any]) {
            guard let sw = sidecar["source_width"] as? Int, let sh = sidecar["source_height"] as? Int,
                  let dw = sidecar["depth_width"] as? Int, let dh = sidecar["depth_height"] as? Int,
                  sw > 0, sh > 0, dw > 0, dh > 0 else { return nil }
            source = (sw, sh); depth = (dw, dh)
        }
    }
    /// The render cache writer is insert-only. Acceptance is a repeatable named
    /// report: render privately, then atomically replace only our two MP4 outputs.
    static func acceptanceRender(work: URL, evidence: URL, name: String, render: (URL) throws -> Void) throws -> URL {
        guard ["sbs", "vr180"].contains(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        let staged = work.appendingPathComponent("acceptance-" + UUID().uuidString + ".mp4")
        defer { try? FileManager.default.removeItem(at: staged) }
        try render(staged)
        let bytes = try Data(contentsOf: staged)
        guard !bytes.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let published = evidence.appendingPathComponent(name + ".mp4")
        try bytes.write(to: published, options: .atomic)
        return published
    }
    /// Runs once per (kit manifest, build): the marker file records the attempt even when it fails, so a crashing model cannot loop on every launch.
    static func markerName(manifestSha: String, build: String) -> String {
        let safe = build.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" ? Character($0) : "_" }
        return "selftest-\(manifestSha.prefix(12))-\(String(safe)).done"
    }
    static func shouldRun(enabled: Bool, kitPresent: Bool, markerExists: Bool, filmPreparing: Bool) -> Bool { enabled && kitPresent && !markerExists && !filmPreparing }
    /// The installer already runs --selftest3d in its own process. Interactive
    /// playback must not also start a model/render/telemetry workload by default.
    static func interactiveRequested(_ environment: [String: String]) -> Bool { environment["GOR_3D_INTERACTIVE_SELFTEST"] == "1" }
    /// Synthetic clip geometry: 16:9 so the 518x294 MoGe package is picked; 36 frames = three keyframes at stride 12.
    static let clipW = 640, clipH = 360, clipFrames = 36, clipFPS = 24.0
    /// Longest the synthetic clip writer may stall before the self-test logs it and gives up (seconds).
    static let writerStallLimit: TimeInterval = 30
    /// Pure test pattern: luma-ish gradient plus a moving block, BGRA. Deterministic so the depth stats are comparable between runs.
    static func pattern(frame k: Int, w: Int = clipW, h: Int = clipH) -> [UInt8] {
        var px = [UInt8](repeating: 255, count: w * h * 4)
        let bx = (k * 7) % (w - 96), by = h / 3
        for y in 0..<h { for x in 0..<w {
            let o = (y * w + x) * 4
            var r = UInt8(x * 255 / (w - 1)), g = UInt8(y * 255 / (h - 1)), b = UInt8(((x + y + k * 3) / 4) % 256)
            if x >= bx && x < bx + 96 && y >= by && y < by + 96 { r = 220; g = 40; b = 40 }
            px[o] = b; px[o + 1] = g; px[o + 2] = r
        } }
        return px
    }
}

#if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate) && canImport(Metal)
import AVFoundation
import CoreVideo
import Metal
import ImageIO

extension ThreeDSelfTest {
    /// Writes the synthetic clip (H.264, BGRA frames). nil on any writer failure (the reason goes to `telemetry`).
    static func writeClip(to url: URL, telemetry: PrepareTelemetry) -> Bool {
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { telemetry.error("clip: cannot create writer"); return false }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: clipW, AVVideoHeightKey: clipH])
        let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: clipW, kCVPixelBufferHeightKey as String: clipH])
        guard w.canAdd(input) else { telemetry.error("clip: cannot add input"); return false }
        w.add(input); guard w.startWriting() else { telemetry.error("clip: startWriting failed: \(String(describing: w.error))"); return false }
        w.startSession(atSourceTime: .zero)
        for k in 0..<clipFrames {
            // Bounded: a writer whose encoder never drains (no GUI session for VideoToolbox, say) used to spin here forever at 0% cpu (owner Mac 16:33: etime 12:58, pcpu 0.0, rss 39 MB).
            let waitStart = Date()
            while !input.isReadyForMoreMediaData {
                if Date().timeIntervalSince(waitStart) > writerStallLimit { telemetry.error("clip: writer not ready for frame \(k) after \(Int(writerStallLimit)) s (status \(w.status.rawValue), error \(String(describing: w.error)))"); w.cancelWriting(); return false }
                Thread.sleep(forTimeInterval: 0.002)
            }
            var pb: CVPixelBuffer?
            guard let pool = ad.pixelBufferPool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb) == kCVReturnSuccess, let b = pb else { telemetry.error("clip: no pixel buffer"); return false }
            CVPixelBufferLockBaseAddress(b, [])
            if let base = CVPixelBufferGetBaseAddress(b) {
                let src = pattern(frame: k), bpr = CVPixelBufferGetBytesPerRow(b)
                for y in 0..<clipH { src.withUnsafeBytes { memcpy(base.advanced(by: y * bpr), $0.baseAddress! + y * clipW * 4, clipW * 4) } }
            }
            CVPixelBufferUnlockBaseAddress(b, [])
            guard ad.append(b, withPresentationTime: CMTime(value: CMTimeValue(k), timescale: CMTimeScale(clipFPS))) else { telemetry.error("clip: append failed at \(k): \(String(describing: w.error))"); return false }
        }
        input.markAsFinished()
        let g = DispatchGroup(); g.enter(); w.finishWriting { g.leave() }
        if g.wait(timeout: .now() + writerStallLimit) == .timedOut { telemetry.error("clip: finishWriting did not return in \(Int(writerStallLimit)) s (status \(w.status.rawValue), error \(String(describing: w.error)))"); return false }
        if w.status != .completed { telemetry.error("clip: finish failed: \(String(describing: w.error))"); return false }
        return true
    }

    /// SHA-256 of the first frame (BGRA bytes) of a video file: the "first rendered 3D frame hash". Same machine and encoder => comparable between runs; not a cross-machine pin.
    static func firstFrameHash(_ url: URL) -> String? {
        let a = AVURLAsset(url: url)
        guard let t = a.tracks(withMediaType: .video).first, let r = try? AVAssetReader(asset: a) else { return nil }
        let o = AVAssetReaderTrackOutput(track: t, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        guard r.canAdd(o) else { return nil }
        r.add(o); guard r.startReading(), let s = o.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(s) else { return nil }
        CVPixelBufferLockBaseAddress(pb, .readOnly); defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        var hasher = SHA256Pure.Hasher()
        for y in 0..<h { hasher.update([UInt8](UnsafeBufferPointer(start: base.advanced(by: y * bpr).assumingMemoryBound(to: UInt8.self), count: w * 4))) }
        r.cancelReading(); return hasher.hex()
    }

    /// Durable, decoded first-frame evidence (not merely a file-exists or encoded-byte claim).
    static func saveFrame(_ video: URL, png: URL) -> Bool {
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: video)); gen.appliesPreferredTrackTransform = true
        guard let image = try? gen.copyCGImage(at: .zero, actualTime: nil),
              let dest = CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    static func thermalObserver(_ t: PrepareTelemetry) -> NSObjectProtocol {
        t.thermalSample(level: ThermalLevel.current().rawValue)
        return NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in t.thermalSample(level: ThermalLevel.current().rawValue) }
    }

    /// Blocking; call on a background queue. Emits the log lines with `emit` (default: stdout, which the app pipes into the gor log). Never throws; every failure is a logged line.
    /// `marker` is written first (an attempt counts even if the process dies mid-run). The test film lives in a temp cache root and is removed afterwards.
    @discardableResult
    static func run(runner: NativePrepareRunner, kitDir: URL, modelsDir: URL, build: String, marker: URL, emit: ([String]) -> Void = { $0.forEach { print($0) }; fflush(stdout) }) -> PrepareTelemetry {
        let tel = PrepareTelemetry()
        try? FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("started".utf8).write(to: marker)
        let obs = thermalObserver(tel); defer { NotificationCenter.default.removeObserver(obs) }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("gor3d-selftest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let host = ProcessInfo.processInfo
        tel.note("build", build); tel.note("os", host.operatingSystemVersionString); tel.note("cpus", "\(host.activeProcessorCount)"); tel.note("mem_gb", "\(host.physicalMemory >> 30)")
        tel.note("kit_manifest_sha", KitCompiledCache.manifestSha(kitDir: kitDir) ?? "missing")
        tel.note("clip", "320x180 48f @24 Tears of Steel CC-BY-3.0 source_sha256=b7eaa61e065d9682e5d3bc2ceae3c79f46a799e792260419dffd38b10bc49956")
        let film = work.appendingPathComponent("selftest.mp4"), cache = work.appendingPathComponent("cache", isDirectory: true)
        let env = ProcessInfo.processInfo.environment
        let fixturePath = env["GOR_3D_TEST_CLIP"] ?? Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("tools/depth_analysis/kit/x2_tos_reference/tos_input_320x180_48f.mp4").path
        let fixture: URL? = URL(fileURLWithPath: fixturePath)
        guard let fixture, let bytes = try? Data(contentsOf: fixture), bytes.count == 63977 else { tel.error("acceptance: original ToS fixture missing or wrong size"); emit(tel.lines(header: "3D self-test FAILED")); return tel }
        var inputHash = SHA256Pure.Hasher(); inputHash.update([UInt8](bytes))
        guard inputHash.hex() == "b7eaa61e065d9682e5d3bc2ceae3c79f46a799e792260419dffd38b10bc49956" else { tel.error("acceptance: original ToS SHA256 mismatch"); emit(tel.lines(header: "3D self-test FAILED")); return tel }
        do { try tel.time("clip_write") { try FileManager.default.copyItem(at: fixture, to: film) } } catch { tel.error("acceptance: cannot stage ToS input"); return tel }
        let evidence = env["GOR_3D_TEST_EVIDENCE"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? modelsDir.appendingPathComponent("selftest-evidence", isDirectory: true)
        do { try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true) } catch { tel.error("acceptance: cannot create evidence directory"); return tel }
        let testW = 320, testH = 180, testFrames = 48
        let test = NativePrepareRunner(kitDir: kitDir, cacheRoot: cache); test.modelsDir = modelsDir; test.telemetry = tel
        let req = ThreeDPrepareLauncher.Request(film: film, fps: clipFPS, nFrames: testFrames, startPTS: 0, quality: "selftest")
        var prepared = false
        tel.time("prepare_total") {
            do { try ThreeDStageLog.time("prepare (cuts, depth, moge)") { try test.prepare(req, cancelled: { false }) }; prepared = true } catch { tel.error("prepare: \(error)") }
        }
        // models: precision actually used, and the compute plan per package
        if let m = test.moge { tel.note("moge_precision", "fp16_used=\(m.fp16Used) fp16_rejected=\(m.fp16Rejected) fp32_used=\(m.fp32Used)") }
        // 195h A (item 5): when the DAV2 experiment is selected, the self-test also runs the pinned CoreML package on fixture frames and
        // reports its ms/frame line. Skipped silently otherwise; a missing package is a note, never a failure of the default self-test.
        if DepthModelID.selected() == .dav2_small_coreml {
            if let r = CoreMLDepthRunner(modelsDir: modelsDir), let fr = NativePrepareRunner.FrameReader(url: film, fps: clipFPS, format: kCVPixelFormatType_32BGRA) {
                var fs: [CVPixelBuffer] = []; for k in 0..<8 { if let pb = fr.frame(k, last: 47) { fs.append(pb) } }
                fr.close()
                tel.note("dav2_selftest", r.selfTest(frames: fs) ?? "dav2_small_coreml self-test: no frame succeeded")
            } else { tel.note("dav2_selftest", "dav2_small_coreml package not installed (tools/gor-fetch-models.sh); skipped") }
        }
        tel.note("compute_plan", "see bounded per-package load/device stage lines; no second model load for telemetry")
        var acceptanceComplete = false
        // render: the real RenderShotWriter over the prepared shot 0
        if prepared, let entry = (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil))?.first(where: { $0.hasDirectoryPath }) {
            let depth = ShotSink.depthURL(entry, 0)
            // 199h D2: the render source is the original film; shot 0's frame range comes from cuts.json.
            guard let shot0 = ((try? Data(contentsOf: entry.appendingPathComponent("cuts.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["shots"] as? [[Int]])?.first, shot0.count == 2 else {
                tel.error("acceptance: cuts.json has no shot 0")
                emit(tel.lines(header: "3D self-test FAILED")); return tel
            }
            guard let data = try? Data(contentsOf: ShotSink.sidecarURL(entry, 0)),
                  let sidecar = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let geometry = PreparedGeometry(sidecar: sidecar) else {
                tel.error("acceptance: prepared shot sidecar geometry missing or invalid")
                emit(tel.lines(header: "3D self-test FAILED")); return tel
            }
            tel.note("prepared_geometry", "source_width=\(geometry.source.w) source_height=\(geometry.source.h) depth_width=\(geometry.depth.w) depth_height=\(geometry.depth.h)")
            let fovShot = ((try? Data(contentsOf: entry.appendingPathComponent("fov_track.json"))).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["shots"] as? [[String: Any]])?.first
            let hfov = (fovShot?["hfov_deg"] as? Double) ?? 60.0
            if fovShot?["hfov_deg"] as? Double == nil { tel.error("render: fov_track.json has no hfov for shot 0, using 60 deg") }
            let fov = entry.appendingPathComponent("fov_track.json")
            do { let data = try Data(contentsOf: fov); try data.write(to: evidence.appendingPathComponent("fov_track.json"), options: .atomic) }
            catch { tel.error("acceptance: FoV track could not be saved") }
            let fovFirstPTS = (((try? Data(contentsOf: fov)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["first_pts"] as? Double) ?? 0
            var grabs = [String: String]()
            for (name, mode) in [("sbs", OutputMode.fullSBS), ("vr180", OutputMode.vr180)] {
                let png = evidence.appendingPathComponent(name + ".png")
                var completed: URL? // A prior run's output must never count after a failed render.
                if let w = RenderShotWriter() {
                    let plan = RenderedShotPlan(eyeN: 256, codec: .hevc, swapEyes: true, output: mode, srcW: geometry.source.w, srcH: geometry.source.h)
                    tel.time("render_" + name) { ThreeDStageLog.time("render " + name) {
                        do { completed = try acceptanceRender(work: work, evidence: evidence, name: name) { staged in
                            _ = try w.write(film: film, startFrame: shot0[0], endFrame: shot0[1], fps: clipFPS, firstPTS: fovFirstPTS, depth: depth, depthSize: geometry.depth, sourceSize: geometry.source, thetaH: hfov * .pi / 180, plan: plan, ipd: 0.063, convergence: nil, out: staged)
                        } }
                        catch { tel.error("render " + name + ": \(error)") }
                    } }
                    if let out = completed, let hash = firstFrameHash(out), saveFrame(out, png: png) { grabs[name] = hash; tel.note("acceptance_" + name + "_frame_sha256", hash); if name == "vr180" { tel.note("first_3d_frame_sha256", hash) } }
                    else { tel.error("acceptance: missing decoded " + name + " frame grab") }
                } else { tel.error("render: no Metal renderer") }
            }
            tel.add("render_shot", ms: tel.stages.filter { $0.name == "render_sbs" || $0.name == "render_vr180" }.reduce(0) { $0 + $1.s.ms })
            let accepted = grabs.count == 2 && FileManager.default.fileExists(atPath: evidence.appendingPathComponent("fov_track.json").path) && tel.errors.isEmpty
            acceptanceComplete = accepted
            let manifest: [String: Any] = ["schema": 1, "build": build, "fixture_sha256": inputHash.hex(), "frames": testFrames, "width": testW, "height": testH,
                "frame_hashes": grabs, "verdict": accepted ? "PASS" : "FAIL", "stage_ms": Dictionary(uniqueKeysWithValues: tel.stages.map { ($0.name, $0.s.ms) })]
            if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]) { try? data.write(to: evidence.appendingPathComponent("acceptance.json"), options: .atomic) }
            tel.note("acceptance_evidence", evidence.path)
            tel.note("decoder_source", "original-film")
            ThreeDStageLog.time("realtime probe") { RealtimeProbe.run(tel: tel, sourceProxy: film, frames: testFrames) } // measured separately from failed/successful renders
        }
        if !acceptanceComplete { tel.error("acceptance: SBS/VR180 decoded grabs, FoV track and stage measurements are incomplete") }
        tel.addRealtimeBudget(frames: testFrames)
        tel.note("prepared", prepared ? "yes" : "no")
        try? Data((prepared && acceptanceComplete && tel.errors.isEmpty ? "done" : "failed").utf8).write(to: marker)
        emit(ThreeDDegrade.walkLines())          // s38/s39 item 12: the scripted degradation walk, verbatim 3dfsm lines
        emit(tel.lines(header: prepared ? "3D self-test finished" : "3D self-test FAILED"))
        return tel
    }
}
#endif
// END relocated ThreeDSelfTest.swift
// BEGIN relocated ThreeDSelfTestCLI.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// X1 (190x): headless entry for the first-Mac kit. `gor --selftest3d` runs the same ThreeDSelfTest the app runs after an update, but without
/// NSApplication, without a window and without needing 3D switched on in the UI, then exits. The kit installer redirects stdout into its log and
/// feeds that log to mac_log_check (the 13-family first-Mac checklist). Nothing here changes what the app does when it is launched normally.
/// Not compiled or run on a Mac yet; the pure parts (argument test, exit code, missing-kit line) are pinned on Linux by Tests/FirstMacKit.
enum ThreeDSelfTestCLI {
    static let flag = "--selftest3d"

    /// Printed by the installer when the headless run cannot start; says what the flag does and what it never does.
    static let usage = """
    gor --selftest3d
      Runs the 3D self-test headless: CoreML prepare of the pinned Tears of Steel 320x180 48-frame clip, SBS and VR180 renders,
      decoded PNG grabs, FoV track, stage milliseconds, thermal series and the degradation walk. Writes gor3d-selftest v1 lines to stdout.
      Exit 0 = pass, 2 = ran with errors, 3 = kit packages missing, 4 = platform has no CoreML/Metal.
      It opens no window, writes no once-per-build marker, changes no setting and does not touch the installed app.
      The kit packages are read from GOR_KIT_DIR or <models dir>/kit; they are never downloaded by this flag.
    """

    /// Pure: true when the process was started with the headless flag.
    static func requested(arguments: [String]) -> Bool { arguments.contains(flag) }

    /// Pure: exit status the kit installer reads. 0 = prepared and no errors, 2 = ran but failed or had errors, 3 = kit packages missing, 4 = no CoreML here.
    static func exitCode(kitMissing: [String], prepared: Bool, errors: Int) -> Int32 {
        if !kitMissing.isEmpty { return 3 }
        return prepared && errors == 0 ? 0 : 2
    }

    /// Pure: the one line written when the kit is incomplete, in the same family as the other self-test lines so the log checker reports it as MISSING.
    static func missingLine(_ m: [String]) -> String { "gor3d-selftest-cli v1 kit_missing " + m.joined(separator: ",") }

    /// Exit statuses, one place, so the installer's mapping and this file cannot drift apart (Tests/FirstMacKit pins the same table).
    static let exitMeanings: [Int32: String] = [
        0: "prepared, rendered, no errors",
        2: "ran, but the prepare failed or the log has error lines",
        3: "kit packages missing: nothing was run",
        4: "no CoreML/Metal/VideoToolbox on this platform: nothing was run",
    ]

    /// Pure: the closing line the installer greps for. A log without it was cut short (crash or kill) and counts as a failed run.
    static func endLine(code: Int32, errors: Int) -> String {
        "gor3d-selftest-cli v1 end code=\(code) errors=\(errors) meaning=" + (exitMeanings[code] ?? "unknown").replacingOccurrences(of: " ", with: "_")
    }

    /// Pure: a headless log is complete when it has exactly one begin line and a closing end line with the same run (the installer applies this in Python too).
    static func logIsComplete(_ lines: [String]) -> Bool {
        lines.filter { $0.hasPrefix("gor3d-selftest-cli v1 begin ") }.count == 1
            && (lines.last(where: { $0.hasPrefix("gor3d-selftest-cli v1 ") })?.hasPrefix("gor3d-selftest-cli v1 end ") ?? false)
    }

    /// Pure: header line with the build id and the kit directory, so the uploaded log says which tree and which kit it measured.
    static func beginLine(build: String, kit: String) -> String { "gor3d-selftest-cli v1 begin build=\(build) kit=\(kit)" }

    /// Blocking. Returns the process exit status; the caller exits with it.
    static func run() -> Int32 {
        #if canImport(AVFoundation) && canImport(CoreML) && canImport(VideoToolbox) && canImport(Accelerate) && canImport(Metal)
        let kit = ThreeDKit.dir, models = ThreeDModels.modelsDir
        let missing = ThreeDKit.missing(dir: kit)
        print(beginLine(build: BuildID.value(), kit: kit.path)); fflush(stdout)
        if !missing.isEmpty {
            let code = exitCode(kitMissing: missing, prepared: false, errors: 0)
            print(missingLine(missing)); print(endLine(code: code, errors: 0)); fflush(stdout)
            return code
        }
        ThreeDStageLog.enabled = true; ThreeDStageLog.start(); defer { ThreeDStageLog.stop() }
        let runner = NativePrepareRunner(kitDir: kit)
        runner.modelsDir = models
        try? FileManager.default.createDirectory(at:runner.cacheRoot,withIntermediateDirectories:true)
        guard let lane=PrepareProcessLifetime.acquireLane(root:runner.cacheRoot,cancelled:{false}) else { return 2 }
        defer { PrepareProcessLifetime.releaseLane(lane) }
        runner.externallyHeldModelLane=true
        // A throwaway marker: the headless run must not consume the app's once-per-build marker in <models>.
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("gor3d-selftest-cli-\(UUID().uuidString).marker")
        defer { try? FileManager.default.removeItem(at: marker) }
        let tel = ThreeDStageLog.time("self-test total") { ThreeDSelfTest.run(runner: runner, kitDir: kit, modelsDir: models, build: BuildID.value(), marker: marker) }
        let prepared = ((try? String(contentsOf: marker)) ?? "") == "done"
        let code = exitCode(kitMissing: [], prepared: prepared, errors: tel.errors.count)
        print(endLine(code: code, errors: tel.errors.count)); fflush(stdout)
        return code
        #else
        print("gor3d-selftest-cli v1 unsupported platform"); print(endLine(code: 4, errors: 0)); fflush(stdout)
        return 4
        #endif
    }
}
// END relocated ThreeDSelfTestCLI.swift
// BEGIN relocated ThreeDStageLog.swift (195y owner-order 3D consolidation, behavior unchanged)
import Foundation

/// Per-stage progress for `gor --selftest3d` (Main 16:33: a 12 min run left only the begin line, because the telemetry lines are emitted once at the very end).
/// Off in the normal app (no noise); the CLI turns it on. Every line is flushed at once, so the installer log shows where a long compile / ANE load is sitting:
///   gor3d-selftest-cli v1 stage <name> begin t=<s since start>
///   gor3d-selftest-cli v1 stage <name> end ms=<n> t=<s>
///   gor3d-selftest-cli v1 alive stage=<current> in_stage_s=<n> t=<s>      (heartbeat every `beat` seconds while a stage is open)
/// Pure Foundation: formatting and the stage stack are tested on Linux (Tests/ThreeDKit/stage_log_test.py); the model calls it wraps are Mac-only.
enum ThreeDStageLog {
    static var enabled = false
    static var beat: TimeInterval = 15
    static var sink: (String) -> Void = { print($0); fflush(stdout) }
    private static let lock = NSLock()
    private static var stack: [(name: String, start: Date)] = []
    private static var t0 = Date()
    private static var timer: DispatchSourceTimer?
    private static var work: (stage: String, done: Int, total: Int, scopeDepth: Int)?

    static func beginLine(_ name: String, t: Double) -> String { "gor3d-selftest-cli v1 stage \(name) begin t=\(String(format: "%.1f", t))" }
    static func endLine(_ name: String, ms: Double, t: Double) -> String { "gor3d-selftest-cli v1 stage \(name) end ms=\(Int(ms.rounded())) t=\(String(format: "%.1f", t))" }
    static func aliveLine(stage: String, inStage: Double, t: Double) -> String { "gor3d-selftest-cli v1 alive stage=\(stage) in_stage_s=\(Int(inStage)) t=\(String(format: "%.1f", t))" }

    static func progressLine(_ stage: String, done: Int, total: Int, t: Double) -> String {
        "gor3d-selftest-cli v1 progress stage=\(stage) done=\(done) total=\(total) t=\(String(format: "%.1f", t))"
    }
    /// Report before and after expensive work. Heartbeats repeat the most recent counter, distinguishing an in-flight model call from completed frames.
    static func progress(_ stage: String, done: Int, total: Int) {
        guard enabled else { return }
        lock.lock(); work = (stage, done, total, stack.count); let t = Date().timeIntervalSince(t0); lock.unlock()
        sink(progressLine(stage, done: done, total: total, t: t))
    }

    static func start() {
        guard enabled else { return }
        lock.lock(); t0 = Date(); stack = []; work = nil; lock.unlock()
        let q = DispatchQueue(label: "gor.3d.stagelog")
        let tm = DispatchSource.makeTimerSource(queue: q)
        tm.schedule(deadline: .now() + beat, repeating: beat)
        tm.setEventHandler {
            lock.lock(); let cur = stack.last; let current = work; let t = Date().timeIntervalSince(t0); lock.unlock()
            sink(aliveLine(stage: cur?.name ?? "between-stages", inStage: cur.map { Date().timeIntervalSince($0.start) } ?? 0, t: t))
            if let current { sink(progressLine(current.stage, done: current.done, total: current.total, t: t)) }
        }
        tm.resume(); timer = tm
    }
    static func stop() { timer?.cancel(); timer = nil }

    /// Runs `body` as a named stage: begin line, end line with the wall time, heartbeat while it runs. A plain call when logging is off.
    static func time<T>(_ name: String, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let s = Date()
        lock.lock(); stack.append((name, s)); let t = s.timeIntervalSince(t0); lock.unlock()
        sink(beginLine(name, t: t))
        defer {
            lock.lock(); _ = stack.popLast()
            if let current = work, current.scopeDepth > stack.count { work = nil }
            lock.unlock()
            sink(endLine(name, ms: Date().timeIntervalSince(s) * 1000, t: Date().timeIntervalSince(t0)))
        }
        return try body()
    }
    /// A finished stage reported by someone else (PrepareTelemetry stage timers): one end line, no heartbeat.
    static func done(_ name: String, ms: Double) { if enabled { sink(endLine(name, ms: ms, t: Date().timeIntervalSince(t0))) } }
}

/// Bounded caller wait. A timed-out OS call is NOT cancelled; its late result is discarded.
/// Device circuit breakers in KitCompiledCache stop later requests accumulating stuck loads.
final class BoundedLoadResult<T> {
    private let lock = NSLock()
    private var value: T?
    private var closed = false
    func publish(_ v: T?) { lock.lock(); defer { lock.unlock() }; if !closed { value = v } }
    func finish() -> T? { lock.lock(); defer { lock.unlock() }; closed = true; let v = value; value = nil; return v }
}
enum BoundedLoad {
    static func attempt<T>(seconds: Double, body: @escaping () -> T?) -> (value: T?, timedOut: Bool) {
        let box = BoundedLoadResult<T>(), sem = DispatchSemaphore(value: 0)
        DispatchQueue(label: "gor.coreml.load." + UUID().uuidString).async { box.publish(body()); sem.signal() }
        let timeout = sem.wait(timeout: .now() + seconds) != .success
        let value = box.finish()
        return (timeout ? nil : value, timeout)
    }
}
// END relocated ThreeDStageLog.swift
// BEGIN station-move CacheKeyMemo.swift
import Foundation

/// Owner log 14:37 (gor_sample.txt, main thread): ThreeDRenderCoordinator.tick() (1 s timer) spent 2059 of 2063 samples inside PrepareSupport.cacheKey (PrepareSupport.swift:55/56, two 1 MiB SHA256Pure hashes) EVERY tick,
/// because the relaunch check re-hashed the film while no cache existed yet. That pinned the main thread (photon-cost frame_drop_count 102..350 per 10 s window). This memo returns the key without touching the main thread:
/// a hit is an O(1) stat compare, a miss starts ONE background hash (utility) and returns nil; the next tick finds it. `hashRuns` counts real hashes (test).
enum CacheKeyMemo {
    private static let lock = NSLock()
    private static var memo: [String: (sig: String, key: String)] = [:]
    private static var inflight = Set<String>()
    private(set) static var hashRuns = 0
    private static func sig(_ path: String) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path), let size = (a[.size] as? NSNumber)?.int64Value, let t = a[.modificationDate] as? Date else { return nil }
        return "\(size):\(t.timeIntervalSinceReferenceDate)"
    }
    /// Memoised key (same value as PrepareSupport.cacheKey), nil while the first hash is still running or the file cannot be read.
    static func key(path: String, background: Bool = true) -> String? {
        guard let s = sig(path) else { return nil }
        lock.lock()
        if let m = memo[path], m.sig == s { lock.unlock(); return m.key }
        if inflight.contains(path) { lock.unlock(); return nil }
        inflight.insert(path); lock.unlock()
        let work: @Sendable () -> Void = {
            let k = PrepareSupport.cacheKey(path: path)
            lock.lock(); hashRuns += 1; inflight.remove(path); if let k = k { memo[path] = (s, k) }; lock.unlock()
        }
        if background { DispatchQueue.global(qos: .utility).async(execute: work); return nil }
        work(); lock.lock(); defer { lock.unlock() }; return memo[path]?.key
    }
}
// END station-move CacheKeyMemo.swift
