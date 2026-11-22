import Foundation
import GorAVCore

// R3 (arch-195l) witness: open(url:) classification for transfer.it, mega,
// torrent/magnet and generic admitted remotes; typed refusals; no URL
// content in reasons.

var passed = 0, failed = 0
func check(_ label: String, _ ok: Bool) { if ok { passed += 1 } else { failed += 1; print("FAIL \(label)") } }

// transfer.it
check("R1-transferit-share", OpenURLRouter.route("https://transfer.it/t/AbCdEf123")
      == .needsTransferResolver)
check("R2-transferit-subdomain", OpenURLRouter.route("https://www.transfer.it/t/xyz")
      == .refused(.transferLinkShape))

// mega
check("R3-mega-file", OpenURLRouter.route("https://mega.nz/file/AbC123#SecretKey") == .needsMegaResolver)
check("R4a-mega-folder", OpenURLRouter.route("https://mega.nz/folder/AbC#key") == .needsMegaResolver)
check("R4b-mega-conz-legacy", OpenURLRouter.route("https://mega.co.nz/#!abc!def") == .needsMegaResolver)
check("R5-mega-bare", OpenURLRouter.route("https://mega.nz/") == .refused(.megaLinkShape))

// torrent / magnet
check("R6-magnet-hex", OpenURLRouter.route("magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=x")
      == .needsWebTorrentBridge(subject: "0123456789abcdef0123456789abcdef01234567"))
check("R6b-magnet-hex-case", OpenURLRouter.route("magnet:?xt=urn:btih:0123456789ABCDEF0123456789ABCDEF01234567")
      == .needsWebTorrentBridge(subject: "0123456789abcdef0123456789abcdef01234567"))
check("R7-magnet-base32", OpenURLRouter.route("magnet:?xt=urn:btih:ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
      == .needsWebTorrentBridge(subject: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"))
check("R8-magnet-no-xt", OpenURLRouter.route("magnet:?dn=nohash") == .refused(.magnetMissingBtih))
check("R9-magnet-bad-hash", OpenURLRouter.route("magnet:?xt=urn:btih:0123") == .refused(.magnetBadInfoHash))
check("R10-torrent-url", OpenURLRouter.route("https://example.com/files/a.torrent?x=1")
      == .needsWebTorrentBridge(subject: "https://example.com/files/a.torrent?x=1"))
check("R10b-torrent-case", OpenURLRouter.route("https://example.com/A.TORRENT")
      == .needsWebTorrentBridge(subject: "https://example.com/A.TORRENT"))

// generic remote + refusals
check("R11-generic-https", OpenURLRouter.route("https://cdn.example.com/film.mkv")
      == .directRemote(id: "https://cdn.example.com/film.mkv", seekable: true))
check("R12-ftp-refused", OpenURLRouter.route("ftp://example.com/film.mkv") == .refused(.schemeNotAdmitted))
check("R13-unparseable", OpenURLRouter.route("not a url") == .refused(.unparseable))
check("R14-empty-host", OpenURLRouter.route("https:///path/file.mkv") == .refused(.emptyHost))
check("R15-userinfo-port", OpenURLRouter.route("https://user:secret@mega.nz:8443/file/a#k") == .needsMegaResolver)
check("R16-uppercase", OpenURLRouter.route("HTTPS://TRANSFER.IT/t/x")
      == .needsTransferResolver)

for value in ["https://transfer.it/s/old", "http://transfer.it/t/a", "https://transfer.it/t/%61", "https://transfer.it./t/a", "https://%74ransfer.it/t/a", "https://transfer.it/t/a//", "https://user:secret@transfer.it/t/a", "https://transfer.it:443/t/a", "https://transfer.it/t/a?secret=1", "https://transfer.it/t/a#secret"] {
    check("transfer invalid shape never raw media", OpenURLRouter.route(value) == .refused(.transferLinkShape))
}
check("transfer trailing slash valid", OpenURLRouter.route("https://transfer.it/t/a/") == .needsTransferResolver)
check("lookalike host remains generic", OpenURLRouter.route("https://transfer.it.example.invalid/t/a") == .directRemote(id: "https://transfer.it.example.invalid/t/a", seekable: true))
print("open-url-tests: \(passed) PASS, \(failed) FAIL")
exit(failed == 0 ? 0 : 1)
