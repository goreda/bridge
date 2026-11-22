import Foundation
import GorAVCore
import GorAVNativeProbeKit
import GorAVFFmpegAdapter

// gorav-first-frame: decodes the pinned fixture through the gorav Swift adapter
// (snapshot route: immutable snapshot -> custom AVIO -> ppm_pipe -> ppm) and
// prints the adapter's own frameDigest vs the pinned independent oracle.
@main
struct FirstFrame {
    static let pinnedBytes: [UInt8] = [
        80, 54, 10, 49, 55, 32, 49, 49, 10, 50, 53, 53, 10, 0, 0, 0, 7, 5, 13,
        14, 10, 26, 21, 15, 39, 28, 20, 52, 35, 25, 65, 42, 30, 78, 49, 35, 91, 56,
        40, 104, 63, 45, 117, 70, 50, 130, 77, 55, 143, 84, 60, 156, 91, 65, 169, 98, 70,
        182, 105, 75, 195, 112, 80, 208, 3, 11, 17, 10, 16, 30, 17, 21, 43, 24, 26, 56,
        31, 31, 69, 38, 36, 82, 45, 41, 95, 52, 46, 108, 59, 51, 121, 66, 56, 134, 73,
        61, 147, 80, 66, 160, 87, 71, 173, 94, 76, 186, 101, 81, 199, 108, 86, 212, 115, 91,
        225, 6, 22, 34, 13, 27, 47, 20, 32, 60, 27, 37, 73, 34, 42, 86, 41, 47, 99,
        48, 52, 112, 55, 57, 125, 62, 62, 138, 69, 67, 151, 76, 72, 164, 83, 77, 177, 90,
        82, 190, 97, 87, 203, 104, 92, 216, 111, 97, 229, 118, 102, 242, 9, 33, 51, 16, 38,
        64, 23, 43, 77, 30, 48, 90, 37, 53, 103, 44, 58, 116, 51, 63, 129, 58, 68, 142,
        65, 73, 155, 72, 78, 168, 79, 83, 181, 86, 88, 194, 93, 93, 207, 100, 98, 220, 107,
        103, 233, 114, 108, 246, 121, 113, 3, 12, 44, 68, 19, 49, 81, 26, 54, 94, 33, 59,
        107, 40, 64, 120, 47, 69, 133, 54, 74, 146, 61, 79, 159, 68, 84, 172, 75, 89, 185,
        82, 94, 198, 89, 99, 211, 96, 104, 224, 103, 109, 237, 110, 114, 250, 117, 119, 7, 124,
        124, 20, 15, 55, 85, 22, 60, 98, 29, 65, 111, 36, 70, 124, 43, 75, 137, 50, 80,
        150, 57, 85, 163, 64, 90, 176, 71, 95, 189, 78, 100, 202, 85, 105, 215, 92, 110, 228,
        99, 115, 241, 106, 120, 254, 113, 125, 11, 120, 130, 24, 127, 135, 37, 18, 66, 102, 25,
        71, 115, 32, 76, 128, 39, 81, 141, 46, 86, 154, 53, 91, 167, 60, 96, 180, 67, 101,
        193, 74, 106, 206, 81, 111, 219, 88, 116, 232, 95, 121, 245, 102, 126, 2, 109, 131, 15,
        116, 136, 28, 123, 141, 41, 130, 146, 54, 21, 77, 119, 28, 82, 132, 35, 87, 145, 42,
        92, 158, 49, 97, 171, 56, 102, 184, 63, 107, 197, 70, 112, 210, 77, 117, 223, 84, 122,
        236, 91, 127, 249, 98, 132, 6, 105, 137, 19, 112, 142, 32, 119, 147, 45, 126, 152, 58,
        133, 157, 71, 24, 88, 136, 31, 93, 149, 38, 98, 162, 45, 103, 175, 52, 108, 188, 59,
        113, 201, 66, 118, 214, 73, 123, 227, 80, 128, 240, 87, 133, 253, 94, 138, 10, 101, 143,
        23, 108, 148, 36, 115, 153, 49, 122, 158, 62, 129, 163, 75, 136, 168, 88, 27, 99, 153,
        34, 104, 166, 41, 109, 179, 48, 114, 192, 55, 119, 205, 62, 124, 218, 69, 129, 231, 76,
        134, 244, 83, 139, 1, 90, 144, 14, 97, 149, 27, 104, 154, 40, 111, 159, 53, 118, 164,
        66, 125, 169, 79, 132, 174, 92, 139, 179, 105, 30, 110, 170, 37, 115, 183, 44, 120, 196,
        51, 125, 209, 58, 130, 222, 65, 135, 235, 72, 140, 248, 79, 145, 5, 86, 150, 18, 93,
        155, 31, 100, 160, 44, 107, 165, 57, 114, 170, 70, 121, 175, 83, 128, 180, 96, 135, 185,
        109, 142, 190, 122
    ]

    static func main() async {
        let expected = "acece099e7c4ad96"
        guard pinnedBytes.count == 574 else { print("REFUSE: embedded byte count"); exit(64) }
        guard let snapshot = ImmutableInputSnapshot(
                pinned: pinnedBytes, expectedBytes: 574,
                sha256Hex: "009889e24805044e676ce86f9d26ed3b8cd60e9a014d623ef4e0ef48ed451fa9") else {
            print("REFUSE: snapshot pin mismatch")
            exit(66)
        }
        let decoder = FFmpegSoftwareDecoder()
        let session = SessionID(uncheckedEpoch: 1)
        do {
            try await decoder.openSnapshot(snapshot, session: session)
        } catch {
            print("REFUSE: openSnapshot failed: \(error)")
            exit(67)
        }
        var digest: String?
        var sawOpened = false
        while let event = await decoder.nextEvent(session: session) {
            switch event {
            case .opened(let codec, let w, let h):
                sawOpened = true
                print("opened: codec=\(codec) \(w)x\(h)")
            case .frameDecoded(let frame):
                print("frame: \(frame.width)x\(frame.height) \(frame.pixelFormatName) key=\(frame.isKeyFrame)")
                digest = await decoder.frameDigest(handle: frame.handle, session: session)
                await decoder.releaseFrame(handle: frame.handle, session: session)
            case .endOfStream:
                print("endOfStream")
            case .interrupted(let s):
                print("interrupted: \(s)")
            case .failed(let code, let summary):
                print("failed: \(code) \(summary)")
            case .feedSaturated(let n):
                print("feedSaturated: \(n)")
            }
            if digest != nil { break } // first frame is the milestone
        }
        if let report = await decoder.closeAndReport(session: session) {
            print("closeReport: leakedHandles=\(report.leakedHandles.count) droppedPending=\(report.droppedPendingPackets) leaseTableLeaks=\(report.leaseTableLeaks.count) ledgerLeaks=\(report.ledgerLeaks.count)")
        }
        guard sawOpened, let d = digest else {
            print("GORAV_FIRST_FRAME_NO_FRAME")
            exit(70)
        }
        print("frame_digest_fnv1a64=\(d)")
        print("expected          =\(expected)")
        if d == expected {
            print("GORAV_FIRST_FRAME_PASS")
            exit(0)
        } else {
            print("GORAV_FIRST_FRAME_MISMATCH")
            exit(71)
        }
    }
}
