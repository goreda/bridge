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
