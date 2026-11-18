# W-gdb-199e-1nstinct-22 - Overflow-safe stereo evidence buffer admission
state: OPEN / unclaimed
lab: 1nstinct

SBSPairEvidence.match must validate dimension multiplication without trapping before comparing byte count. Invalid/overflowing dimensions return nil. Preserve normal minimum dimensions, even splits, NCC thresholds and classification behavior. This is a different production file and classifier from the earlier SBSEyeCrop packet.

Selected production declarations are extracted verbatim at runtime from the listed complete source. No algorithm rewrite or model is compiled. This is an isolated shipping-helper semantic proof, not the full AppKit module. Native/module integration remains NOT_RUN.

PATH-CONTRACT: top-level fixtures -> Tests/Fixtures; kits -> archive/kits. No directory moves, root-path cleanup, old packet source overlap or product/delivery-ref changes. One production source plus own tests. Test-only changes count0. English only. Missing compiler is77 NOT_RUN. Base for A is isolated S2 b603, not delivery; preserve later BuildID/launch-identity rebase changes. Native/UI/runtime and full provider build NOT_RUN.

```packet-json
{
  "packet_id": "W-gdb-199e-1nstinct-22",
  "lab": "1nstinct",
  "product_repo": "goreda/instinct",
  "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
  "scope": "product",
  "touched_files": [
    {
      "path": "archive/gor/Sources/gor/Stereo/StereoDetection.swift",
      "excerpt_block": "source1"
    }
  ],
  "interface": {
    "signatures": "SBSPairEvidence.match must validate dimension multiplication without trapping before comparing byte count. Invalid/overflowing dimensions return nil. Preserve normal minimum dimensions, even splits, NCC thresholds and classification behavior. This is a different production file and classifier from the earlier SBSEyeCrop packet.",
    "ownership_lifetime": "Only listed production source and own tests. Coordinator resolves lease claim; no host/shared/ref expansion.",
    "caller": "Existing shipping helper callers; no new feature/parity claim.",
    "callee": "archive/gor/Sources/gor/Stereo/StereoDetection.swift"
  },
  "test": {
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-22.py",
    "fixture_block": "fixtures1",
    "config_block": "fixtures2",
    "expected": "Imported baseline RED exit1 after successful actual Swift compilation. Acceptance requires production fix and green semantic regression, plus writer edge cases and native module validation."
  },
  "target": {
    "branch": "lane/lab-1nstinct-W-gdb-199e-1nstinct-22",
    "paths": [
      "archive/gor/Sources/gor/Stereo/StereoDetection.swift",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-22.py",
      "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-22.json"
    ],
    "return_form": "patch"
  },
  "run_proof": {
    "version": 1,
    "product_sha": "b60352dabc87fe8519832999b4af639f37d786f8",
    "command": "python3 archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-22.py",
    "system": "Swift6.0.3 Linux",
    "clean_checkout": false,
    "kind": "verbatim-selected-production-declarations",
    "expected_exit": 1,
    "exit_code": 1,
    "expected_log_contains": "compile_exit=0",
    "inline_files": [
      {
        "path": "archive/gor/Sources/gor/Stereo/StereoDetection.swift",
        "block": "source1",
        "sha256": "a061f7c0b1ca1453d59c909c165c91daf63a77c5fb01935a47f91aa885656c29",
        "read_only_dependency": false
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-22.py",
        "block": "fixtures1",
        "sha256": "730c373aa4798b02ab0eb98bf6629f9a0d5bcf336784e31bc3fb39c669adc5f6"
      },
      {
        "path": "archive/gor/Tests/Architecture/199e/W-gdb-199e-1nstinct-22.json",
        "block": "fixtures2",
        "sha256": "7467ff10b225b04904a3b225f4071819f3c76020aba1c3594346dae649087c5c"
      }
    ],
    "log_block": "actual_run_log",
    "log_sha256": "10c5cf8835b9cc03fed10a0871bf58b4b5cece4d0935d01657510480b3f87f8a",
    "last_5_lines": [
      "0x000056283b6b0000\u20130x000056283b6b6e38 <no build ID> test /tmp/tmpyebsoz9t/test",
      "",
      "Backtrace took 0.00s",
      "",
      ""
    ],
    "receipt_sha256": "e64a75c6ff7b8c53d286b4f478b571634c74f402f856ba6d0240b4256e93cfb5"
  }
}
```

