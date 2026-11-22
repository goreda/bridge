import Foundation

// MARK: - SBSGeometry
/// Separates coded storage, anamorphic packing and post-crop eye geometry.
enum SBSGeometry {
    static func parseCrop(_ crop:String?)->(Double,Double)? {
        guard let crop,let re=try? NSRegularExpression(pattern:#"^([0-9]+(?:\.[0-9]+)?)x([0-9]+(?:\.[0-9]+)?)(?:\+|$)"#),
              let match=re.firstMatch(in:crop,range:NSRange(crop.startIndex...,in:crop)),
              let a=Range(match.range(at:1),in:crop),let b=Range(match.range(at:2),in:crop),
              let w=Double(crop[a]),let h=Double(crop[b]),w>0,h>0 else{return nil}
        return (w,h)
    }
    /// One authority for full versus half packing: explicit filename token first, else frame layout.
    static func packing(width:Double,height:Double,filename:String)->(full:Bool,basis:String) {
        let name=URL(fileURLWithPath:filename).lastPathComponent.lowercased()
        func token(_ pattern:String)->Bool {name.range(of:pattern,options:.regularExpression) != nil}
        if token(#"(?:^|[^a-z])(?:full[ ._-]*sbs|fsbs)(?:[^a-z]|$)"#) {return (true,"explicitFullToken")}
        if token(#"(?:^|[^a-z])(?:half[ ._-]*sbs|hsbs)(?:[^a-z]|$)"#) {return (false,"explicitHalfToken")}
        return (height>0 && width/height>=3.0,"block185FrameLayout")
    }
    struct Result:Equatable {let aspect:Double;let packing:String;let basis:String}
    static func resolve(width:Double,height:Double,pixelAspect:Double,filename:String,stereoProven:Bool,fullByContract:Bool=false,cropWidth:Double?=nil,cropHeight:Double?=nil)->Result? {
        guard stereoProven,width>0,height>0,width.isFinite,height.isFinite else{return nil}
        let par=pixelAspect.isFinite && pixelAspect>0 ? pixelAspect:1
        let (full,basis)=packing(width:width,height:height,filename:filename)
        // Half SBS stores each eye at half horizontal sampling. Correct that compression once.
        // Crop dimensions are the complete packed frame; each eye retains half its columns.
        let w=(cropWidth ?? width),h=(cropHeight ?? height)
        guard w>0,h>0,w<=width,h<=height else{return nil}
        return Result(aspect:w*par/h/(full ? 2:1),packing:full ? "full":"half",basis:basis)
    }
}

/// Menu ratios describe one displayed picture, independent of storage packing.
/// Crop changes the visible bounds; aspect override changes display proportions.
/// The stereo window contains two copies of that result, with the existing gap.
enum StereoMenuGeometry {
    struct Plan: Equatable {
        let scaleX: Double
        let scaleY: Double
        let eyeAspect: Double
        let windowAspect: Double
    }
    struct Viewport {
        let scaleX:Double,scaleY:Double,centerX:Double,centerY:Double,windowAspect:Double
        var key:String {"\(scaleX):\(scaleY):\(centerX):\(centerY):\(windowAspect)"}
    }
    /// Crop is a viewport, not a new source aspect. Preserve the accepted centre on every refresh.
    static func viewport(_ plan:Plan,detected:CGRect?,menuOwns:Bool) -> Viewport {
        let rect=menuOwns ? nil:detected
        let x=rect.map {Double($0.width)} ?? plan.scaleX,y=rect.map {Double($0.height)} ?? plan.scaleY
        return Viewport(scaleX:x,scaleY:y,centerX:rect.map {Double($0.midX)} ?? 0.5,
            centerY:rect.map {Double($0.midY)} ?? 0.5,windowAspect:plan.windowAspect * (rect == nil ? 1:x/y))
    }
    static func plan(sourceAspect: Double, aspectOverride: Double?, cropAspect: Double?, gap: Double) -> Plan? {
        guard sourceAspect.isFinite, sourceAspect > 0, gap.isFinite else { return nil }
        let display = aspectOverride.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? sourceAspect
        let crop = cropAspect.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let x = crop.map { min(1, $0 / display) } ?? 1
        let y = crop.map { min(1, display / $0) } ?? 1
        let eye = display * x / y
        let fraction = 0.5 - min(0.2, max(0, gap)) * 0.25
        return Plan(scaleX:x, scaleY:y, eyeAspect:eye, windowAspect:eye / fraction)
    }
}

// MARK: - SBSEyeCrop
/// scan each half independently, then retain a common eye crop.
/// No aspect-film labels. Bounds are measured in source pixels; SAR is applied once at display.
enum SBSEyeCrop {
    struct Bounds:Equatable {let x:Int;let y:Int;let width:Int;let height:Int}
    static func scan(_ frame:Data,width:Int,height:Int,topBottom:Bool=false)->[Bounds]? {
        guard width>=32,height>=32,width%2==0,height%2==0,frame.count==width*height else{return nil}
        let a=[UInt8](frame),w=topBottom ? width:width/2,h=topBottom ? height/2:height
        var out:[Bounds]=[]
        for eye in 0...1 {
            let ox=topBottom ? 0:eye*w,oy=topBottom ? eye*h:0
            // Source bounds are conservative: one nonblack sampled pixel keeps that edge.
            // Avoid row-average cropdetect silently discarding tiny bright subtitles/details.
            var minX=w,minY=h,maxX = -1,maxY = -1
            for y in 0..<h {for x in 0..<w {
                if a[(oy+y)*width+ox+x]>12 {minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y)}
            }}
            guard maxX>=minX,maxY>=minY else{return nil}
            let t=minY,b=maxY,l=minX,r=maxX
            out.append(Bounds(x:l,y:t,width:r-l+1,height:b-t+1))
        }
        return out
    }
    struct NormalizedCrop:Equatable {let x:Double;let y:Double;let width:Double;let height:Double}
    /// Common horizontal union across both eyes and every sampled frame. One
    /// sampled-pixel guard preserves boundary detail. Vertical crop remains with
    /// the original-pixel video-crop owner, avoiding a second vertical crop.
    static func sourceCrop(_ frames:[Data],width:Int,height:Int,topBottom:Bool=false)->NormalizedCrop? {
        let scans=frames.compactMap{scan($0,width:width,height:height,topBottom:topBottom)}
        guard !topBottom,scans.count>=3,scans.count==frames.count else{return nil}
        let w=width/2
        let all=scans.flatMap{$0}
        let x=max(0,(all.map{$0.x}.min() ?? 0)-1)
        let r=min(w,(all.map{$0.x+$0.width}.max() ?? w)+1)
        return NormalizedCrop(x:Double(x)/Double(w),y:0,width:Double(r-x)/Double(w),height:1)
    }
    static func eyeAspect(_ frames:[Data],width:Int,height:Int,codedWidth:Double,codedHeight:Double,sar:Double,full:Bool,topBottom:Bool=false)->Double? {
        let scans=frames.compactMap{scan($0,width:width,height:height,topBottom:topBottom)}
        guard scans.count>=3 else{return nil}
        func median(_ v:[Double])->Double {let a=v.sorted();return a[a.count/2]}
        // A common crop union avoids cutting differently in the two eyes.
        let ratios=scans.map {eyes -> Double in
            let x=min(eyes[0].x,eyes[1].x),y=min(eyes[0].y,eyes[1].y)
            let right=max(eyes[0].x+eyes[0].width,eyes[1].x+eyes[1].width)
            let bottom=max(eyes[0].y+eyes[0].height,eyes[1].y+eyes[1].height)
            let cw=Double(right-x)*codedWidth/Double(width),ch=Double(bottom-y)*codedHeight/Double(height)
            let sx=topBottom ? 1:(full ? 1:2),sy=topBottom && !full ? 2:1
            return cw*Double(sx)*(sar>0 ? sar:1)/(ch*Double(sy))
        }
        return median(ratios)
    }
    static func circularEdge(_ frames:[Data],width:Int,height:Int)->Bool {
        // Fisheye profile requires both eyes: dark corners, bright central disk, curved occupancy.
        let votes=frames.filter {frame in
            guard frame.count==width*height else{return false};let a=[UInt8](frame),w=width/2
            return (0...1).allSatisfy {eye in
                func lum(_ x:Double,_ y:Double)->Double {Double(a[min(height-1,Int(y*Double(height)))*width+eye*w+min(w-1,Int(x*Double(w)))])}
                let corners=[(0.05,0.05),(0.95,0.05),(0.05,0.95),(0.95,0.95)].map{lum($0.0,$0.1)}
                let axis=[(0.5,0.15),(0.15,0.5),(0.85,0.5),(0.5,0.85)].map{lum($0.0,$0.1)}
                return corners.allSatisfy{$0<12} && axis.allSatisfy{$0>24} && lum(0.5,0.5)>24
            }
        }
        return votes.count>=3
    }
}

// MARK: - StereoDepth
/// Physical-pixel disparity. Cross-eye maps left half to right eye; swap reverses that mapping.
/// No pose input: depth placement is independent of head-pose parallax.
enum StereoDepth {
    struct Placement { let left: Double; let right: Double; let disparity: Double }
    static func placeDepth(disparityPX: Double, distanceMM: Double?, mmPerPX: Double, swapEyes: Bool) -> Placement {
        let scale = mmPerPX > 0 ? mmPerPX : 25.4/227.0
        // Same 500mm reference as182 when camera distance is unavailable, never a guessed live distance.
        let d = (distanceMM ?? 500) > 0 ? (distanceMM ?? 500) : 500
        let limit = 2*d*tan(Double.pi/360)/scale
        let v = max(-limit,min(limit,disparityPX))
        // d = x_leftEye - x_rightEye. In cross-eye, right eye sees the left display half.
        let l = (swapEyes ? 1.0 : -1.0)*v/2
        return Placement(left:l,right:-l,disparity:v)
    }
}

/// Decoded SOURCE layout, independent of output pack and head/VR enable state.
enum CropSourcePacking {
    static func flags(_ kind: String) -> (stereo: Bool, topBottom: Bool) {
        let tb = ["flat-tb", "vr180-tb", "vr360-tb"].contains(kind)
        return (["flat-sbs", "vr180"].contains(kind) || tb, tb)
    }
}
