import Foundation

/// Minimal clean-room hvcC/SPS syntax reader, only through sub-layer ordering.
/// Unsupported/truncated configuration throws rather than guessing reorder depth.
struct HEVCReorder {
    private struct Bits {
        let bytes: [UInt8]
        var position = 0
        mutating func read(_ count: Int) throws -> Int {
            guard count >= 0, count <= 31, position <= bytes.count*8-count else {
                throw DemuxError.truncated("HEVC SPS bits")
            }
            var value = 0
            for _ in 0..<count {
                value = value*2 + Int((bytes[position/8] >> (7-position%8)) & 1)
                position += 1
            }
            return value
        }
        mutating func skip(_ count: Int) throws {
            guard position <= bytes.count*8-count else { throw DemuxError.truncated("HEVC profile tier level") }
            position += count
        }
        mutating func ue() throws -> Int {
            var zeros = 0
            while try read(1) == 0 {
                zeros += 1
                guard zeros <= 20 else { throw DemuxError.unsupported("HEVC SPS Exp-Golomb limit") }
            }
            return (1 << zeros)-1 + (try read(zeros))
        }
    }
    static func depth(hvcc: [UInt8]) throws -> Int {
        guard hvcc.count >= 23, hvcc[0] == 1 else { throw DemuxError.unsupported("HEVC requires hvcC CodecPrivate") }
        var offset = 23
        var depths: [Int] = []
        for _ in 0..<Int(hvcc[22]) {
            guard offset+3 <= hvcc.count else { throw DemuxError.truncated("HEVC hvcC array") }
            let type = hvcc[offset] & 63
            let count = Int(hvcc[offset+1])*256 + Int(hvcc[offset+2]); offset += 3
            for _ in 0..<count {
                guard offset+2 <= hvcc.count else { throw DemuxError.truncated("HEVC NAL length") }
                let length = Int(hvcc[offset])*256 + Int(hvcc[offset+1]);offset += 2
                guard length >= 2, length <= hvcc.count-offset else { throw DemuxError.truncated("HEVC NAL bytes") }
                if type == 33 { depths.append(try sps(Array(hvcc[offset..<offset+length]))) }
                offset += length
            }
        }
        guard !depths.isEmpty, Set(depths).count == 1 else { throw DemuxError.unsupported("HEVC missing or varying SPS reorder depth") }
        return depths[0]
    }
    private static func sps(_ nal: [UInt8]) throws -> Int {
        var rbsp: [UInt8] = [], zeros = 0
        for byte in nal.dropFirst(2) {
            if zeros >= 2 && byte == 3 { zeros = 0; continue }
            rbsp.append(byte); zeros = byte == 0 ? zeros+1 : 0
        }
        var bits = Bits(bytes: rbsp)
        try bits.skip(4)
        let layers = try bits.read(3)
        try bits.skip(1+96)
        var flags: [(Int,Int)] = []
        for _ in 0..<layers { flags.append((try bits.read(1), try bits.read(1))) }
        if layers > 0 { try bits.skip((8-layers)*2) }
        for (profile,level) in flags {
            if profile == 1 { try bits.skip(88) }
            if level == 1 { try bits.skip(8) }
        }
        _ = try bits.ue() // sps_seq_parameter_set_id
        let chroma = try bits.ue()
        guard chroma <= 3 else { throw DemuxError.malformed("HEVC chroma_format_idc") }
        if chroma == 3 { try bits.skip(1) }
        _ = try bits.ue(); _ = try bits.ue() // width/height
        if try bits.read(1) == 1 { for _ in 0..<4 { _ = try bits.ue() } }
        _ = try bits.ue(); _ = try bits.ue(); _ = try bits.ue()
        let allLayers = try bits.read(1)
        var depth = 0
        for _ in (allLayers == 1 ? 0 : layers)...layers {
            let buffering = try bits.ue(), reorder = try bits.ue()
            _ = try bits.ue()
            guard reorder <= buffering, reorder <= 16 else { throw DemuxError.unsupported("HEVC reorder depth limit") }
            depth = max(depth, reorder)
        }
        return depth
    }
}
