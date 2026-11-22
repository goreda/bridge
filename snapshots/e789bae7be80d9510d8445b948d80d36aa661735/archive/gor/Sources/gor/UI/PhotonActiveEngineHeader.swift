import Foundation

/// Preserve Photon display rows. Engine, build identity and fallback diagnostics
/// remain outside the measurement header. About/logs stay unchanged.
/// Kept as an identity adapter for callers compiled against the existing API.
enum PhotonActiveEngineHeader {
    static func lines(_ rows:[String],activeEngine:String?,sourceIdentity:String?,fallbackReason:String?=nil) -> [String] {
        rows
    }
}
