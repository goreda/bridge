import Foundation

/// Bounds-checked big-endian reader over a byte slice. Every out-of-range
/// access throws `DemuxError.truncated`; there are no unsafe reads.
struct Cursor {
    let bytes: [UInt8]
    var pos: Int
    let end: Int

    init(_ bytes: [UInt8], _ start: Int, _ end: Int) throws {
        guard start >= 0, start <= end, end <= bytes.count else {
            throw DemuxError.truncated("cursor range \(start)..<\(end) outside \(bytes.count) bytes")
        }
        self.bytes = bytes
        self.pos = start
        self.end = end
    }

    var remaining: Int { end - pos }

    mutating func take(_ n: Int, _ what: String) throws -> Int {
        guard n >= 0, pos + n <= end else {
            throw DemuxError.truncated("\(what): need \(n) bytes at \(pos), have \(remaining)")
        }
        let p = pos
        pos += n
        return p
    }

    mutating func u8(_ what: String = "u8") throws -> UInt8 {
        bytes[try take(1, what)]
    }

    mutating func u16(_ what: String = "u16") throws -> UInt16 {
        let p = try take(2, what)
        return UInt16(bytes[p]) << 8 | UInt16(bytes[p + 1])
    }

    mutating func i16(_ what: String = "i16") throws -> Int16 {
        Int16(bitPattern: try u16(what))
    }

    mutating func u32(_ what: String = "u32") throws -> UInt32 {
        let p = try take(4, what)
        return UInt32(bytes[p]) << 24 | UInt32(bytes[p + 1]) << 16 | UInt32(bytes[p + 2]) << 8 | UInt32(bytes[p + 3])
    }

    mutating func i32(_ what: String = "i32") throws -> Int32 {
        Int32(bitPattern: try u32(what))
    }

    mutating func u64(_ what: String = "u64") throws -> UInt64 {
        let hi = UInt64(try u32(what))
        let lo = UInt64(try u32(what))
        return hi << 32 | lo
    }

    mutating func i64(_ what: String = "i64") throws -> Int64 {
        Int64(bitPattern: try u64(what))
    }

    func slice(_ start: Int, _ count: Int, _ what: String) throws -> [UInt8] {
        guard start >= 0, count >= 0, start + count <= bytes.count else {
            throw DemuxError.truncated("\(what): need \(count) bytes at \(start), have \(bytes.count)")
        }
        return Array(bytes[start ..< start + count])
    }
}