```swift id=source1
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// MARK: - VRRecognition
/// first matching rule wins. Pure so the shipped contract is fixture-testable.
enum VRRecognition {
    struct Choice: Equatable { let kind: String; let reason: String }
    static func choose(remembered: String?, projection: String?, stereoSBS: Bool,
                       filename: String, width: Double, height: Double, manualThisSession: Bool = false, stereoTB: Bool = false) -> Choice {
        if let r = remembered { return Choice(kind:r, reason:"remembered") }
        if let p = projection, ["vr180", "vr180-tb", "vr360-mono", "vr360-tb", "flat-sbs", "flat-tb", "mono"].contains(p) {
            return Choice(kind:p, reason:"projectionMetadata")
        }
        if projection == "unsupported" { return Choice(kind:"mono",reason:"unsupportedProjectionMetadata") }
        // Stereo correspondence and square-eye geometry do not prove spherical projection.
        if stereoSBS {return Choice(kind:"flat-sbs",reason:"stereoMetadata")}
        if stereoTB {return Choice(kind:"flat-tb",reason:"topBottomMetadata")}
        return Choice(kind:"mono", reason:"monoNegative")
    }
    static func suggestion(filename:String,width:Double,height:Double)->String {
        let name=URL(fileURLWithPath:filename).lastPathComponent.lowercased()
        if name.range(of:#"(?:^|[^a-z0-9])(?:vr180|180)(?:x180|sbs|lr|3dh)?(?:[^a-z0-9]|$)"#,options:.regularExpression) != nil {return "2d (name suggests VR180?)"}
        if name.contains("sbs") || (height>0 && width/height>=3.2) {return "2d (looks like SBS?)"}
        return "2d"
    }
    struct MPVEvidence {
        let stereoSBS:Bool
        let stereoTB:Bool
        let projection:String?
        let metadataStereo:String
        let metadataProjection:String
    }
    static func mpvEvidence(stereoMode:String?,metadata:[String:String])->MPVEvidence {
        let normalized=Dictionary(metadata.map {($0.key.lowercased().replacingOccurrences(of:"-",with:"_"),$0.value.lowercased())},uniquingKeysWith:{$0+" "+$1})
        let stereo=normalized["stereo_mode"] ?? normalized["stereo3d"] ?? normalized["stereoscopic"] ?? ""
        let projection=normalized["projection"] ?? normalized["projection_type"] ?? ""
        func sbs(_ s:String)->Bool {
            ["sbs","side_by_side","side-by-side","side by side","left_right","right_left","left-right","right-left","half_sbs","full_sbs"].contains(s)
        }
        let tb=["tb","top_bottom","bottom_top","top and bottom","over_under","half_tb","full_tb"].contains(stereoMode?.lowercased() ?? "") || ["tb","top_bottom","bottom_top","top and bottom","over_under","half_tb","full_tb"].contains(stereo)
        let p:String? = ["vr180","half equirectangular","half_equirectangular"].contains(projection) ? (tb ? "vr180-tb":"vr180") :
            (["equirectangular","vr360","360"].contains(projection) ? (tb ? "vr360-tb":"vr360-mono") : (sbs(projection) ? "flat-sbs":(["tb","top_bottom","top and bottom","over_under"].contains(projection) ? "flat-tb":nil)))
        return MPVEvidence(stereoSBS:sbs(stereoMode?.lowercased() ?? "") || sbs(stereo),stereoTB:tb,projection:p,metadataStereo:stereo,metadataProjection:projection)
    }
    static func fileIdentity(_ path: String) -> String {
        // Canonical location plus current file identity: a replacement at the same path is not the old movie.
        if path.contains("://") || path.lowercased().hasPrefix("magnet:") {
            guard var u=URLComponents(string:path) else {return path}
            u.scheme=u.scheme?.lowercased();u.host=u.host?.lowercased();u.fragment=nil
            u.queryItems=u.queryItems?.sorted {($0.name,$0.value ?? "") < ($1.name,$1.value ?? "")}
            return u.string ?? path
        }
        let url = URL(fileURLWithPath:path).resolvingSymlinksInPath().standardizedFileURL
        let a = try? FileManager.default.attributesOfItem(atPath:url.path)
        return [url.path, String(describing:a?[.systemFileNumber] ?? ""),
                String(describing:a?[.size] ?? ""), String(describing:a?[.modificationDate] ?? "")].joined(separator:"|")
    }
}

// MARK: - SBSPairEvidence
/// production classifier: 8 luma frames, NCC median and genuine disparity votes.
enum SBSPairEvidence {
    struct Match {let ncc:Double;let shift:Int}
    struct Verdict {let layout:String?;let median:Double;let nonzero:Int}
    static func match(_ bytes:Data,width:Int,height:Int,topBottom:Bool=false)->Match? {
        guard width>=64,height>=32,width%2==0,height%2==0,bytes.count==width*height else{return nil}
        let a=[UInt8](bytes),w=topBottom ? width:width/2,h=topBottom ? height/2:height
        let maxShift=max(1,Int((Double(w)*0.03).rounded()))
        var best:Match?
        // Zero first: identical duplicate views never win a nonzero vote on ties.
        let shifts=[0]+(1...maxShift).flatMap{[-$0,$0]}
        for shift in shifts {
            var n=0.0,sl=0.0,sr=0.0,ll=0.0,rr=0.0,lr=0.0
            for y in stride(from:3,to:h-3,by:2) {for x in stride(from:maxShift+2,to:w-maxShift-2,by:2) {
                let rightX=x+shift+(topBottom ? 0:w),rightY=y+(topBottom ? h:0)
                let l=Double(a[y*width+x]),r=Double(a[rightY*width+rightX]);n+=1;sl+=l;sr+=r;ll+=l*l;rr+=r*r;lr+=l*r
            }}
            guard n>0 else{continue};let vl=ll-sl*sl/n,vr=rr-sr*sr/n
            guard vl/n>120,vr/n>120 else{continue}
            let score=(lr-sl*sr/n)/sqrt(vl*vr)
            if best==nil || score>best!.ncc+1e-9 {best=Match(ncc:score,shift:shift)}
        }
        return best
    }
    static func classify(_ frames:[Data],width:Int,height:Int)->Verdict {
        guard frames.count==8 else{return Verdict(layout:nil,median:0,nonzero:0)}
        func vote(_ tb:Bool)->Verdict {
            let m=frames.compactMap{match($0,width:width,height:height,topBottom:tb)}
            guard m.count==8 else{return Verdict(layout:nil,median:0,nonzero:0)}
            let scores=m.map{$0.ncc}.sorted(),median=(scores[3]+scores[4])/2,n=m.filter{$0.shift != 0}.count
            return Verdict(layout:median>=0.85 && n>=3 ? (tb ? "top-bottom":"side-by-side"):nil,median:median,nonzero:n)
        }
        let sbs=vote(false),tb=vote(true)
        if sbs.layout != nil,tb.layout != nil {return sbs.median>=tb.median ? sbs:tb}
        return sbs.layout != nil ? sbs:tb
    }
}

// MARK: - VRProjectionProbe
/// Bounded metadata and 8-frame local decoded-luma probe per file opening. No user image is written.
enum VRProjectionProbe {
    struct Result {
        var projection: String? // vr180 / flat-sbs / unsupported; nil = absent or unreadable
        var stereoSBS = false
        var stereoTopBottom = false
        var eyeAspect:Double?
        var eyeCrop:SBSEyeCrop.NormalizedCrop?
        var circularProfile=false
        var suggestedLayout:String? // image evidence is advisory only, never SOURCE
        var status: String
    }
    /// ffprobe prints the sv3d equi bounds as 0.32 fixed point (bound_left/right/top/bottom of 2^32). 180 wide = left+right is half the turn; nothing cropped top or bottom.
    static func coversHalfSphere(_ item: [String:Any]) -> Bool {
        func v(_ k: String) -> Double? { (item[k] as? NSNumber)?.doubleValue ?? (item[k] as? String).flatMap { Double($0) } }
        guard let l = v("bound_left"), let r = v("bound_right") else { return false }
        let t = v("bound_top") ?? 0, b = v("bound_bottom") ?? 0, turn = 4294967296.0
        return abs((l + r) / turn - 0.5) < 0.01 && (t + b) / turn < 0.01
    }
    static func parse(_ data: Data) -> Result {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String:Any],
              let streams = root["streams"] as? [[String:Any]], let stream = streams.first else {
            return Result(status:"invalidProbeJSON")
        }
        var result = Result(status:"metadataAbsent")
        let sides = stream["side_data_list"] as? [[String:Any]] ?? []
        for item in sides {
            let type = item["side_data_type"] as? String ?? ""
            if type == "Stereo 3D", item["type"] as? String == "side by side" { result.stereoSBS = true }
            if type == "Stereo 3D", item["type"] as? String == "top and bottom" {result.stereoTopBottom=true}
            if type == "Spherical Mapping" {
                // FFmpeg av_spherical_projection_name() values; equirectangular alone has no 180 coverage proof.
                let projection = item["projection"] as? String ?? ""
                if projection == "half equirectangular" || (projection == "tiled equirectangular" && coversHalfSphere(item)) { result.projection = "vr180" }   // sv3d equi bounds 90+90 deg cropped = 180 x 180
                else if projection == "equirectangular" {result.projection="vr360-mono"}
                else if projection == "rectilinear" { result.projection = nil }
                else { result.projection = "unsupported" }
                result.status = "projectionMetadata"
            }
        }
        if let tags = stream["tags"] as? [String:Any], let stereo = tags["stereo_mode"] as? String,
           ["left_right","right_left"].contains(stereo) { result.stereoSBS = true }
        if let tags=stream["tags"] as? [String:Any],let stereo=tags["stereo_mode"] as? String,["top_bottom","bottom_top"].contains(stereo) {result.stereoTopBottom=true}
        if result.stereoTopBottom {
            if result.projection=="vr180" {result.projection="vr180-tb"}
            if result.projection=="vr360-mono" {result.projection="vr360-tb"}
        }
        return result
    }
    static func applyGeometry(_ result:inout Result,frames:[Data],metadata bytes:Data,filename:String="") {
                    let metadata=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]
                    let stream=(metadata?["streams"] as? [[String:Any]])?.first ?? [:]
                    let cw=(stream["width"] as? NSNumber)?.doubleValue ?? 0,ch=(stream["height"] as? NSNumber)?.doubleValue ?? 0
                    let sarParts=(stream["sample_aspect_ratio"] as? String ?? "1:1").split(separator:":").compactMap{Double($0)}
                    let sar=sarParts.count==2 && sarParts[1]>0 ? sarParts[0]/sarParts[1]:1
                    let tb=result.stereoTopBottom && !result.stereoSBS
                    let full=tb ? ch/cw>=3:SBSGeometry.packing(width:cw,height:ch,filename:filename).full
                    result.eyeCrop=SBSEyeCrop.sourceCrop(frames,width:320,height:90,topBottom:tb)
                    result.eyeAspect=SBSEyeCrop.eyeAspect(frames,width:320,height:90,codedWidth:cw,codedHeight:ch,sar:sar,full:full,topBottom:tb)
                    result.circularProfile=cw>=3840 && ch>0 && abs(cw/ch/2-1)<=0.02 && SBSEyeCrop.circularEdge(frames,width:320,height:90)
                    if result.projection == nil && result.circularProfile && result.suggestedLayout == "side-by-side" {result.projection="vr180"}
                    else if result.projection == nil && result.circularProfile {result.suggestedLayout = result.suggestedLayout ?? "vr180?"}
    }
    static func inspect(_ path: String, completion: @escaping (Result) -> Void) {
        DispatchQueue.global(qos:.utility).async {
            inspectSync(path,completion:completion)
        }
    }
    private static func inspectSync(_ path:String,completion:@escaping(Result)->Void) {
            // Follow the existing optional ffprobe dependency, without installing anything or guessing a binary.
            let paths = [GORResources.vendorPath("ffmpeg/bin/ffprobe"), "/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe"]
            var bytes=Data()
            var result=Result(status:"ffprobeUnavailable")
            if let binary=paths.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) {
            let process = Process(), pipe = Pipe()
            process.executableURL = URL(fileURLWithPath:binary)
            process.arguments = ["-v","error","-rw_timeout","5000000","-select_streams","v:0","-show_streams","-show_format","-of","json",path]
            process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            do { try process.run() } catch {
                DispatchQueue.main.async { completion(Result(status:"probeLaunchFailed")) }; return
            }
            let deadline = DispatchWorkItem { if process.isRunning { kill(process.processIdentifier,SIGKILL) } }
            DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+8,execute:deadline)
            var oversized = false
            while true {
                let chunk = pipe.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                if bytes.count + chunk.count <= 262144 { bytes.append(chunk) } else { oversized = true }
            }
            process.waitUntilExit(); deadline.cancel()
            result = oversized ? Result(status:"probeOversized") :
                (process.terminationStatus == 0 ? parse(bytes) : Result(status:"probeFailedOrTimedOut"))
            }
            // Image-pair evidence can suggest a layout, never promote SOURCE (191a A3).
            // Local files only: do not add competing stream reads to magnet/network playback.
            if result.projection == nil,!path.contains("://") {
                let ffmpeg=GORResources.vendorPath("ffmpeg/bin/ffmpeg")
                if FileManager.default.isExecutableFile(atPath:ffmpeg) {
                    let metadataRoot=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any]
                    let metadataStream=(metadataRoot?["streams"] as? [[String:Any]])?.first ?? [:]
                    let format=metadataRoot?["format"] as? [String:Any] ?? [:]
                    let duration=Double(metadataStream["duration"] as? String ?? "") ?? Double(format["duration"] as? String ?? "") ?? 0
                    var positions:[Double]=[]
                    for i in 0..<8 {
                        let t:Double=duration>0 ? duration*(Double(i)+0.5)/8.0:2.0+Double(i)*4.0
                        positions.append(t)
                    }
                    var frames:[Data]=[]
                    for at in positions {
                        let p=Process(),out=Pipe();p.executableURL=URL(fileURLWithPath:ffmpeg)
                        p.arguments=["-v","error","-nostdin","-ss",String(at),"-i",path,"-map","0:v:0","-an","-sn","-frames:v","1","-vf","scale=320:90","-pix_fmt","gray","-f","rawvideo","pipe:1"]
                        p.standardOutput=out;p.standardError=FileHandle.nullDevice;p.standardInput=FileHandle.nullDevice
                        do {try p.run()} catch {break}
                        let timeout=DispatchWorkItem {if p.isRunning{kill(p.processIdentifier,SIGKILL)}}
                        DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+3,execute:timeout)
                        let bytes=out.fileHandleForReading.readDataToEndOfFile();p.waitUntilExit();timeout.cancel()
                        if p.terminationStatus==0,bytes.count==320*90 {frames.append(bytes)}
                    }
                    let verdict=SBSPairEvidence.classify(frames,width:320,height:90)
                    if let layout=verdict.layout {result.suggestedLayout=layout;result.status="suggestionOnly-"+layout}
                    applyGeometry(&result,frames:frames,metadata:bytes,filename:path)
                }
            }
            let finalResult=result
            DispatchQueue.main.async { completion(finalResult) }
    }
}

```

