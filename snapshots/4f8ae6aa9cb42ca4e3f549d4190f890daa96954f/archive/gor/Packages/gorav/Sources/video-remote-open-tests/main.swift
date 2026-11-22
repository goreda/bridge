import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
import GorAVCore
import GorAVFFmpegAdapter

@main struct VideoRemoteOpenChecks {
    static func main() async throws {
        let root=URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let fixture=root.appendingPathComponent("fixtures/clip-bbb-10s.mov")
        let dir=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
        let py=dir.appendingPathComponent("server.py"),portFile=dir.appendingPathComponent("port"),countFile=dir.appendingPathComponent("count")
        try """
        import http.server,sys,time,threading
        data=open(sys.argv[1],'rb').read(); lock=threading.Lock(); count=0
        class H(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                global count
                with lock:
                    count+=1
                    open(sys.argv[3],'w').write(str(count))
                if self.path.startswith('/stall'):
                    time.sleep(5); return
                if self.headers.get('X-GorAV-Test')!='yes' or 'session=abc' not in (self.headers.get('Cookie') or ''):
                    self.send_response(403);self.end_headers();return
                start=0;end=len(data)-1
                if self.headers.get('Range','').startswith('bytes='):
                    span=self.headers['Range'][6:].split('-')
                    start=int(span[0] or 0)
                    if span[1]:end=min(end,int(span[1]))
                    self.send_response(206)
                    self.send_header('Content-Range',f'bytes {start}-{end}/{len(data)}')
                else:self.send_response(200)
                self.send_header('Content-Length',str(end-start+1))
                self.send_header('Accept-Ranges','bytes');self.end_headers()
                self.wfile.write(data[start:end+1])
            def log_message(self,*a):pass
        s=http.server.ThreadingHTTPServer(('127.0.0.1',0),H)
        open(sys.argv[2],'w').write(str(s.server_address[1]));s.serve_forever()
        """.write(to:py,atomically:true,encoding:.utf8)
        let server=Process();server.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
        server.arguments=[py.path,fixture.path,portFile.path,countFile.path]
        try server.run();defer {kill(server.processIdentifier, SIGKILL);server.waitUntilExit()}
        var port:String?
        for _ in 0..<100 {
            port=try? String(contentsOf:portFile,encoding:.utf8)
            if port != nil {break};try await Task.sleep(nanoseconds:20_000_000)
        }
        guard let port else {fatalError("fixture server not ready")}
        let base="http://127.0.0.1:\(port)"
        func source(_ path:String) -> SourceDescriptor {SourceDescriptor(id:base+path,kind:.remote,seekable:true)}
        let options=SourceOpenOptions(headers:["X-GorAV-Test":"yes"],cookies:["session":"abc"],openDeadlineSeconds:2)
        let video=FFmpegSoftwareDecoder();video.remoteOpenOptions=options
        let sid=SessionID(uncheckedEpoch:6201)
        try await video.open(source:source("/film.mov"),session:sid)
        precondition(video.activeMediaInventory(session:sid)?.inventory.tracks.count == 2)
        // Invalid options for a rejected busy reopen must not touch live fence.
        video.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:.nan)
        do {try await video.open(source:source("/film.mov"),session:SessionID(uncheckedEpoch:6202));fatalError("busy open admitted")} catch { }
        precondition(video.activeMediaInventory(session:sid) != nil)
        _ = await video.closeAndReport(session:sid)
        print("PASS actual video HTTP headers/cookies and busy-open isolation")
        let invalid=FFmpegSoftwareDecoder()
        let before=(try? String(contentsOf:countFile,encoding:.utf8)) ?? "0"
        for (n,opts) in [SourceOpenOptions(headers:["X":"yes\r\nInjected:x"]),SourceOpenOptions(openDeadlineSeconds:0),SourceOpenOptions(openDeadlineSeconds:.infinity)].enumerated() {
            invalid.remoteOpenOptions=opts
            do {try await invalid.open(source:source("/film.mov"),session:SessionID(uncheckedEpoch:UInt64(6210+n)));fatalError("invalid options admitted")}
            catch {precondition(String(describing:error).contains("invalid remote open options"))}
        }
        precondition(((try? String(contentsOf:countFile,encoding:.utf8)) ?? "0") == before)
        print("PASS typed option validation before any HTTP access")
        let deadline=FFmpegSoftwareDecoder()
        deadline.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:0.1)
        let began=ProcessInfo.processInfo.systemUptime
        do {try await deadline.open(source:source("/stall"),session:SessionID(uncheckedEpoch:6230));fatalError("deadline did not abort")}
        catch {precondition(String(describing:error).contains("deadline exceeded"))}
        precondition(ProcessInfo.processInfo.systemUptime-began < 3)
        print("PASS deadline interrupts actual URL open before response headers")
        let canceled=FFmpegSoftwareDecoder()
        canceled.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:2)
        let cancelSID=SessionID(uncheckedEpoch:6240)
        let stalledSource=source("/stall")
        let task=Task.detached {try await canceled.open(source:stalledSource,session:cancelSID)}
        try await Task.sleep(nanoseconds:100_000_000)
        canceled.requestInterrupt(session:cancelSID)
        do {try await task.value;fatalError("cancel did not abort")}
        catch {precondition(String(describing:error).contains("interrupted"))}
        print("PASS cancellation interrupts actual remote open")
        let local=FFmpegSoftwareDecoder()
        try local.pinLocalRoots([root.appendingPathComponent("fixtures").path])
        local.remoteOpenOptions=SourceOpenOptions(openDeadlineSeconds:.nan)
        let localSID=SessionID(uncheckedEpoch:6250)
        try await local.open(source:SourceDescriptor(id:fixture.path,kind:.local,seekable:true),session:localSID)
        _ = await local.closeAndReport(session:localSID)
        print("PASS local path ignores remote-only options")
        print("ALL VIDEO REMOTE OPEN CHECKS PASS (HTTP only, no native/TLS claim)")
    }
}
