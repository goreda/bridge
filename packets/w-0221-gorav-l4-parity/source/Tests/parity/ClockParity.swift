import Foundation

struct DecisionVector: Decodable {
    struct Expected: Decodable { let kind: String; let seconds: Double? }
    let name: String
    let pts: Double
    let now: Double
    let duration: Double
    let maxWait: Double
    let expected: Expected
}
struct AnchorVector: Decodable {
    let name: String
    let media: Double
    let wall: Double
    let pts: Double
    let expected: Double
}
struct Corpus: Decodable {
    let schema: Int
    let decisionCases: [DecisionVector]
    let anchorCases: [AnchorVector]
}

@main struct ClockParity {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("one corpus path required") }
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        guard corpus.schema == 1, corpus.decisionCases.count == 24, corpus.anchorCases.count == 5 else {
            fatalError("unexpected fixture schema or vector count")
        }
        var failures = 0
        for v in corpus.decisionCases {
            let actual = AVSyncDecider(maxWaitSeconds: v.maxWait).decide(ptsSeconds: v.pts, nowSeconds: v.now, frameDuration: v.duration)
            let expected: FrameDecision
            switch v.expected.kind {
            case "drop": expected = .drop
            case "show": expected = .show
            case "wait": expected = .wait(v.expected.seconds!)
            default: fatalError("unknown fixture decision")
            }
            if actual != expected { failures += 1; print("FAIL decision \(v.name): \(actual) != \(expected)") }
        }
        for v in corpus.anchorCases {
            let actual = MediaWallAnchor(mediaSeconds: v.media, wallSeconds: v.wall).scheduledWall(forMediaSeconds: v.pts)
            if actual != v.expected { failures += 1; print("FAIL anchor \(v.name): \(actual) != \(v.expected)") }
        }
        print("CLOCK_PARITY decisions=\(corpus.decisionCases.count) anchors=\(corpus.anchorCases.count) failures=\(failures)")
        if failures != 0 { exit(1) }
    }
}
