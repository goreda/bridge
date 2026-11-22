import Foundation

/// Binding must match exactly. Never reuse a rendered screenshot as a decoded source.
public struct PhotonSourceBinding: Equatable, Codable, Sendable {
    public let session: UInt64
    public let generation: UInt64
    public let frameIndex: UInt64
    public init(session: UInt64, generation: UInt64, frameIndex: UInt64) {
        self.session=session; self.generation=generation; self.frameIndex=frameIndex
    }
}
public enum PhotonMeasurementDomain: String, Codable, Sendable { case decodedSDRSignal, decodedPQSignal, decodedHLGSignal }
public struct PhotonPictureRect: Equatable, Codable, Sendable {
    public let x: Int, y: Int, width: Int, height: Int
    public init(x: Int, y: Int, width: Int, height: Int) { self.x=x; self.y=y; self.width=width; self.height=height }
    public func valid(width w: Int, height h: Int) -> Bool {
        x>=0 && y>=0 && width>=7 && height>=7 && x<=w && y<=h && width<=w-x && height<=h-y
    }
}
public struct PhotonSourceMeasurement: Equatable, Sendable {
    public let binding: PhotonSourceBinding
    public let domain: PhotonMeasurementDomain
    public let pictureRect: PhotonPictureRect
    public let sigma: [Double]
    public let counts: [Int]
    /// No guessed cluster size from residual sigma. nil until validated spatial-fit estimator.
    public let sourceCellPixels: Double?
    public let cellConfidence: Double
    public init(binding: PhotonSourceBinding, domain: PhotonMeasurementDomain, pictureRect: PhotonPictureRect,
                sigma: [Double], counts: [Int], sourceCellPixels: Double?, cellConfidence: Double) {
        self.binding=binding;self.domain=domain;self.pictureRect=pictureRect;self.sigma=sigma;self.counts=counts
        self.sourceCellPixels=sourceCellPixels;self.cellConfidence=cellConfidence
    }
    public func admits(_ expected: PhotonSourceBinding, domain expectedDomain: PhotonMeasurementDomain) -> Bool {
        binding==expected && domain==expectedDomain && sigma.count==8 && counts.count==8 && sigma.allSatisfy({$0.isFinite && $0>=0}) && counts.allSatisfy({$0>=0}) && cellConfidence.isFinite && cellConfidence>=0 && cellConfidence<=1
    }
}

/// CPU witness, not the runtime GPU stage. Luma must come from decoded texture
/// before sharp/grain, in the domain bound below. Positive sigma is residual
/// granularity; the .96 white-noise transfer gain correction is NOT applied
/// to correlated film because that would silently impose a source-size model.
public enum PhotonSourceMeasurementReference {
    public static func measure(luma: [Float], width: Int, height: Int, rect: PhotonPictureRect,
                               binding: PhotonSourceBinding, domain: PhotonMeasurementDomain) throws -> PhotonSourceMeasurement {
        guard width>0, height>0, width<=Int.max/height, luma.count==width*height,
              rect.valid(width:width,height:height), luma.allSatisfy({$0.isFinite}) else { throw PhotonV4Error.invalid("decoded luma") }
        func denoise(_ x: Int, _ y: Int) -> Double {
            var sum=0.0
            for dy in -2...2 { for dx in -2...2 { sum+=Double(luma[(y+dy)*width+x+dx]) } }
            return sum/25
        }
        var squares=[Double](repeating:0,count:8), sums=squares, counts=[Int](repeating:0,count:8)
        for y in (rect.y+3)..<(rect.y+rect.height-3) { for x in (rect.x+3)..<(rect.x+rect.width-3) {
            let smooth=denoise(x,y)
            let gx=abs(denoise(x+1,y)-denoise(x-1,y)), gy=abs(denoise(x,y+1)-denoise(x,y-1))
            // Edge threshold is signal-domain, provisional until real-corpus calibration.
            if max(gx,gy)>0.02 { continue }
            let bin=min(7,max(0,Int(floor(min(1,max(0,smooth))*8))))
            let r=Double(luma[y*width+x])-smooth
            squares[bin]+=r*r; sums[bin]+=r; counts[bin]+=1
        } }
        let sigma=(0..<8).map { i -> Double in
            guard counts[i]>=32 else { return 0 }
            let n=Double(counts[i]); return sqrt(max(0,(squares[i]-sums[i]*sums[i]/n)/(n-1)))
        }
        return PhotonSourceMeasurement(binding:binding,domain:domain,pictureRect:rect,sigma:sigma,counts:counts,sourceCellPixels:nil,cellConfidence:0)
    }
}
