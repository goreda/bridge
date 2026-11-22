import Foundation
import CoreVideo

/// Bounded7x7 face samples plus6x3 eye samples. No pixels leave this function.
/// Vision boxes have Y-up coordinates; BGRA rows are Y-down.
enum PoseFrameQuality {
    static func measure(_ buffer:CVPixelBuffer,face:CGRect,eyes:[CGPoint])->(mean:Double,contrast:Double,clipped:Double)? {
        guard CVPixelBufferGetPixelFormatType(buffer)==kCVPixelFormatType_32BGRA else{return nil}
        CVPixelBufferLockBaseAddress(buffer,.readOnly)
        defer{CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}
        guard let base=CVPixelBufferGetBaseAddress(buffer) else{return nil}
        let w=CVPixelBufferGetWidth(buffer),h=CVPixelBufferGetHeight(buffer),stride=CVPixelBufferGetBytesPerRow(buffer)
        guard w>0,h>0,stride>=w*4 else{return nil}
        let ptr=base.assumingMemoryBound(to:UInt8.self)
        func luma(_ x:Double,_ y:Double)->Double {
            guard x.isFinite,y.isFinite else{return 0}
            let px=min(w-1,Int(max(0,min(1,x))*Double(w))),py=min(h-1,Int(max(0,min(1,1-y))*Double(h)))
            let i=py*stride+px*4
            return 0.114*Double(ptr[i])+0.587*Double(ptr[i+1])+0.299*Double(ptr[i+2])
        }
        var values:[Double]=[],eyeValues:[Double]=[]
        for y in 0..<7 {for x in 0..<7 {
            values.append(luma(Double(face.minX)+Double(face.width)*(Double(x)+0.5)/7,Double(face.minY)+Double(face.height)*(Double(y)+0.5)/7))
        }}
        for eye in eyes {for y in -1...1 {for x in -2...2 {
            eyeValues.append(luma(Double(eye.x)+Double(x)*Double(face.width)*0.025,Double(eye.y)+Double(y)*Double(face.height)*0.025))
        }}}
        let mean=values.reduce(0,+)/Double(values.count)
        let variance=values.reduce(0){$0+($1-mean)*($1-mean)}/Double(values.count)
        let clips=(eyeValues.isEmpty ? values:eyeValues).filter{$0>=245}.count
        return (mean,sqrt(variance),Double(clips)/Double(max(1,eyeValues.isEmpty ? values.count:eyeValues.count)))
    }
}
