import Foundation
import GorAVPlaybackCore
import GorAVFFmpegAdapter
import GorAVCore

// 195b-59: REAL software adapters and tracked local fixtures. Needs the pinned
// FFmpeg headers/libs. No hardware/device/native session acceptance is implied.
@main struct DecoderLifetimeChecks {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let fixture=root.appendingPathComponent("fixtures/clip-bbb-10s.mov").path
        let tone=root.appendingPathComponent("fixtures/tone-48k.wav").path
        let registry=DecoderInventoryStore()
        let sid=SessionID(uncheckedEpoch:901)
        let foreign=SessionID(uncheckedEpoch:902)
        let reopened=SessionID(uncheckedEpoch:903)
        var video:FFmpegSoftwareDecoder?=FFmpegSoftwareDecoder(decoderInventory:registry)
        try video!.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        do {
            try await video!.open(source:SourceDescriptor(id:"/missing-decoder-lifetime",kind:.local,seekable:true),session:sid)
            fatalError("missing video opened")
        } catch { }
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS failed video open registers nothing")
        try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:sid)
        let first=registry.activeSnapshots(session:sid.epoch)
        precondition(first.count == 1 && first[0].kind == .videoSoftware)
        precondition(first[0].sourceID?.hasPrefix("video:") == true && first[0].revisionAtOpen == 1)
        print("PASS real video open registers immutable opaque identity")
        do {
            try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:foreign)
            fatalError("busy video reopen admitted")
        } catch { }
        precondition(registry.snapshot(first[0].identity) != nil)
        _ = await video!.closeAndReport(session:foreign)
        precondition(registry.snapshot(first[0].identity) != nil)
        print("PASS failed reopen and foreign close preserve live registration")
        _ = await video!.closeAndReport(session:sid)
        precondition(registry.snapshot(first[0].identity) == nil)
        try await video!.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:reopened)
        let second=registry.activeSnapshots(session:reopened.epoch)
        precondition(second.count == 1 && second[0].identity != first[0].identity)
        precondition(second[0].sourceID != first[0].sourceID)
        print("PASS close/reopen never revives prior registration")
        video=nil
        precondition(registry.activeSnapshots(session:reopened.epoch).isEmpty)
        print("PASS abandoned real video deinit deregisters")
        var audio:FFmpegSoftwareAudioDecoder?=FFmpegSoftwareAudioDecoder(decoderInventory:registry)
        try audio!.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        do {
            try await audio!.open(source:SourceDescriptor(id:"/missing-audio-lifetime",kind:.local,seekable:true),session:sid)
            fatalError("missing audio opened")
        } catch { }
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS failed audio open registers nothing")
        try await audio!.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        let sound=registry.activeSnapshots(session:sid.epoch)
        precondition(sound.count == 1 && sound[0].kind == .audioSoftware)
        precondition(sound[0].sourceID != nil && sound[0].revisionAtOpen == 1)
        await audio!.close(session:foreign)
        precondition(registry.snapshot(sound[0].identity) != nil)
        await audio!.close(session:sid)
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS real audio lifetime/foreign close fence")
        try await audio!.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        audio=nil
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        print("PASS abandoned real audio deinit deregisters")
        registry.invalidateSession(sid.epoch)
        let stale=FFmpegSoftwareAudioDecoder(decoderInventory:registry)
        try stale.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        try await stale.open(source:SourceDescriptor(id:tone,kind:.local,seekable:true),session:sid)
        precondition(registry.activeSnapshots(session:sid.epoch).isEmpty)
        await stale.close(session:sid)
        print("PASS invalidated-session successful adapter open cannot revive metadata")
        print("ALL DECODER LIFETIME CHECKS PASS (software registry only)")
    }
}
