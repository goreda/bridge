import Foundation
// Archived gor at c1431906: bce-MenuActions.swift:615 dispatches local
// .torrent selections; bce-TorrentManager.swift:180-186 decodes file URLs.
@main
struct LocalTorrentTests {
    static func main() {
        let vectors: [(String, OpenURLRoute)] = [
            ("/media/Film.TORRENT", .needsWebTorrentBridge(subject: "/media/Film.TORRENT")),
            ("file:///media/Film%20One.torrent", .needsWebTorrentBridge(subject: "/media/Film One.torrent")),
            ("FILE:///media/Film.TORRENT", .needsWebTorrentBridge(subject: "/media/Film.TORRENT")),
            ("MAGNET:?XT=URN:BTIH:0123456789ABCDEF0123456789ABCDEF01234567", .needsWebTorrentBridge(subject: "0123456789abcdef0123456789abcdef01234567")),
            ("https://example.invalid/Film.TORRENT?key=x", .needsWebTorrentBridge(subject: "https://example.invalid/Film.TORRENT?key=x")),
            ("file://server.invalid/media/film.torrent", .refused(.schemeNotAdmitted)),
            ("file://user:secret@localhost/media/film.torrent", .refused(.schemeNotAdmitted)),
            ("file://localhost/media/film.torrent", .needsWebTorrentBridge(subject: "/media/film.torrent")),
            ("ipfs://example.invalid/film.torrent", .refused(.schemeNotAdmitted)),
            ("file:///media/film.mp4", .refused(.schemeNotAdmitted)),
            ("https://user:secret@example.invalid/film.mp4", .directRemote(id: "https://user:secret@example.invalid/film.mp4", seekable: true))
        ]
        var failures = 0
        for (index, vector) in vectors.enumerated() {
            if OpenURLRouter.route(vector.0) != vector.1 {
                failures += 1; print("FAIL local/source classification vector \(index)")
            }
        }
        print("RESULT local/source \(vectors.count-failures)/\(vectors.count)")
        if failures != 0 { exit(1) }
    }
}
