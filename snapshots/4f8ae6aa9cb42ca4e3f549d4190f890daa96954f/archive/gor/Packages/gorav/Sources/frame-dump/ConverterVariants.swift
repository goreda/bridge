import Foundation

/// r15 converter variant (design, never compiled by its author before the owner's Mac run).
/// yuv420p -> RGBA, BT.601 limited range, same integer matrix as YUV420Converter, but chroma is
/// reconstructed by bilinear interpolation: co-sited LEFT horizontally (even luma column x=2k uses
/// chroma k, odd x averages chroma k and k+1), CENTER vertically (row 2j weights 1/4 chroma j-1 and
/// 3/4 chroma j, row 2j+1 weights 3/4 chroma j and 1/4 chroma j+1). Edges clamp. All integer:
/// horizontal pass H = 2*c (even x) or c[k]+c[k+1] (odd x), vertical pass (a*H1 + b*H2 + 4) >> 3.
/// The existing YUV420Converter is unchanged; this is an additional type, kept in the frame-dump target.
public enum YUV420BilinearConverter {
    public static func rgbaFromYUV420pBilinear(y: UnsafePointer<UInt8>, yStride: Int,
                                               u: UnsafePointer<UInt8>, uStride: Int,
                                               v: UnsafePointer<UInt8>, vStride: Int,
                                               width: Int, height: Int) -> [UInt8] {
        let cw = (width + 1) / 2
        let ch = (height + 1) / 2
        func upsample(_ p: UnsafePointer<UInt8>, _ stride: Int) -> [Int] {
            var h = [Int](repeating: 0, count: width * ch)
            for j in 0..<ch {
                for x in 0..<width {
                    let k = x / 2
                    let c0 = Int(p[j * stride + k])
                    if x % 2 == 0 {
                        h[j * width + x] = 2 * c0
                    } else {
                        let k1 = Swift.min(k + 1, cw - 1)
                        h[j * width + x] = c0 + Int(p[j * stride + k1])
                    }
                }
            }
            var out = [Int](repeating: 0, count: width * height)
            for row in 0..<height {
                let j = row / 2
                for x in 0..<width {
                    if row % 2 == 0 {
                        let jm = Swift.max(j - 1, 0)
                        out[row * width + x] = (h[jm * width + x] + 3 * h[j * width + x] + 4) >> 3
                    } else {
                        let jp = Swift.min(j + 1, ch - 1)
                        out[row * width + x] = (3 * h[j * width + x] + h[jp * width + x] + 4) >> 3
                    }
                }
            }
            return out
        }
        let uu = upsample(u, uStride)
        let vv = upsample(v, vStride)
        var out = [UInt8](repeating: 255, count: width * height * 4)
        func clamp8(_ x: Int) -> UInt8 { UInt8(Swift.max(0, Swift.min(255, x))) }
        for row in 0..<height {
            for col in 0..<width {
                let yv = Int(y[row * yStride + col])
                let cu = uu[row * width + col] - 128
                let cv = vv[row * width + col] - 128
                let c = yv - 16
                let o = (row * width + col) * 4
                out[o]     = clamp8((298 * c + 409 * cv + 128) >> 8)
                out[o + 1] = clamp8((298 * c - 100 * cu - 208 * cv + 128) >> 8)
                out[o + 2] = clamp8((298 * c + 516 * cu + 128) >> 8)
            }
        }
        return out
    }
}