```python id=fixtures1
from pathlib import Path
import sys,json,subprocess,tempfile,os,shutil,resource
resource.setrlimit(resource.RLIMIT_CORE,(0,0))
ROOT=Path(__file__).resolve().parents[5 if 'archive/gor/Tests' in str(Path(__file__)) else 3]
cfg=json.loads(Path(__file__).with_suffix('.json').read_text())
swift=os.environ.get('SWIFTC') or shutil.which('swiftc')
if not swift:print('NOT_RUN compiler absent');sys.exit(77)
def declaration(s,marker):
 start=s.index(marker);i=s.index('{',start)+1;depth=1
 while depth:
  if s[i]=='{':depth+=1
  elif s[i]=='}':depth-=1
  i+=1
 return s[start:i]
with tempfile.TemporaryDirectory() as td:
 td=Path(td);inputs=[]
 if cfg['markers']:
  s=(ROOT/cfg['source']).read_text();selected='\n'.join(declaration(s,m) for m in cfg['markers'])
  if cfg['wrapper']:selected=cfg['wrapper']+' {\n'+selected+'\n}'
  source=td/'Production.swift';source.write_text('import Foundation\n'+cfg['support']+'\n'+selected+'\n');inputs=[str(source)]
 else:
  inputs=[str(ROOT/cfg['source'])]+[str(ROOT/p) for p in cfg['deps']]
  if cfg['support']:
   source=td/'Support.swift';source.write_text('import Foundation\n'+cfg['support']+'\n');inputs.append(str(source))
 main=td/'main.swift';main.write_text((source.read_text()+'\n' if cfg['source'].endswith('ArchiveLibrary.swift') else '')+cfg['test_source']);exe=td/'test'
 if cfg['source'].endswith('ArchiveLibrary.swift'):inputs=[]
 c=subprocess.run([swift]+inputs+[str(main),'-o',str(exe)],capture_output=True,text=True,timeout=90);print('compile_exit='+str(c.returncode));print(c.stdout+c.stderr)
 if c.returncode:sys.exit(2)
 c=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30);print('semantic_exit='+str(c.returncode));print(c.stdout+c.stderr);sys.exit(0 if c.returncode==0 else 1)

```

