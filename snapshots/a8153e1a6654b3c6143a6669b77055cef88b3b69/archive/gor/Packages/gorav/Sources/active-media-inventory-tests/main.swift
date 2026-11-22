import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import GorAVCore
import GorAVFFmpegAdapter

@main struct ActiveInventoryChecks {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let pins=root.appendingPathComponent("fixtures")
        let fixture=pins.appendingPathComponent("active-inventory-chapters.mkv").path
        let sid=SessionID(uncheckedEpoch:6101), other=SessionID(uncheckedEpoch:6102)
        let video=FFmpegSoftwareDecoder()
        try video.pinLocalRoots([pins.path])
        precondition(video.activeMediaInventory(session:sid) == nil)
        do {
            try await video.open(source:SourceDescriptor(id:"/missing-inventory-fixture",kind:.local,seekable:true),session:sid)
            fatalError("missing source admitted")
        } catch { }
        precondition(video.activeMediaInventory(session:sid) == nil)
        try await video.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:sid)
        let first=video.activeMediaInventory(session:sid)!
        precondition(first.inventory.tracks.contains { $0.kind == .video && $0.codec == "mpeg4" })
        precondition(first.inventory.tracks.contains { $0.kind == .audio && $0.language == "eng" })
        precondition(first.inventory.chapters.count == 2)
        precondition(first.inventory.chapters[0].title == "Opening")
        precondition(first.inventory.metadata["title"] == "GorAV active inventory fixture")
        precondition(abs(first.inventory.durationSeconds! - 1) < 0.1)
        print("PASS actual active video context tracks/duration/tags/chapters")
        precondition(video.activeMediaInventory(session:other) == nil)
        for _ in 0..<100 { precondition(video.activeMediaInventory(session:sid,expected:first.identity) == first) }
        do {
            try await video.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:other)
            fatalError("busy open admitted")
        } catch { }
        precondition(video.activeMediaInventory(session:sid,expected:first.identity) == first)
        try await video.seek(toSeconds:0.5,session:sid)
        precondition(video.activeMediaInventory(session:sid,expected:first.identity) == nil)
        let seeked=video.activeMediaInventory(session:sid)!
        precondition(seeked.identity != first.identity && seeked.inventory == first.inventory)
        print("PASS stale revision fenced without reextract/reopen")
        _ = await video.closeAndReport(session:sid)
        precondition(video.activeMediaInventory(session:sid) == nil)
        try await video.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:other)
        precondition(video.activeMediaInventory(session:other,expected:seeked.identity) == nil)
        precondition(first.inventory.chapters[1].title == "Closing") // immutable detached value
        _ = await video.closeAndReport(session:other)
        print("PASS close/replacement invalidates old identity, detached values remain safe")
        let audio=FFmpegSoftwareAudioDecoder()
        try audio.pinLocalRoots([pins.path])
        try await audio.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:sid)
        let sound=audio.activeMediaInventory(session:sid)!
        precondition(sound.inventory.chapters == first.inventory.chapters)
        precondition(sound.inventory.metadata["title"] == first.inventory.metadata["title"])
        await audio.close(session:sid)
        precondition(audio.activeMediaInventory(session:sid) == nil)
        print("PASS active audio context has actual container inventory")

        // HTTP serves one real WAV. Count requests after initial open, then
        // prove snapshots add none. Initial provider range/probe traffic is not
        // confused with a separate inventory open.
        let dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let script=dir.appendingPathComponent("server.py"), portFile=dir.appendingPathComponent("port"), count=dir.appendingPathComponent("count")
        try """
        import http.server,sys,threading
        data=open(sys.argv[1],'rb').read()
        lock=threading.Lock(); n=0
        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                global n
                with lock:
                    n+=1
                    open(sys.argv[3],'w').write(str(n))
                self.send_response(200)
                self.send_header('Content-Length',str(len(data)))
                self.end_headers()
                self.wfile.write(data)
            def log_message(self,*a): pass
        s=http.server.ThreadingHTTPServer(('127.0.0.1',0),H)
        open(sys.argv[2],'w').write(str(s.server_address[1]))
        s.serve_forever()
        """.write(to:script,atomically:true,encoding:.utf8)
        let server=Process();server.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
        server.arguments=[script.path,pins.appendingPathComponent("tone-48k.wav").path,portFile.path,count.path]
        try server.run();defer { kill(server.processIdentifier, SIGKILL); server.waitUntilExit() }
        var port:String?
        for _ in 0..<100 {
            port=try? String(contentsOf:portFile,encoding:.utf8)
            if port != nil { break }
            try await Task.sleep(nanoseconds:20_000_000)
        }
        guard let port else { fatalError("HTTP fixture server not ready") }
        let remote=FFmpegSoftwareAudioDecoder()
        remote.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:2)
        try await remote.open(source:SourceDescriptor(id:"http://127.0.0.1:\(port)/tone.wav",kind:.remote,seekable:false),session:sid)
        let before=try String(contentsOf:count,encoding:.utf8)
        let cached=remote.activeMediaInventory(session:sid)!
        for _ in 0..<100 { precondition(remote.activeMediaInventory(session:sid,expected:cached.identity) == cached) }
        let after=try String(contentsOf:count,encoding:.utf8)
        precondition(before == after && Int(before)! > 0)
        await remote.close(session:sid)
        precondition(remote.activeMediaInventory(session:sid) == nil)
        print("PASS HTTP snapshots use original active context, zero additional requests")
        print("ALL ACTIVE MEDIA INVENTORY CHECKS PASS (not track selection/native UI)")
    }
}
