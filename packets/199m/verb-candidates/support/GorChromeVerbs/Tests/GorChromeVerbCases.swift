import Foundation

// Shared by the Linux and Darwin mains. Command strings are the production call-site literals.
func gorCommand(_ json: String) -> [Any] {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let command = object["command"] as? [Any] else { return [] }
    return command
}

public func runGorChromeVerbCases() -> [String] {
    var failures: [String] = []
    func expect(_ condition: Bool, _ label: String) { if !condition { failures.append(label) } }

    // Current default refusal text at the host (documented, derived from the default branch).
    func expectDetail(_ json: String, _ expected: String) {
        let got = GorHostDefaultRefusal.detail(gorCommand(json))
        expect(got == expected, "host detail \(json) got \(got)")
    }
    expectDetail(#"{"command":["multiply","speed",1.1]}"#, "multiply")
    expectDetail(#"{"command":["set","speed",1.0]}"#, "set")
    expectDetail(#"{"command":["set_property","volume-max",200]}"#, "set_property volume-max")
    expectDetail(#"{"command":["screenshot","video"]}"#, "screenshot")

    // transport-speed
    let up = GorSpeedRequest.parse(gorCommand(#"{"command":["multiply","speed",1.1]}"#))
    let reset = GorSpeedRequest.parse(gorCommand(#"{"command":["set","speed",1.0]}"#))
    expect(up == GorSpeedRequest.multiply(1.1), "parse multiply")
    expect(reset == GorSpeedRequest.set(1.0), "parse set")
    expect(GorSpeedRequest.parse(gorCommand(#"{"command":["set","volume",1.0]}"#)) == nil, "other property is not speed")
    expect(GorSpeedRequest.parse(gorCommand(#"{"command":["multiply","speed"]}"#)) == nil, "missing value")
    if let up = up, let reset = reset {
        expect(GorSpeedVerb.resolve(up, currentSpeed: 1.0, capability: .none) == .refused(.engineUnsupported("rate control")), "speed default capability refuses")
        expect(GorSpeedVerb.resolve(up, currentSpeed: 1.0, capability: .supported) == .applied(speed: 1.0 * 1.1), "speed multiply applies")
        expect(GorSpeedVerb.resolve(up, currentSpeed: nil, capability: .supported) == .refused(.currentValueUnknown), "multiply without current is unknown, not 1")
        expect(GorSpeedVerb.resolve(reset, currentSpeed: nil, capability: .supported) == .applied(speed: 1.0), "set needs no current")
    }
    let limits = GorSpeedLimits.proposed
    expect(GorSpeedVerb.resolve(.set(0.01), currentSpeed: nil, capability: .supported) == .applied(speed: 0.01), "lower bound inclusive")
    expect(GorSpeedVerb.resolve(.set(100), currentSpeed: nil, capability: .supported) == .applied(speed: 100), "upper bound inclusive")
    expect(GorSpeedVerb.resolve(.set(0.0099), currentSpeed: nil, capability: .supported) == .refused(.outOfRange(lower: limits.lower, upper: limits.upper)), "below lower refused")
    expect(GorSpeedVerb.resolve(.set(100.01), currentSpeed: nil, capability: .supported) == .refused(.outOfRange(lower: limits.lower, upper: limits.upper)), "above upper refused")
    expect(GorSpeedVerb.resolve(.set(0), currentSpeed: nil, capability: .supported) == .refused(.nonPositive), "zero refused")
    expect(GorSpeedVerb.resolve(.set(-1), currentSpeed: nil, capability: .supported) == .refused(.nonPositive), "negative refused")
    expect(GorSpeedVerb.resolve(.set(Double.nan), currentSpeed: nil, capability: .supported) == .refused(.nonFinite), "nan refused")
    expect(GorSpeedVerb.resolve(.multiply(Double.infinity), currentSpeed: 1, capability: .supported) == .refused(.nonFinite), "infinity refused")
    expect(GorSpeedVerb.resolve(.multiply(2), currentSpeed: 60, capability: .supported) == .refused(.outOfRange(lower: limits.lower, upper: limits.upper)), "multiply past upper refused")
    var nanParsedAsNaN = true
    if let parsed = GorSpeedRequest.parse(gorCommand(#"{"command":["multiply","speed","nan"]}"#)) {
        if case .multiply(let v) = parsed { nanParsedAsNaN = v.isNaN } else { nanParsedAsNaN = false }
    }
    expect(nanParsedAsNaN, "string nan parses to nan or nil")

    // audio-boost
    let boost = GorVolumeBoostRequest.parse(gorCommand(#"{"command":["set_property","volume-max",200]}"#))
    expect(boost == GorVolumeBoostRequest(volumeMaxPercent: 200), "parse volume-max")
    expect(GorVolumeBoostRequest.parse(gorCommand(#"{"command":["set_property","volume",200]}"#)) == nil, "volume is not volume-max")
    expect(GorVolumeBoostRequest.parse(gorCommand(#"{"command":["add","volume",10]}"#)) == nil, "add volume stays with the volume verb")
    if let boost = boost {
        expect(GorBoostVerb.resolve(boost, capability: .unknown) == .refused(.engineHeadroomUnknown), "unknown headroom refuses")
        expect(GorBoostVerb.resolve(boost, capability: .unityOnly) == .refused(.engineUnsupported("gain above unity")), "unity-only refuses")
        expect(GorBoostVerb.resolve(boost, capability: .boosted(maxLinear: 2)) == .applied(maxLinear: 2), "boost 200 on 2.0 headroom applies")
        expect(GorBoostVerb.resolve(boost, capability: .boosted(maxLinear: 1.5)) == .refused(.outOfRange(lower: 100, upper: 150)), "headroom below request refuses")
        expect(GorBoostVerb.resolve(boost, capability: .boosted(maxLinear: 0.5)) == .refused(.engineHeadroomUnknown), "headroom below unity is not usable")
    }
    expect(GorBoostVerb.resolve(GorVolumeBoostRequest(volumeMaxPercent: 100), capability: .boosted(maxLinear: 2)) == .applied(maxLinear: 1), "unity applies")
    expect(GorBoostVerb.resolve(GorVolumeBoostRequest(volumeMaxPercent: 99.9), capability: .boosted(maxLinear: 2)) == .refused(.outOfRange(lower: 100, upper: 200)), "below unity refused")
    expect(GorBoostVerb.resolve(GorVolumeBoostRequest(volumeMaxPercent: 200.1), capability: .boosted(maxLinear: 5)) == .refused(.outOfRange(lower: 100, upper: 200)), "above interface ceiling refused")
    expect(GorBoostVerb.resolve(GorVolumeBoostRequest(volumeMaxPercent: Double.nan), capability: .boosted(maxLinear: 2)) == .refused(.nonFinite), "nan refused")

    // capture-screenshot
    let modes = ["subtitles", "video", "window"]
    var all: [GorScreenshotRequest] = []
    for m in modes {
        if let r = GorScreenshotRequest.parse(gorCommand("{\"command\":[\"screenshot\",\"\(m)\"]}")) { all.append(r) }
    }
    expect(all.map { $0.mode } == [.subtitles, .video, .window], "parse three modes")
    expect(GorScreenshotRequest.parse(gorCommand(#"{"command":["screenshot","bogus"]}"#)) == nil, "unknown mode is not parsed")
    expect(GorScreenshotRequest.parse(gorCommand(#"{"command":["screenshot-to-file","x"]}"#)) == nil, "screenshot-to-file is a different verb")
    for r in all {
        expect(GorScreenshotVerb.resolve(r, destination: "/x/a.png", capabilities: .currentDefault, frameAvailable: true) == .refused(.notOpen), "default capabilities refuse \(r.mode)")
    }
    let full = GorScreenshotCapabilities(isOpen: true, frameTap: true, subtitleComposite: true, windowCapture: true)
    for r in all {
        expect(GorScreenshotVerb.resolve(r, destination: "/x/a.png", capabilities: full, frameAvailable: true) == .capture(mode: r.mode, destination: "/x/a.png"), "full capabilities capture \(r.mode)")
        expect(GorScreenshotVerb.resolve(r, destination: nil, capabilities: full, frameAvailable: true) == .refused(.destinationUnspecified), "nil destination refused \(r.mode)")
        expect(GorScreenshotVerb.resolve(r, destination: "", capabilities: full, frameAvailable: true) == .refused(.destinationUnspecified), "empty destination refused \(r.mode)")
        expect(GorScreenshotVerb.resolve(r, destination: "/x/a.png", capabilities: full, frameAvailable: false) == .refused(.noFrame), "no frame refused \(r.mode)")
    }
    let tapOnly = GorScreenshotCapabilities(isOpen: true, frameTap: true, subtitleComposite: false, windowCapture: false)
    expect(GorScreenshotVerb.resolve(GorScreenshotRequest(mode: .video), destination: "/x/a.png", capabilities: tapOnly, frameAvailable: true) == .capture(mode: .video, destination: "/x/a.png"), "video works on frame tap alone")
    expect(GorScreenshotVerb.resolve(GorScreenshotRequest(mode: .subtitles), destination: "/x/a.png", capabilities: tapOnly, frameAvailable: true) == .refused(.modeUnsupported("subtitles")), "subtitles needs composite")
    expect(GorScreenshotVerb.resolve(GorScreenshotRequest(mode: .window), destination: "/x/a.png", capabilities: tapOnly, frameAvailable: true) == .refused(.modeUnsupported("window")), "window needs window capture")
    let noTap = GorScreenshotCapabilities(isOpen: true, frameTap: false, subtitleComposite: true, windowCapture: true)
    expect(GorScreenshotVerb.resolve(GorScreenshotRequest(mode: .video), destination: "/x/a.png", capabilities: noTap, frameAvailable: true) == .refused(.engineUnsupported("frame tap")), "video without tap refused")
    expect(GorScreenshotVerb.resolve(GorScreenshotRequest(mode: .subtitles), destination: "/x/a.png", capabilities: noTap, frameAvailable: true) == .refused(.engineUnsupported("frame tap")), "subtitles without tap refused")
    return failures
}
