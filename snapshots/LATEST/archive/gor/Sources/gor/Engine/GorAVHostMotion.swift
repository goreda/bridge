import Foundation

// Ported from gor-fit.lua at d8b677b. Points throughout; no mpv properties or IPC.
struct GorAVHostRect: Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var valid: Bool { [x, y, width, height].allSatisfy(\.isFinite) && width > 0 && height > 0 }
}

struct GorAVHostTransform: Equatable {
    var panX = 0.0
    var panY = 0.0
    // Log2 zoom, matching video-zoom. Presenter scale is pow(2, zoom).
    var zoom = 0.0
}

struct GorAVHostFit {
    // Usable screen coordinates in AppKit's bottom-left origin.
    static func frame(videoWidth: Double, videoHeight: Double, usable: GorAVHostRect,
                      chromeWidth: Double = 0, chromeTop: Double = 0) -> GorAVHostRect? {
        guard usable.valid, videoWidth.isFinite, videoHeight.isFinite,
              videoWidth > 0, videoHeight > 0, chromeWidth.isFinite, chromeTop.isFinite,
              chromeWidth >= 0, chromeTop >= 0 else { return nil }
        let pw: Double, ph: Double
        if videoWidth >= videoHeight {
            pw = max(1, floor(usable.width * 0.4 * max(1, sqrt(videoWidth / 1280))))
            ph = max(1, floor(pw * videoHeight / videoWidth))
        } else {
            ph = max(1, floor(usable.height * 0.9))
            pw = max(1, floor(ph * videoWidth / videoHeight))
        }
        var w = pw + chromeWidth, h = ph + chromeTop
        let scale = min(1, min(floor(usable.width) / w, floor(usable.height) / h))
        w = floor(w * scale); h = floor(h * scale)
        guard w.isFinite, h.isFinite, w >= 160, h >= 90,
              w > chromeWidth, h > chromeTop else { return nil }
        return GorAVHostRect(x: usable.x + floor((usable.width - w) / 2),
                             y: usable.y + floor((usable.height - h) / 2), width: w, height: h)
    }
}

private struct HostSpring {
    var value: Double
    var velocity = 0.0
    var target: Double
    var omega: Double
    var epsilon: Double
    var moving: Bool { value != target || velocity != 0 }
    mutating func retarget(_ next: Double) {
        guard next.isFinite else { return }
        target = next
        let d = value - target
        if d > 0 { velocity = max(velocity, -omega * d) }
        else if d < 0 { velocity = min(velocity, -omega * d) }
        else { velocity = 0 }
    }
    mutating func step(_ dt: Double) {
        let d = value - target, b = velocity + omega * d, e = exp(-omega * dt)
        let nd = (d + b * dt) * e
        velocity = (velocity - omega * b * dt) * e
        value = target + nd
        if abs(nd) < epsilon && abs(velocity) < epsilon * (omega == 16 ? 12 : 8) {
            value = target; velocity = 0
        }
    }
}

// Value state is testable without AppKit. The host supplies one monotonic clock.
struct GorAVHostMotion {
    private var frameSprings: [HostSpring] = []
    private var picture: [HostSpring] = [
        HostSpring(value: 0, target: 0, omega: 20, epsilon: 0.0005),
        HostSpring(value: 0, target: 0, omega: 20, epsilon: 0.0005),
        HostSpring(value: 0, target: 0, omega: 20, epsilon: 0.003)]
    private var holdVelocity = [0.0, 0, 0]
    private var directions = [0.0, 0, 0]
    private var holdAt: Double?
    private var lastTime: Double?
    private var suspendedZoom: Double?
    private(set) var isPiP = false
    var transform: GorAVHostTransform {
        GorAVHostTransform(panX: picture[0].value, panY: picture[1].value, zoom: picture[2].value)
    }
    var frame: GorAVHostRect? {
        guard frameSprings.count == 4 else { return nil }
        let p = frameSprings.map { $0.value }
        return GorAVHostRect(x: p[0], y: p[1], width: p[2], height: p[3])
    }
    var frameMoving: Bool { frameSprings.contains { $0.moving } }
    var busy: Bool { frameMoving || picture.contains { $0.moving } ||
        directions.contains { $0 != 0 } || holdVelocity.contains { $0 != 0 } }

