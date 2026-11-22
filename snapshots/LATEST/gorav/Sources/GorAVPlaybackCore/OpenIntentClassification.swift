import Foundation
import GorAVCore

/// Source-only classification, not admission or an executor. The host still
/// owns existence checks, current-session policy, side effects and batching.
public enum OpenIntent: Equatable, Sendable {
    case local(path: String, kind: LocalKind)
    /// Preserve OpenURLRouter's contract, including typed refusals. In the
    /// embedded caller only local media uses open(path:); remote intents use
    /// open(url:) and may require external preparation before playback.
    case routed(OpenURLRoute)
    case refused(Reason)

    public enum LocalKind: String, Equatable, Sendable {
        case font, subtitle, torrent, image, media
    }
    public enum Reason: String, Equatable, Sendable {
        case emptyInput, malformedFileURL, nonlocalFileURL
    }
}

public enum OpenIntentClassification {
    /// Absolute paths are literal filesystem paths: '?' and '#' are filename
    /// characters here. File URLs are decoded once; remote URL strings remain
    /// untouched for the existing router. No I/O and no UI/runtime mutation.
    public static func classify(_ input: String) -> OpenIntent {
        guard !input.isEmpty else { return .refused(.emptyInput) }
        if input.hasPrefix("/"), !input.hasPrefix("//") {
            return local(input)
        }
        if input.prefix(5).lowercased() == "file:" {
            guard let url = URLComponents(string: input),
                  url.scheme?.lowercased() == "file", url.path.hasPrefix("/") else {
                return .refused(.malformedFileURL)
            }
            guard url.host == nil || url.host == "" || url.host?.lowercased() == "localhost",
                  url.user == nil, url.password == nil, url.port == nil else {
                return .refused(.nonlocalFileURL)
            }
            return local(url.path)
        }
        return .routed(OpenURLRouter.route(input))
    }

    private static func local(_ path: String) -> OpenIntent {
        // Extension groups are a historical DragDropHandler reference only:
        // instinct 94ee671d, archive/gor/Sources/gor/gor/DragDropHandler.swift.
        // This is not evidence of current gor parity or host integration.
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        let kind: OpenIntent.LocalKind
        switch ext {
        case "ttf", "otf", "woff", "woff2": kind = .font
        case "srt", "ass", "ssa", "vtt", "sub": kind = .subtitle
        case "torrent": kind = .torrent
        case "jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif",
             "ico", "heic", "heif", "avif": kind = .image
        default: kind = .media
        }
        return .local(path: path, kind: kind)
    }
}
