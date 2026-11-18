# W-gdb-199h-d5r3b-01 - RenderShotWriter film-frame map (r3: whole-loop proof)
state: OPEN / unclaimed
lab: shared stock (1nstinct + in2tinct; earliest claim wins, one holder)

arch-199h D2a (r3b, pinned to native50 872dcc32d). Current composition lands the typed film-frame map: RenderShotWriter.write takes originalMap:OriginalFilmShot and reads through NativePrepareRunner.FrameReader (excerpts below). Lane c reconciled: H0661 v3 carries no G0930 defect (the missing increment was a G0930 artifact only). Remaining: exact production extraction of the whole write loop and a whole-loop proof - index pairing (depth k with source s+k) and exact-rational PTS stamping across the FULL loop, not a prefix. 'verified-not-needed with evidence' is an accepted outcome.

Re-pin note: r3b moves the pin 35f553acd -> 872dcc32d; all excerpt bytes are identical to r3 at the recorded ranges (the only shift is +3 lines before the sess_replace excerpt, now carved at 1660-1720).

Required acceptance: Executed whole-loop evidence (pairing + rational PTS for every frame of a multi-shot fixture), or verified-not-needed with that same evidence.

Outcomes: a production change with executed semantic tests, or 'verified-not-needed with evidence' where this packet says so. The executed starter proof is a clean source-only materialization of exact pinned excerpts, not a full Swift package build. Full excerpts below are read-only input until this packet is claimed. Earliest claim wins across both labs; 2h lease expiry without holder commit. No product ref or billing changes. Return patch and exact logs, or the evidence document. Preserve all existing supported behavior. Native compile queues after Linux verification (through the D1 route); native/UI/runtime NOT_RUN unless actually executed. No licensed bytes, no credentials.

```packet-json
{
 "packet_id": "W-gdb-199h-d5r3b-01",
 "lab": "shared",
 "writer": "1nstinct or in2tinct (earliest claim wins)",
 "code_owner": "Claiming lab owns only the listed production files for this packet; integrator owns host wiring and move composition",
 "product_repo": "goreda/instinct",
 "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
 "touched_files": [
  {
   "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
   "excerpt_block": "writer_class (lines 7475-7545)"
  }
 ],
 "interface": {
  "signatures": "Current composition lands the typed film-frame map: RenderShotWriter.write takes originalMap:OriginalFilmShot and reads through NativePrepareRunner.FrameReader (excerpts below). Lane c reconciled: H06",
  "types": "Existing declarations in exact pinned excerpts below; retain public APIs",
  "ownership_lifetime": "One writer per listed source file; 2h lease expires without holder commit; no gor U2/S2 host edits beyond the listed files",
  "caller": "Executed whole-loop evidence (pairing + rational PTS for every frame of a multi-shot fixture), or verified-not-needed with that same evidence.",
  "callee": "archive/gor/Sources/gor/gor/ThreeD.swift"
 },
 "scope": "product",
 "test": {
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-01.py",
  "expected": "Baseline source-pin proof exit0 only. Acceptance additionally requires: Executed whole-loop evidence (pairing + rational PTS for every frame of a multi-shot fixture), or verified-not-needed with that same evidence.",
  "fixture_block": "fixtures1"
 },
 "target": {
  "branch": "lane/lab-<claiming-lab>-W-gdb-199h-d5r3b-01",
  "paths": [
   "archive/gor/Sources/gor/gor/ThreeD.swift",
   "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-01.py"
  ],
  "return_form": "patch"
 },
 "run_proof": {
  "version": 1,
  "product_repo": "goreda/instinct",
  "product_sha": "872dcc32d2394bdfa887f16d760399d0b39b4001",
  "command": "python3 archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-01.py",
  "system": "Linux",
  "clean_checkout": true,
  "ran_at": "2026-11-18T11:50:59.505071+00:00",
  "kind": "module",
  "expected_exit": 0,
  "exit_code": 0,
  "expected_log_contains": "BASELINE_SOURCE_PIN_PASS",
  "inline_files": [
   {
    "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
    "lines": "7475-7545",
    "block": "Sources/gor/gor/ThreeD.swift:7475-7545",
    "sha256": "b7266762367c21a3a75fdd744428d748472fe16f012c27ef0d67a8fc4d4ff7e6"
   },
   {
    "path": "archive/gor/Sources/gor/gor/ThreeD.swift",
    "lines": "5268-5352",
    "block": "Sources/gor/gor/ThreeD.swift:5268-5352",
    "sha256": "6f16e6f5cfc9cdb3c5d201c695810e305b865c8a9268705c44767cb115deca75"
   },
   {
    "path": "archive/gor/Tests/Architecture/199h-d5r3b/W-gdb-199h-d5r3b-01.py",
    "block": "fixtures1",
    "sha256": "a27f818a8c54303da3c274d2cee519b078adfff020ab4f79c6d1051947207b56"
   }
  ],
  "log_block": "actual_run_log",
  "log_sha256": "88282f728df9eba13a7a170dc218fb791ffd9efd952197e69fbcb609718fb4d2",
  "last_5_lines": [
   "BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-01; baseline only, product change and semantic test still required"
  ],
  "receipt_sha256": "979602af455f4216110bfefa2c1bf28d51ca42d7ecd0446ff3a94081adf5beb2"
 }
}
```