    mutating func animateFrame(from: GorAVHostRect, to: GorAVHostRect) {
        guard from.valid, to.valid else { return }
        let a = [from.x, from.y, from.width, from.height]
        let b = [to.x, to.y, to.width, to.height]
        if frameSprings.isEmpty { frameSprings = a.map { HostSpring(value: $0, target: $0, omega: 16, epsilon: 0.5) } }
        for i in 0..<4 { frameSprings[i].retarget(b[i]) }
    }
    mutating func cancelFrame() { frameSprings.removeAll() }
    mutating func adopt(_ value: GorAVHostTransform) {
        guard [value.panX, value.panY, value.zoom].allSatisfy(\.isFinite) else { return }
        let a = [value.panX, value.panY, isPiP ? max(0, value.zoom) : value.zoom]
        for i in 0..<3 { picture[i].value = a[i]; picture[i].target = a[i]; picture[i].velocity = 0 }
        holdVelocity = [0, 0, 0]; directions = [0, 0, 0]; holdAt = nil
    }
    mutating func nudge(dx: Double = 0, dy: Double = 0, dz: Double = 0) {
        guard [dx, dy, dz].allSatisfy(\.isFinite) else { return }
        releaseHold(immediate: true)
        for (i, delta) in [dx * 0.05, dy * 0.05, dz * 0.1].enumerated() where delta != 0 {
            let lead = i == 2 ? 0.15 : 0.075
            var target = min(picture[i].value + lead, max(picture[i].value - lead, picture[i].target + delta))
            if i == 2 && isPiP { target = max(0, target) }
            picture[i].retarget(target)
        }
    }
    mutating func hold(dx: Double, dy: Double, dz: Double, now: Double) {
        guard now.isFinite, [dx, dy, dz].allSatisfy(\.isFinite),
              lastTime == nil || now >= lastTime!, holdAt == nil || now >= holdAt! else { return }
        directions = [dx, dy, dz].map { max(-1, min(1, $0)) }; holdAt = now
        if directions.contains(where: { $0 != 0 }) {
            for i in 0..<3 { picture[i].target = picture[i].value; picture[i].velocity = 0 }
        }
    }
    mutating func releaseHold(immediate: Bool = false) {
        directions = [0, 0, 0]; holdAt = nil
        if immediate { holdVelocity = [0, 0, 0] }
    }
    mutating func reset() {
        suspendedZoom = nil; releaseHold(immediate: true)
        for i in 0..<3 { picture[i].retarget(0) }
    }
    mutating func setPiP(_ active: Bool) {
        guard active != isPiP else { return }
        isPiP = active
        if active {
            suspendedZoom = picture[2].target
            setZoomImmediately(max(0, suspendedZoom!))
        } else if let saved = suspendedZoom {
            setZoomImmediately(saved); suspendedZoom = nil
        }
    }
    // Source replacement keeps the owner's frame but never inherits suspended old-file zoom.
    mutating func newPlayback() {
        suspendedZoom = nil; releaseHold(immediate: true)
        picture[2].target = picture[2].value; picture[2].velocity = 0
        if isPiP { suspendedZoom = picture[2].value; setZoomImmediately(max(0, picture[2].value)) }
    }
    private mutating func setZoomImmediately(_ value: Double) {
        picture[2].value = value; picture[2].target = value; picture[2].velocity = 0
        holdVelocity[2] = 0; directions[2] = 0
    }
    mutating func tick(now: Double) {
        guard now.isFinite else { return }
        guard let previous = lastTime else { lastTime = now; return }
        guard now >= previous else { return }
        lastTime = now
        let dt = min(0.05, now - previous)
        for i in frameSprings.indices { frameSprings[i].step(dt) }
        if holdAt == nil || now - holdAt! > 0.6 { directions = [0, 0, 0] }
        let k = 1 - exp(-dt / 0.045)
        for i in 0..<3 {
            if directions[i] != 0 || holdVelocity[i] != 0 {
                holdVelocity[i] += (directions[i] * (i == 2 ? 1 : 0.6) - holdVelocity[i]) * k
                if directions[i] == 0 && abs(holdVelocity[i]) < picture[i].epsilon * 4 { holdVelocity[i] = 0 }
                let lo = i == 2 ? (isPiP ? 0.0 : -1.0) : -1.5, hi = i == 2 ? 4.0 : 1.5
                let next = picture[i].value + holdVelocity[i] * dt
                picture[i].value = max(lo, min(hi, next))
                if next < lo || next > hi { holdVelocity[i] = 0 }
                picture[i].target = picture[i].value; picture[i].velocity = 0
            } else { picture[i].step(dt) }
        }
    }
}
