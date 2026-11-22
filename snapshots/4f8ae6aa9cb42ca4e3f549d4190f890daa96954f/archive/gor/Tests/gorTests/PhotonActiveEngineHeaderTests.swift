import XCTest
@testable import gor

final class PhotonActiveEngineHeaderTests:XCTestCase {
    func testMetadataNeverChangesVisibleRows() {
        let rows=["photon\tphoton sdr","sharp\tA\tB","grain\t"]
        for engine:String? in ["mpv","gorav","other",nil] {
            for identity:String? in ["abcdef0","bad\nrow",nil] {
                for reason:String? in ["decoder unavailable","bad\nrow\t‖ value",nil] {
                    XCTAssertEqual(PhotonActiveEngineHeader.lines(rows,activeEngine:engine,sourceIdentity:identity,fallbackReason:reason),rows)
                }
            }
        }
    }
    func testDoesNotCreateVisibleContent() {
        XCTAssertEqual(PhotonActiveEngineHeader.lines([],activeEngine:"gorav",sourceIdentity:"abcdef0"),[])
        XCTAssertEqual(PhotonActiveEngineHeader.lines(["sharp\tx"],activeEngine:"mpv",sourceIdentity:"abcdef0"),["sharp\tx"])
    }
}
