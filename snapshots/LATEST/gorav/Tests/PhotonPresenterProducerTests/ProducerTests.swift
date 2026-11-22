import XCTest
@testable import GorAVPlaybackCore

final class ProducerTests:XCTestCase {
    func testLuaRuntimeDefaultsAndEpochReset() throws {
        var p=PhotonPresenterProducer()
        let a=try p.snapshot(epoch:1,sourceWidth:1920,sourceHeight:1080,outputWidth:1920,outputHeight:1080,position:1,now:10)
        XCTAssertEqual(a.sharp.count,19);XCTAssertEqual(a.grain.count,29)
        XCTAssertEqual(a.sharp["PHOTON_SHARP_AMOUNT"],0.312)
        XCTAssertEqual(a.sharp["PHOTON_SHARP_FACTOR_RENDERED"],1)
        XCTAssertEqual(a.sharp["PHOTON_SHARP_FRAME_PEAK"],-1)
        XCTAssertEqual(a.grain["BASE_STRENGTH"],6)
        XCTAssertEqual(a.grain["GRAIN_SIZE"]!,0.8,accuracy:0.0001)
        XCTAssertFalse(a.hasSceneFeed)
        XCTAssertEqual(a.grain["GR_SIZE_COEFFICIENT"],0.8)
        let b=try p.snapshot(epoch:1,sourceWidth:1920,sourceHeight:1080,outputWidth:1920,outputHeight:1080,position:1,now:90)
        XCTAssertEqual(a.sharp,b.sharp,"redraw must not advance scene easing")
        XCTAssertEqual(a.grain,b.grain,"redraw must not change grain")
        XCTAssertEqual(a.token,b.token)
        let next=try p.snapshot(epoch:2,sourceWidth:1920,sourceHeight:1080,outputWidth:1920,outputHeight:1080,position:0,now:100)
        XCTAssertNotEqual(next.token,a.token)
        XCTAssertEqual(next.grain["GR_ANIM_BUCKET"],0)
        XCTAssertThrowsError(try p.sceneFeed(PhotonSceneFeed(),epoch:1,now:100,position:1))
    }
    func testClockFeedAndHonestTelemetry() throws {
        var p=PhotonPresenterProducer()
        let a=try p.snapshot(epoch:1,sourceWidth:1280,sourceHeight:720,outputWidth:1280,outputHeight:720,position:1,now:1)
        var feed=PhotonSceneFeed();feed.hasFeed=true;feed.fps=24
        try p.sceneFeed(feed,epoch:1,now:2,position:1)
        let b=try p.snapshot(epoch:1,sourceWidth:1280,sourceHeight:720,outputWidth:1280,outputHeight:720,position:2,now:2)
        XCTAssertTrue(b.hasSceneFeed)
        XCTAssertNotEqual(a.grain["GR_ANIM_BUCKET"],b.grain["GR_ANIM_BUCKET"])
        let rows=PhotonPresentedTelemetry(snapshot:a,frameSequence:7).rows
        XCTAssertTrue(rows[0].hasPrefix("photon\t"))
        XCTAssertTrue(rows[0].contains("no scene feed"))
        XCTAssertFalse(rows.joined().contains("nit"),"no brightness measurement invented")
        XCTAssertThrowsError(try p.snapshot(epoch:1,sourceWidth:0,sourceHeight:720,outputWidth:1,outputHeight:1,position:0,now:1))
    }
}
extension ProducerTests: @unchecked Sendable {}
