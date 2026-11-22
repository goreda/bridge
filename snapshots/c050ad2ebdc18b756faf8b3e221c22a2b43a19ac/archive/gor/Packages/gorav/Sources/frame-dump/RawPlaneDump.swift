// AUTHORED_NEW (2026-11-08, queue item 13): pure raw-plane (linesize-padded)
// assembly for frame-dump --raw-planes, plus the linux unit test on a
// synthetic frame (--selftest-raw-planes). No FFmpeg imports: the geometry
// math and the synthetic-frame check run anywhere Swift runs. Honest refusal
// (nil) on any inconsistent geometry - no clipping, no guessing.
import Foundation

public enum RawPlaneDump {
    /// The exact byte count a raw (padding-INCLUDED) dump of one plane must
    /// produce: stride * rows, contiguous from the plane base. Returns nil on
    /// any inconsistency: non-positive fields, stride shorter than the
    /// visible row, multiplication overflow, or a padded region the
    /// containing buffer does not fully cover.
    public static func rawByteCount(rowBytes: Int, rows: Int, stride: Int, bufferBytes: Int) -> Int? {
        guard rowBytes > 0, rows > 0, stride >= rowBytes, bufferBytes >= 0 else { return nil }
        let (count, overflow) = stride.multipliedReportingOverflow(by: rows)
        guard !overflow, count <= bufferBytes else { return nil }
        return count
    }

    /// Assemble the raw (linesize-padded) bytes of one plane from a flat
    /// buffer whose rows are stride-advanced from the plane base at `offset`.
    /// Rows are stride-contiguous by construction, so the result is one
    /// contiguous stride*rows slice INCLUDING every padding byte. Returns nil
    /// on any geometry or coverage inconsistency.
    public static func assemble(buffer: [UInt8], offset: Int, rowBytes: Int, rows: Int, stride: Int) -> [UInt8]? {
        guard offset >= 0, offset <= buffer.count else { return nil }
        guard let count = rawByteCount(rowBytes: rowBytes, rows: rows, stride: stride,
                                       bufferBytes: buffer.count - offset) else { return nil }
        return Array(buffer[offset ..< offset + count])
    }

    /// Linux unit test (queue item 13 done-when): a synthetic frame with
    /// deliberately padded linesizes, plus the refusal cases. Prints one
    /// RAWPLANE_SELFTEST_PASS/FAIL line per check and a FINAL line; returns
    /// true only when every check holds. No decoder, no fixture, no native
    /// calls - the synthetic buffers stand in for an AVFrame's planes.
    public static func runSelfTest() -> Bool {
        var ok = true
        func chk(_ name: String, _ cond: Bool) {
            print("RAWPLANE_SELFTEST_\(cond ? "PASS" : "FAIL") \(name)")
            if !cond { ok = false }
        }

        // Synthetic Y plane: 6 visible bytes x 4 rows, stride 8, padding 0xEE.
        let yRow: [UInt8] = [10, 20, 30, 40, 50, 60]
        var yBuf: [UInt8] = []
        for _ in 0..<4 { yBuf.append(contentsOf: yRow); yBuf.append(contentsOf: [0xEE, 0xEE]) }
        let y = assemble(buffer: yBuf, offset: 0, rowBytes: 6, rows: 4, stride: 8)
        chk("y.count_is_stride_x_rows", y?.count == 32)
        chk("y.row1_visible_bytes", y.map { Array($0[8..<14]) == yRow } ?? false)
        chk("y.padding_preserved", y.map { $0[6] == 0xEE && $0[7] == 0xEE && $0[30] == 0xEE && $0[31] == 0xEE } ?? false)

        // Synthetic chroma plane at a nonzero offset in a shared buffer
        // (shared-buffer planar allocations are a retained-frame reality).
        let uRow: [UInt8] = [1, 2, 3]
        var shared: [UInt8] = Array(repeating: 0x00, count: 16)
        for _ in 0..<2 { shared.append(contentsOf: uRow); shared.append(0xEE) }
        let u = assemble(buffer: shared, offset: 16, rowBytes: 3, rows: 2, stride: 4)
        chk("u.offset_plane_count", u?.count == 8)
        chk("u.offset_plane_bytes", u.map { Array($0[0..<3]) == uRow && Array($0[4..<7]) == uRow && $0[3] == 0xEE && $0[7] == 0xEE } ?? false)

        // Refusals: every inconsistent geometry is nil, never a clipped copy.
        chk("refuse_stride_shorter_than_row", assemble(buffer: yBuf, offset: 0, rowBytes: 6, rows: 4, stride: 5) == nil)
        chk("refuse_uncovered_padding", assemble(buffer: Array(yBuf[0..<31]), offset: 0, rowBytes: 6, rows: 4, stride: 8) == nil)
        chk("refuse_zero_rowbytes", assemble(buffer: yBuf, offset: 0, rowBytes: 0, rows: 4, stride: 8) == nil)
        chk("refuse_zero_rows", assemble(buffer: yBuf, offset: 0, rowBytes: 6, rows: 0, stride: 8) == nil)
        chk("refuse_negative_offset", assemble(buffer: yBuf, offset: -1, rowBytes: 6, rows: 4, stride: 8) == nil)
        chk("refuse_offset_past_end", assemble(buffer: yBuf, offset: 33, rowBytes: 6, rows: 4, stride: 8) == nil)
        chk("refuse_overflow", rawByteCount(rowBytes: 1, rows: Int.max, stride: Int.max, bufferBytes: Int.max) == nil)
        chk("refuse_tight_buffer", rawByteCount(rowBytes: 6, rows: 4, stride: 8, bufferBytes: 31) == nil)

        print("RAWPLANE_SELFTEST_FINAL \(ok ? "PASS" : "FAIL")")
        return ok
    }
}