```swift id=Sources/gor/gor/ThreeD.swift:7475-7545
final class RenderShotWriter {
    enum Failure: Error { case open, size, depth, render, write, pairing }
    private let device: MTLDevice, renderer: Stereo3DRenderer

    init?(renderer: Stereo3DRenderer? = Stereo3DRenderer.make()) {
        guard let r = renderer, let d = MTLCreateSystemDefaultDevice() else { return nil }
        self.renderer = r; device = d
    }

    /// `depthSize`: sidecar depth_width/depth_height and `sourceSize`: source_width/source_height (both unpadded; nil = the buffer size).
    /// Both pictures are cropped (top-left blit, no resampling) to that size and must then agree. Returns the output URL; throws and deletes on failure.
    func write(source: URL, originalMap:OriginalFilmShot, depth: URL, depthSize: (w: Int, h: Int)?, sourceSize: (w: Int, h: Int)? = nil, thetaH: Double, plan: RenderedShotPlan, ipd: Double,
               convergence: Double?, zNear: Double? = nil, surround: Bool = true, options: ThreeDExperimentOptions = .live, out: URL, cancelled: @escaping () -> Bool = { false }) throws -> URL {
        // Encode privately. Never unlink a currently playing last-good file.
        let destination=out
        let out=out.deletingLastPathComponent().appendingPathComponent(".render-"+UUID().uuidString+".mp4")
        defer {try? FileManager.default.removeItem(at:out)}
        guard PrepareSupport.cacheKey(path:source.path)==originalMap.sourceKey,
              let depthFile=DZCFile(url:depth),originalMap.matches(depth:depthFile.meta),
              let facts=SourceFormatProbe.pipeFacts(url:source,cancelled:cancelled),SourceFormat.refuseReasons(facts).isEmpty else {throw Failure.open}
        var segment:ShotCopySegment?
        if source.pathExtension.lowercased()=="mkv" {
            do {segment=try ShotCopySegment.create(source:source,entry:depth.deletingLastPathComponent(),map:originalMap,sourceFirstPTS:facts.firstPTS,binary:GORResources.vendorPath("ffmpeg/bin/ffmpeg"),cancelled:cancelled)}
            catch ShotCopySegment.Failure.copyFailed {
                // MP4 cannot carry every MKV codec (e.g. FFV1). Preserve the
                // established original decode route; never encode a new proxy.
                print("3D source segment unavailable=stream-copy-mux; decoding original")
            }
        }
        guard let sourceReader=NativePrepareRunner.FrameReader(url:segment?.url ?? source,fps:Double(originalMap.timeline.fps.numerator)/Double(originalMap.timeline.fps.denominator),format:kCVPixelFormatType_32BGRA,facts:facts,inputSeek:segment == nil ? nil:0,cancelled:cancelled),
              let dr=DepthFrameReader(url:depth,device:device) else {throw Failure.open}
        defer {sourceReader.close();if let segment {try? segment.remove()}}
        let filmStart=originalMap.timeline.filmStart
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else { throw Failure.open }

        let n = plan.eyeN, w2 = plan.canvas.w, h2 = plan.canvas.h, flat = plan.output.isFlat
        guard let sbs = Stereo3DRenderer.texture(device, .rgba8Unorm, w2, h2),
              let movie=DepthBoundedMovie(url:out,start:CMTime(value:filmStart.value,timescale:filmStart.scale)) else {throw Failure.open}
        let writer=movie.writer
        defer {movie.cancel()}
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: plan.codec == .hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264, AVVideoWidthKey: w2, AVVideoHeightKey: h2,
            // review: with no compression properties AVAssetWriter picks its own (low) default bitrate for a 2x-wide canvas; same quality key the prepare encoder (VTShotEncoder) uses. UNCOMPILED on a Mac; real bitrate unmeasured.
            AVVideoCompressionPropertiesKey: [AVVideoQualityKey: 0.9]])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: w2, kCVPixelBufferHeightKey as String: h2])
        guard writer.canAdd(input) else { throw Failure.open }
        writer.add(input)
        guard writer.startWriting() else { throw Failure.write }
        guard let up = DepthUpsampler(device: device, queue: renderer.queue) else { throw Failure.open }
        var started = false, completedFrames = 0
        var firstOutputPTS=Double.nan,lastOutputPTS=Double.nan
        let totalFrames=Int(originalMap.timeline.frameCount)
        ThreeDStageLog.progress("stereo-synthesis-" + plan.output.rawValue, done: 0, total: totalFrames)
        func fail(_ f: Failure) -> Failure { sourceReader.close(); dr.cancel(); movie.cancel(); try? FileManager.default.removeItem(at: out); return f }

        for local in 0..<totalFrames {
            if cancelled() {throw fail(.write)}
            let filmFrame=try originalMap.originalFrame(local:Int64(local))
            guard let sp=sourceReader.frame(Int(filmFrame),last:Int(originalMap.firstFrame+originalMap.timeline.frameCount-1)),
                  let df=dr.next(),df.rangeOK else {throw fail(.depth)}
            let expected=try originalMap.filmPTS(local:Int64(local))
            let pts=CMTime(value:expected.value,timescale:expected.scale)
            // arch-199h: pair by exact original frame index, not container PTS.
            let dw = depthSize?.w ?? df.width, dh = depthSize?.h ?? df.height
            let fw = sourceSize?.w ?? CVPixelBufferGetWidth(sp), fh = sourceSize?.h ?? CVPixelBufferGetHeight(sp)
            // the depth box (sidecar depth_width x depth_height, the letterbox box the native prepare stores) may be smaller than the source picture: same aspect, resampled up below
            guard DepthUpsampleKernel.compatible(depth: (dw, dh), source: (fw, fh)), dw <= df.width, dh <= df.height, fw <= CVPixelBufferGetWidth(sp), fh <= CVPixelBufferGetHeight(sp) else { throw fail(.size) }
            var ft: CVMetalTexture?
```