```json id=fixtures2
{
  "source": "archive/gor/Sources/gor/Stereo/StereoDetection.swift",
  "markers": [
    "enum SBSPairEvidence {"
  ],
  "wrapper": "",
  "support": "",
  "deps": [],
  "test_source": "import Foundation\nvar failures=0\nfunc check(_ ok:Bool,_ label:String){ print((ok ? \"PASS \":\"FAIL \")+label); if !ok {failures+=1} }\ncheck(SBSPairEvidence.match(Data(),width:Int.max-1,height:32) == nil,\"overflow dimensions refused\")\ncheck(SBSPairEvidence.match(Data(),width:64,height:32) == nil,\"short buffer refused\")\ncheck(SBSPairEvidence.match(Data(repeating:0,count:64*32),width:64,height:32) == nil,\"low-variance evidence remains absent\")\nexit(failures==0 ? 0:1)\n"
}

```

```text id=actual_run_log
compile_exit=0

semantic_exit=-4

*** Signal 4: Backtracing from 0x56283b6b5928... done ***

*** Program crashed: Illegal instruction at 0x000056283b6b5928 ***

Thread 0 "test" crashed:

0      0x000056283b6b5928 static SBSPairEvidence.match(_:width:height:topBottom:) + 4920 in test
1 [ra] 0x000056283b6b618e main + 77 in test


Registers:

rax 0xffffffffffffff01  18446744073709551361
rdx 0x0000000000000000  0
rcx 0x0000000000000020  32
rbx 0x0000000000000000  0
rsi 0x0000000000000000  0
rdi 0xc000000000000000  13835058055282163712
rbp 0x00007ffc38dc0f10  30 10 dc 38 fc 7f 00 00 8e 61 6b 3b 28 56 00 00  0·Ü8ü····ak;(V··
rsp 0x00007ffc38dc09d0  00 00 00 00 00 00 00 00 e0 62 be 55 8c 7f 00 00  ········àb¾U····
 r8 0x00007ffc38dc09d0  00 00 00 00 00 00 00 00 e0 62 be 55 8c 7f 00 00  ········àb¾U····
 r9 0x0000000000000010  16
r10 0x00007f8c5442cf58  d1 46 00 00 12 03 0b 00 10 95 2e 00 00 00 00 00  ÑF········.·····
r11 0x00007f8c546e9510  e9 fb 14 ea ff 66 66 2e 0f 1f 84 00 00 00 00 00  éû·êÿff.········
r12 0x00007ffc38dc1148  3f 1c dc 38 fc 7f 00 00 00 00 00 00 00 00 00 00  ?·Ü8ü···········
r13 0x000056283b6b6140  55 48 89 e5 48 81 ec 10 01 00 00 48 c7 05 4a 32  UH·åH·ì····HÇ·J2
r14 0x000056283b6b8ac8  e8 d0 9d 55 8c 7f 00 00 a0 0e 9e 55 8c 7f 00 00  èÐ·U···· ··U····
r15 0x00007f8c55be5040  e0 62 be 55 8c 7f 00 00 15 00 00 00 00 00 00 00  àb¾U············
rip 0x000056283b6b5928  0f 0b 0f 0b 0f 0b 0f 0b 0f 0b 0f 0b 0f 0b 0f 0b  ················

rflags 0x0000000000010202  

cs 0x0033  fs 0x0000  gs 0x0000


Images (19 omitted):

0x000056283b6b0000–0x000056283b6b6e38 <no build ID> test /tmp/tmpyebsoz9t/test

Backtrace took 0.00s



```

Publication caveat: NONQUALIFIED: exact-source declaration extraction, not native/full module acceptance. HeatTelemetry in A27 is an explicit test support value, not production telemetry evidence. Own compiler rerun NOT_RUN.
Claim lease:2hwithout verified progress, existing owner earliest-claim workflow. Single production source and own tests only.
