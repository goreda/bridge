// W-gdb-036 sidecar fixture rows for cue-output-tests.
// Replays kits/sidecar-fixtures/expected/*.json against the pinned product
// surface (product pin 2112af0d60df16c5473173b664903f76ce54173e):
//   SubtitleAutoLoad.discover(forVideoPath:) -> [Candidate]
//   SubtitleSidecarSession replaceSource / loadExactPrimary / select
// Row statuses in the tables: "pinned" asserts packet-pinned behaviour;
// "assumed"/"derived" rows are reported with their status tag so a
// divergence from the prose-pinned behaviour is visible in the output.
import Foundation
import GorAVSubtitles
import GorAVPlaybackCore

struct SidecarRowLog {
    var pass = 0
    var fail = 0
    mutating func row(_ id: String, _ status: String, _ got: String, _ want: String) {
        if got == want { pass += 1; print("ROW \(id) \(status.uppercased()) PASS") }
        else { fail += 1; print("ROW \(id) \(status.uppercased()) FAIL got \(got) want \(want)") }
    }
}

enum SidecarFixtureRows {
    /// Discovery rows call the real SubtitleAutoLoad.discover. Session rows
    /// use the real SubtitleSidecarSession; the success path of an async
    /// load needs a SubtitleTrack.Track value whose construction is NOT
    /// pinned in the packet, so those rows go through the loader seam in
    /// INTEGRATION.md (rows for refusal paths need no track value).
    @MainActor
    static func run(packPath: String) -> (pass: Int, fail: Int) {
        var log = SidecarRowLog()
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: packPath) else {
            print("ROW sidecar-fixtures/pack PINNED FAIL cannot list \(packPath)")
            return (0, 1)
        }
        for file in entries.sorted() where file.hasSuffix(".json") {
            guard let data = fm.contents(atPath: (packPath as NSString).appendingPathComponent(file)),
                  let table = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tree = table["tree"] as? String,
                  let video = table["video"] as? String,
                  let files = table["files"] as? [String] else { continue }
            let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("sidecar-fix-\(tree)")
            try? fm.removeItem(atPath: dir)
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            fm.createFile(atPath: (dir as NSString).appendingPathComponent(video),
                          contents: Data("placeholder\n".utf8))
            for name in files { // creation order is the table order; determinism row rescans
                let ext = (name as NSString).pathExtension.lowercased()
                let body = (ext == "ass" || ext == "ssa")
                    ? "[Events]\nDialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,fixture\n"
                    : "1\n00:00:01,000 --> 00:00:02,000\nfixture\n"
                fm.createFile(atPath: (dir as NSString).appendingPathComponent(name), contents: Data(body.utf8))
            }
            if let rn = table["rename"] as? [String: String], let from = rn["from"], let to = rn["to"] {
                try? fm.moveItem(atPath: (dir as NSString).appendingPathComponent(from),
                                 toPath: (dir as NSString).appendingPathComponent(to))
            }
            let videoPath = (dir as NSString).appendingPathComponent(video)

            // discovery order / tags / formats against the real discover()
            let candidates = SubtitleAutoLoad.discover(forVideoPath: videoPath)
            if let d = table["discovery"] as? [String: Any] {
                let status = d["status"] as? String ?? "pinned"
                let base = { (p: String) in (p as NSString).lastPathComponent }
                if let want = d["order"] as? [String] {
                    log.row("\(tree)/discovery.order", status, candidates.map { base($0.path) }.description, want.description)
                }
                if let want = d["tags"] as? [Any] {
                    let got: [Any] = candidates.map { $0.tag as Any? ?? NSNull() }
                    log.row("\(tree)/discovery.tags", status, got.description, want.description)
                }
                if let want = d["formats"] as? [String] {
                    log.row("\(tree)/discovery.formats", status, candidates.map { $0.format }.description, want.description)
                }
            }
            // determinism: a second scan must return the identical order
            let again = SubtitleAutoLoad.discover(forVideoPath: videoPath)
            log.row("\(tree)/discovery.determinism", "pinned",
                    again.map { $0.path }.description, candidates.map { $0.path }.description)

            // replaceSource refusal rows use the real session (no loader needed)
            if let cases = table["replaceSourceCases"] as? [[String: Any]] {
                for (i, rc) in cases.enumerated() where rc["sequence"] == nil {
                    // Skipped pending seam: the session close API is outside the
                    // pinned excerpt (INTEGRATION.md seam 3). Without it this row
                    // cannot reach the "closed" state, so it is reported as SKIP,
                    // never FAIL, until the integrator wires the close seam.
                    if rc["closeFirst"] as? Bool == true {
                        print("ROW \(tree)/replaceSource[\(i)] ASSUMED SKIP pending close seam (INTEGRATION.md seam 3)")
                        continue
                    }
                    let session = SubtitleSidecarSession(session: 1, emit: { _ in })
                    let path = (rc["path"] as? String ?? "").replacingOccurrences(of: "__TREE__", with: dir)
                    let got = session.replaceSource(path: path)
                    let gotS = got.map { "refused(\($0))" } ?? "nil"
                    let wantS: String
                    if let exp = rc["expect"] as? [String: String], let r = exp["refused"] {
                        wantS = "refused(\(r))"
                    } else { wantS = "nil" }
                    log.row("\(tree)/replaceSource[\(i)]", rc["status"] as? String ?? "pinned", gotS, wantS)
                }
            }
            // SEAM (see INTEGRATION.md): loadExactPrimary/select success paths
            // and staleCompletion fencing need an injectable loader returning
            // a SubtitleTrack.Track; Track construction is not pinned in the
            // packet. Wire rows t09/t01/t03/t08 select/autoSelect here once
            // the integrator confirms the Track fixture.
        }
        print("sidecar-fixture-rows: \(log.pass) PASS, \(log.fail) FAIL")
        return (log.pass, log.fail)
    }
}
