import Foundation
import GorAVCore
#if !PORTABLE_INTENT_TEST
import GorAVPlaybackCore
#endif

@MainActor final class Host: OpenIntentHost {
    enum Call: Equatable { case local(String), routed(String, OpenURLRoute, String?) }
    var calls: [Call] = []
    var failLocal = false
    enum Failure: Error { case admission }
    func openIntentLocal(path: String) async throws {
        calls.append(.local(path))
        if failLocal { throw Failure.admission }
    }
    func openIntentRouted(input: String, route: OpenURLRoute, selectedFilename: String?) async throws {
        calls.append(.routed(input, route, selectedFilename))
    }
}

@main enum DispatchTests {
    @MainActor static func main() async throws {
        var count = 0
        func expect(_ ok: Bool) { count += 1; precondition(ok, "dispatch assertion \(count)") }
        let cases: [(String, Host.Call)] = [
            ("/fixture/a.mp4", .local("/fixture/a.mp4")),
            ("file:///fixture/a%20b.mkv", .local("/fixture/a b.mkv")),
            ("/fixture/a.PNG", .local("/fixture/a.PNG")),
            ("file:///fixture/a.torrent", .routed("/fixture/a.torrent", .needsWebTorrentBridge(subject: "/fixture/a.torrent"), "chosen")),
            ("https://example.test/a.srt", .routed("https://example.test/a.srt", .directRemote(id: "https://example.test/a.srt", seekable: true), "chosen")),
            ("https://transfer.it/t/abc", .routed("https://transfer.it/t/abc", .needsTransferResolver, "chosen")),
            ("https://mega.nz/file/a#key", .routed("https://mega.nz/file/a#key", .needsMegaResolver, "chosen")),
            ("ftp://example.test/a", .routed("ftp://example.test/a", .refused(.schemeNotAdmitted), "chosen"))
        ]
        for (input, wanted) in cases {
            let host = Host()
            try await OpenIntentDispatch.open(input, selectedFilename: "chosen", on: host)
            expect(host.calls == [wanted])
        }
        let refused: [(String, OpenIntentDispatchError)] = [
            ("/fixture/a.srt", .unsupportedLocalKind(.subtitle)),
            ("/fixture/a.woff2", .unsupportedLocalKind(.font)),
            ("file://remote/a.mp4", .invalidInput(.nonlocalFileURL)),
            ("", .invalidInput(.emptyInput))
        ]
        for (input, wanted) in refused {
            let host = Host()
            do { try await OpenIntentDispatch.open(input, on: host); expect(false) }
            catch let error as OpenIntentDispatchError { expect(error == wanted) }
            expect(host.calls.isEmpty)
        }
        let denied = Host(); denied.failLocal = true
        do { try await OpenIntentDispatch.open("/fixture/a.mp4", on: denied); expect(false) }
        catch Host.Failure.admission { expect(true) }
        expect(denied.calls == [.local("/fixture/a.mp4")]) // no remote retry after host refusal
        print("OpenIntentDispatch \(count)/\(count) PASS")
    }
}