```swift id=Sources/gor/gor/ThreeD.swift:5268-5352
    final class FrameReader {
        let fps:Double,format:OSType,facts:SourceFacts?,fallbackFormat:OSType?
        private let url:URL,source:SourceFacts,cancelled:()->Bool,inputSeek:Double?
        private var pipe:PrepareRawPipe?
        private var needsFirstFrame=true
        private(set) var nextFrame=0,last=0
        init?(url:URL,fps:Double,format:OSType,facts:SourceFacts?=nil,fallbackFormat:OSType?=nil,decodeFacts:SourceFacts?=nil,inputSeek:Double?=nil,cancelled:@escaping ()->Bool={false}) {
            guard let source=decodeFacts ?? facts ?? SourceFormatProbe.pipeFacts(url:url,cancelled:cancelled),fps.isFinite,fps>0,
                  abs(source.avgFps-fps)/fps<0.002 else {return nil}
            self.url=url;self.fps=fps;self.format=format;self.facts=facts;self.fallbackFormat=fallbackFormat;self.source=source;self.cancelled=cancelled;self.inputSeek=inputSeek
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
            guard let args=PrepareDecodeContract.arguments(source:url.path,first:first,last:last,fps:fps,startPTS:source.firstPTS,pixel:pixel,filters:filters,inputSeek:inputSeek),
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
```

```python id=fixtures1
from pathlib import Path
import hashlib, os, sys
sys.dont_write_bytecode = True
ROOT = Path(os.environ.get("PRODUCT_ROOT", Path(__file__).resolve().parents[3]))
CHECKS = [["Sources/gor/gor/ThreeD.swift", 7475, 7545, "b7266762367c21a3a75fdd744428d748472fe16f012c27ef0d67a8fc4d4ff7e6"], ["Sources/gor/gor/ThreeD.swift", 5268, 5352, "6f16e6f5cfc9cdb3c5d201c695810e305b865c8a9268705c44767cb115deca75"]]
bad = []
for rel, a, b, want in CHECKS:
    lines = (ROOT / rel).read_text().splitlines(keepends=True)
    data = "".join(lines[a-1:b]).encode()
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        bad.append((rel, a, b, got))
if bad:
    for rel, a, b, got in bad:
        print("PIN_MISMATCH " + rel + ":" + str(a) + "-" + str(b) + " got=" + got)
    sys.exit(1)
print("BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-01; baseline only, product change and semantic test still required")
```

```text id=actual_run_log
BASELINE_SOURCE_PIN_PASS W-gdb-199h-d5r3b-01; baseline only, product change and semantic test still required
```
