import XCTest
@testable import gor

/// T4 M1 gap 1: pins the gorav stream admission table. Each refusal reason
/// must keep the mpv load path untouched; only plain resolved http(s)
/// streams with no headers, no companions and no positive start offset may
/// open on the gorav engine.
final class GorAVStreamAdmissionTests: XCTestCase {

    private func admit(_ url: String, headers: Int = 0, subs: Int = 0,
                       start: Double? = nil, tunnel: Bool = false) -> Result<String, GorAVStreamAdmission.Refusal> {
        GorAVStreamAdmission.admit(url: url, headerCount: headers, subtitleCount: subs,
                                   startPos: start, needsTunnel: tunnel)
    }

    func testAdmitsResolvedStreamShapes() {
        for url in ["http://127.0.0.1:2222/0/file.mkv",      // wt_server torrent
                    "http://127.0.0.1:2223/stream",          // mega relay
                    "http://provider.example/live/ch1.m3u8", // IPTV channel
                    "https://archive.org/download/item/file.mp4",
                    "http://127.0.0.1:8787/relay/file.mp4"] { // transfer.it relay
            guard case .success(let admitted) = admit(url) else {
                XCTFail("expected admission for \(url)"); continue
            }
            XCTAssertEqual(admitted, url)
        }
    }

    func testRefusesNonHTTPSchemes() {
        for url in ["magnet:?xt=urn:btih:abc", "ftp://h/f", "/film/movie.mkv", "not a url"] {
            guard case .failure(let refusal) = admit(url) else {
                XCTFail("expected refusal for \(url)"); continue
            }
            XCTAssertEqual(refusal, .notRemoteHTTP)
        }
    }

    func testRefusesBlockedHost() {
        guard case .failure(let refusal) = admit("https://store-na.gofile.io/download/x", tunnel: true) else {
            return XCTFail("expected tunnel refusal")
        }
        XCTAssertEqual(refusal, .needsTunnel)
    }

    func testRefusesHeadersSubtitlesAndPositiveStart() {
        if case .failure(let r) = admit("https://cdn.example.com/v.mp4", headers: 1) {
            XCTAssertEqual(r, .carriesHeaders)
        } else { XCTFail("expected header refusal") }
        if case .failure(let r) = admit("https://cdn.example.com/v.mp4", subs: 2) {
            XCTAssertEqual(r, .carriesSubtitles)
        } else { XCTFail("expected subtitle refusal") }
        if case .failure(let r) = admit("https://cdn.example.com/v.mp4", start: 12.5) {
            XCTAssertEqual(r, .carriesStart)
        } else { XCTFail("expected start refusal") }
    }

    func testExplicitZeroStartAdmitted() {
        // start=0 is "from the beginning", gorav's default - not an offset.
        guard case .success = admit("http://127.0.0.1:2222/f", start: 0.0) else {
            return XCTFail("expected admission for explicit zero start")
        }
    }
}
