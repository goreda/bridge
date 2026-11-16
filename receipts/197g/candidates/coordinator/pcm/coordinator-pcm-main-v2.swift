// Controlled transfer resolver/download -> actual engine decoder. Not live-service.
import Foundation
#if os(Linux)
import Glibc
#endif
import GorAVCore
import GorAVFFmpegAdapter
import GorAVPlaybackCore
setbuf(stdout,nil)
func runCoordinatorPCM() async throws -> Int32 {
let root=FileManager.default.currentDirectoryPath
let env=ProcessInfo.processInfo.environment
let prepared=try NodeSourcePreparation.prepare(url:"https://transfer.it/t/OWNEDHANDLE",selectedFilename:"owned.wav",nodeExecutable:env["M2_NODE"]!,script:env["M2_SOURCE_SCRIPT"]!,cacheRoot:env["M2_SOURCE_CACHE"]!)
let fixture=prepared.path
print("prepared local cache bytes=\(prepared.bytes) integrity=\(prepared.integrity)")
let anchor=try Data(contentsOf:URL(fileURLWithPath:env["M2_SOURCE_ANCHOR"]!))
let decoder=FFmpegSoftwareAudioDecoder()
try decoder.pinLocalRoots([env["M2_SOURCE_CACHE"]!])
let session=SessionID(uncheckedEpoch:201)
try await decoder.open(source:SourceDescriptor(id:fixture,kind:.local,seekable:true),session:session)
var pcm=Data(),eof=false,opened=false,failed=false,chunks=0
for _ in 0..<10000 {
 guard let event=await decoder.nextEvent(session:session) else {break}
 switch event {
 case .opened(_,let rate,let channels,_,_): opened=rate==44100 && channels==2
 case .pcm(let frame): pcm.append(contentsOf:frame.bytes);chunks+=1
 case .endOfStream: eof=true
 case .failed(let code,_): print("FAIL actual decoder code=\(code)");failed=true
 default: break
 }
 if eof || failed {break}
}
await decoder.close(session:session)
let cacheExistedThroughClose=FileManager.default.fileExists(atPath:prepared.path)
try prepared.release()
let cacheRemovedAfterClose = !FileManager.default.fileExists(atPath:prepared.path)
var fnv:UInt64=14695981039346656037
for b in pcm {fnv=(fnv ^ UInt64(b)) &* 1099511628211}
let ok=opened && eof && !failed && anchor.count==176400 && pcm==anchor && cacheExistedThroughClose && cacheRemovedAfterClose && prepared.bytes==176444 && prepared.integrity=="node-key-mac"
print("\(ok ? "PASS" : "FAIL") Swift process -> real controlled API -> node-key-MAC bytes -> actual PCM independent anchor bytes=\(pcm.count) chunks=\(chunks) eof=\(eof) fnv=\(String(fnv,radix:16))")
print("scope: local API fixture, bounded Node download, engine local-file decode; bounded child + actual local API + whole-file MAC + local decoder/cache lifetime; no live service or Darwin/default-host claim")
return ok ? 0:1
}
do { exit(try await runCoordinatorPCM()) }
catch let error as SourcePreparationError {
    if case .kind(let token, _) = error { print("FAIL source preparation typed refusal: \(token)") }
    exit(1)
}
catch {
    // Decoder/cache Foundation errors can contain private paths; never print.
    print("FAIL coordinator PCM fixture error (redacted)")
    exit(1)
}
