import Foundation
/// Linux test stub: the real ThreeDDegradeProbe (relocated span inside ThreeDDegrade.swift, 195y G2) uses Darwin-only volume keys.
enum ThreeDDegradeProbe {
    static func noteWriteError(_ e: Error) {}
    static func takeDiskFull() -> Bool { false }
    static func headroomOK(at url: URL) -> Bool { true }
}
// (no-op: policy rows for the Linux test drivers)
