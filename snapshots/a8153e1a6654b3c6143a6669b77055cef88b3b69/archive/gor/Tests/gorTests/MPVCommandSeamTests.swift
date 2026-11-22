import XCTest
@testable import gor

/// A012: every mpv wire line in MPVCommand.swift is built through MPVCommand.
/// These tests pin seam output so framing, escaping and request_id
/// correlation cannot drift back to hand interpolation.
final class MPVCommandSeamTests: XCTestCase {

    func testMakeKeepsEstablishedBytes() {
        // Single-key object: key order is not a variable.
        XCTAssertEqual(MPVCommand.make(["quit"]), "{\"command\":[\"quit\"]}")
        XCTAssertEqual(MPVCommand.make(["script-message-to","photon","set-live","true"]),
                       "{\"command\":[\"script-message-to\",\"photon\",\"set-live\",\"true\"]}")
        XCTAssertEqual(MPVCommand.make(["set_property","geometry","100x100+0+0"]),
                       "{\"command\":[\"set_property\",\"geometry\",\"100x100+0+0\"]}")
    }

    func testMakeEscapesInterpolationHazards() {
        // Quote, backslash and newline must never split a frame.
        for hazard in ["100x100+\"0", "C:\\media\\a.mp4", "a\nb"] {
            let line = MPVCommand.make(["set","geometry",hazard])
            let obj = try! JSONSerialization.jsonObject(with: line.data(using: .utf8)!) as? [String: Any]
            XCTAssertEqual((obj?["command"] as? [String])?.last, hazard)
        }
    }

    func testMakeRequestCarriesIdAndCommand() {
        // Two keys: parse, never string-compare (object key order is not API).
        let line = MPVCommand.makeRequest(["get_property","time-pos"], id: 42)
        let obj = try! JSONSerialization.jsonObject(with: line.data(using: .utf8)!) as? [String: Any]
        XCTAssertEqual(obj?["request_id"] as? Int, 42)
        XCTAssertEqual(obj?["command"] as? [String], ["get_property","time-pos"])
    }

    func testPreviewPayloadKeepsEstablishedFraming() {
        let payload = PlayerFitProtocol.previewPayload(geometry: "640x360+10+20", seekPercent: 12.5)
        let lines = payload.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, ["{\"command\":[\"seek\",12.5,\"absolute-percent\",\"keyframes\"]}",
                               "{\"command\":[\"set\",\"geometry\",\"640x360+10+20\"]}"])
        XCTAssertEqual(PlayerFitProtocol.previewPayload(geometry: "1x1+0+0", seekPercent: nil),
                       "{\"command\":[\"set\",\"geometry\",\"1x1+0+0\"]}\n")
    }
}
