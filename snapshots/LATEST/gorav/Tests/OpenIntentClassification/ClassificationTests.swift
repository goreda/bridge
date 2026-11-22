import Foundation
import GorAVCore

@main enum ClassificationTests {
    static func main() {
        var checks = 0
        var failures = 0
        func check(_ input: String, _ expected: OpenIntent) {
            checks += 1
            if OpenIntentClassification.classify(input) != expected {
                failures += 1
                // Do not print arbitrary input, paths or URL/key content.
                print("FAIL classification case \(checks)")
            }
        }
        // Literal expected groups, independent of the production switch.
        let groups: [(OpenIntent.LocalKind, [String])] = [
            (.font, ["ttf", "otf", "woff", "woff2"]),
            (.subtitle, ["srt", "ass", "ssa", "vtt", "sub"]),
            (.torrent, ["torrent"]),
            (.image, ["jpg", "jpeg", "png", "gif", "bmp", "webp", "tiff", "tif", "ico", "heic", "heif", "avif"]),
            (.media, ["mp4", "mkv", "mp3", "flac", "txt", "unknown"])
        ]
        for (kind, extensions) in groups {
            for ext in extensions {
                for suffix in [ext, ext.uppercased()] {
                    let path = "/fixture/name." + suffix
                    check(path, .local(path: path, kind: kind))
                    check("file://" + path, .local(path: path, kind: kind))
                }
            }
        }
        check("/fixture/noextension", .local(path: "/fixture/noextension", kind: .media))
        check("/fixture/a%20b.srt", .local(path: "/fixture/a%20b.srt", kind: .subtitle))
        check("file:///fixture/a%20b.srt", .local(path: "/fixture/a b.srt", kind: .subtitle))
        check("file:///fixture/a%2520b.srt", .local(path: "/fixture/a%20b.srt", kind: .subtitle))
        check("FILE://LOCALHOST/fixture/a.SRT", .local(path: "/fixture/a.SRT", kind: .subtitle))
        check("file:/fixture/a.torrent", .local(path: "/fixture/a.torrent", kind: .torrent))
        check("file:///fixture/a.torrent?download=1#part", .local(path: "/fixture/a.torrent", kind: .torrent))
        check("/fixture/a.mp4#name.srt", .local(path: "/fixture/a.mp4#name.srt", kind: .subtitle))
        check("/fixture/a.srt?name.mp4", .local(path: "/fixture/a.srt?name.mp4", kind: .media))
        check("", .refused(.emptyInput))
        check("file:relative.srt", .refused(.malformedFileURL))
        check("file:///", .local(path: "/", kind: .media))
        for input in ["file://remote/fixture/a.srt", "file://user@localhost/a.srt", "file://localhost:99/a.srt"] {
            check(input, .refused(.nonlocalFileURL))
        }
        // Remote extension does not become a local side effect. Resolver and
        // bridge ownership comes from the current router, not suffix guesses.
        let remote: [(String, OpenURLRoute)] = [
            ("https://example.test/a.srt", .directRemote(id: "https://example.test/a.srt", seekable: true)),
            ("https://example.test/a.png", .directRemote(id: "https://example.test/a.png", seekable: true)),
            ("https://example.test/a.torrent?dl=1#x", .needsWebTorrentBridge(subject: "https://example.test/a.torrent?dl=1#x")),
            ("https://example.test/a.mp4?file=a.torrent", .directRemote(id: "https://example.test/a.mp4?file=a.torrent", seekable: true)),
            ("https://transfer.it/t/abc", .needsTransferResolver),
            ("https://mega.nz/file/abc#key", .needsMegaResolver),
            ("https://mega.nz./file/abc#key", .needsMegaResolver),
            ("MAGNET:?xt=urn:btih:0123456789012345678901234567890123456789", .needsWebTorrentBridge(subject: "0123456789012345678901234567890123456789")),
            ("magnet:?dn=a", .refused(.magnetMissingBtih)),
            ("ftp://example.test/a.mp4", .refused(.schemeNotAdmitted)),
            ("relative.srt", .refused(.unparseable)),
            ("//remote/fixture/a.srt", .refused(.unparseable))
        ]
        for (input, expected) in remote { check(input, .routed(expected)) }
        print("OpenIntentClassification: \(checks - failures)/\(checks) PASS")
        if failures > 0 { exit(1) }
    }
}
