import Foundation
import GorAVCore

public enum OpenIntentDispatchError: Error, Equatable {
    case invalidInput(OpenIntent.Reason)
    case unsupportedLocalKind(OpenIntent.LocalKind)
}

/// The host retains its normal session admission and lifetime checks. The
/// dispatcher does not stop a torrent, replace a session, or append a playlist.
@MainActor public protocol OpenIntentHost: AnyObject {
    func openIntentLocal(path: String) async throws
    func openIntentRouted(input: String, route: OpenURLRoute, selectedFilename: String?) async throws
}

public enum OpenIntentDispatch {
    @MainActor public static func open(_ input: String, selectedFilename: String? = nil,
                                      on host: any OpenIntentHost) async throws {
        switch OpenIntentClassification.classify(input) {
        case .local(let path, let kind):
            switch kind {
            case .media, .image:
                try await host.openIntentLocal(path: path)
            case .torrent:
                // Bridge remains the existing host's responsibility. Never
                // send a torrent to the media decoder as an ordinary file.
                try await host.openIntentRouted(input: path, route: OpenURLRouter.route(path),
                                                selectedFilename: selectedFilename)
            case .font, .subtitle:
                // No gorav font/subtitle drag executor is registered. Refuse
                // before opening a decoder, never invent side effects.
                throw OpenIntentDispatchError.unsupportedLocalKind(kind)
            }
        case .routed(let route):
            try await host.openIntentRouted(input: input, route: route, selectedFilename: selectedFilename)
        case .refused(let reason):
            throw OpenIntentDispatchError.invalidInput(reason)
        }
    }
}
