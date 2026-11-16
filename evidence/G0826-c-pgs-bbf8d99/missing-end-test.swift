import Foundation
// Missing-END behavior of the seam decoder (LabPGSDecoder), G0826 item 3.
let path = CommandLine.arguments[1]
let buf = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: path)))
let d = LabPGSDecoder(frameW: 640, frameH: 360)!
let rc = d.feed(buf)
var events: [String] = []
while let ev = d.nextEvent() { events.append("\(ev.type)") }
print("feed(complete-set-minus-END) rc=\(rc) events=\(events.count) (expect rc=true, 0 events: no END -> display set pending, never emitted)")
// The decoder stays usable: feed the SAME display set WITH its END segment.
let full = [UInt8](try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
let rc2 = d.feed(full)
var events2: [LabPGSEvent] = []
while let ev = d.nextEvent() { events2.append(ev) }
print("feed(full stream after) rc=\(rc2) events=\(events2.count) type=\(events2.first.map { "\($0.type)" } ?? "none") pts90k=\(events2.first?.pts90k ?? 0) (expect rc=true, 1 display)")
// Note: the pending acquisition-point state from the truncated feed was reset
// by the second feed's PCS (state 0x80 = acquisition point resets the epoch),
// so the second display set decodes cleanly on its own.
