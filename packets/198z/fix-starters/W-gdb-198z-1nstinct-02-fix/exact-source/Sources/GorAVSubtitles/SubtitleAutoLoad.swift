import Foundation

/// R7 (arch-195b): external subtitle auto-load discovery. Given a playing
/// video's local path, finds sibling sidecar files: exact-basename matches
/// (movie.srt next to movie.mp4) and language-tagged matches (movie.en.srt).
/// Deterministic order: exact basename first, then tagged matches sorted by
/// tag. Unknown extensions are never returned (they fail at load time as
/// typed refusals via SubtitleTrack.load). Discovery only; no parsing here.
public enum SubtitleAutoLoad {

    public static let extensions: Set<String> = ["srt", "ass", "ssa"]

    public struct Candidate: Equatable, Sendable {
        public let path: String
        /// nil for an exact-basename match; otherwise the tag between the
        /// video basename and the extension (usually a language code).
        public let tag: String?
        public let format: String
        public init(path: String, tag: String?, format: String) {
            self.path = path
            self.tag = tag
            self.format = format
        }
    }

    /// Deterministic candidates for `videoPath`. Returns [] when the video
    /// path has no usable basename or the directory cannot be listed; an
    /// empty result is a fact (no sidecars), never an error.
    public static func discover(forVideoPath videoPath: String) -> [Candidate] {
        let ns = videoPath as NSString
        let dir = ns.deletingLastPathComponent
        let base = ns.deletingPathExtension as NSString
        let baseName = base.lastPathComponent
        guard !baseName.isEmpty else { return [] }
        let listDir = dir.isEmpty ? "." : dir
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: listDir) else { return [] }
        var exact: [Candidate] = []
        var tagged: [Candidate] = []
        for entry in entries {
            let e = entry as NSString
            let ext = e.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }
            let nameNoExt = e.deletingPathExtension
            let full = listDir == "." ? entry : (listDir as NSString).appendingPathComponent(entry)
            let format = ext == "ssa" ? "ass" : ext
            if nameNoExt == baseName {
                exact.append(Candidate(path: full, tag: nil, format: format))
            } else if nameNoExt.hasPrefix(baseName + ".") {
                let tag = String(nameNoExt.dropFirst(baseName.count + 1))
                guard !tag.isEmpty else { continue }
                tagged.append(Candidate(path: full, tag: tag, format: format))
            }
        }
        return exact.sorted { $0.path < $1.path } + tagged.sorted { $0.path < $1.path }
    }
}
