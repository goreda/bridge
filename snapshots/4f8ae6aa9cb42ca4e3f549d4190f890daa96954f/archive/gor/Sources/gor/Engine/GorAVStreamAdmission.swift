// ================================================================
//  GorAVStreamAdmission.swift - pre-open stream admission for the gorav engine (T4 M1 gap 1)
//  Owns: deciding whether a playMedia URL may open on the gorav engine.
//  Contract: admission is PRE-OPEN only, mirroring PlayerBackendRoute: an
//  admitted URL goes to gorav, and a gorav-side typed refusal then never
//  replays on mpv; a refused URL falls through to the mpv load path
//  untouched. Owner-signed-off mpv behavior is unchanged on every refusal.
// ================================================================
import Foundation

enum GorAVStreamAdmission {
    enum Refusal: String, Error {
        case notRemoteHTTP = "not an http(s) stream URL"
        case needsTunnel = "blocked host: WARP tunnel is mpv-only"
        case carriesHeaders = "per-load cookie/gofile headers are mpv-only"
        case carriesSubtitles = "companion subtitles are mpv-only for streams"
        case carriesStart = "start offset is mpv-only for streams"
    }

    /// gorav opens only plain, already-resolved http(s) streams. Every gap-1
    /// source reaches playMedia in that form: wt_server torrent URLs (port
    /// 2222), the mega relay (port 2223), IPTV channel URLs, archive.org
    /// download URLs and the transfer.it relay. The owner's torrent app stays
    /// the resolver; gorav's own OpenURLRouter remains the authoritative
    /// classifier engine-side and typed-refuses anything outside its
    /// direct-remote class. Per-load headers, companion subtitles, a start
    /// offset and WARP-tunneled hosts have no gorav path yet and stay on mpv.
    static func admit(url: String, headerCount: Int, subtitleCount: Int, startPos: Double?, needsTunnel: Bool) -> Result<String, Refusal> {
        guard let c = URLComponents(string: url), let scheme = c.scheme?.lowercased(),
              scheme == "http" || scheme == "https", c.host != nil else { return .failure(.notRemoteHTTP) }
        guard !needsTunnel else { return .failure(.needsTunnel) }
        guard headerCount == 0 else { return .failure(.carriesHeaders) }
        guard subtitleCount == 0 else { return .failure(.carriesSubtitles) }
        if let startPos, startPos > 0 { return .failure(.carriesStart) } // explicit 0 is "from the beginning", gorav's default
        return .success(url)
    }
}
