// Controlled MEGA ciphertext/download -> actual engine decoder. Not live-service.
import Foundation
#if os(Linux)
import Glibc
#endif
import GorAVCore
import GorAVFFmpegAdapter
import GorAVPlaybackCore
setbuf(stdout,nil)
let root=FileManager.default.currentDirectoryPath
let fixture=root+"/fixtures/mega-downloaded.wav"
let anchor=try Data(contentsOf:URL(fileURLWithPath:root+"/fixtures/archive-anchor.pcm"))
let decoder=FFmpegSoftwareAudioDecoder()
try decoder.pinLocalRoots([root+"/fixtures"])
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
var fnv:UInt64=14695981039346656037
for b in pcm {fnv=(fnv ^ UInt64(b)) &* 1099511628211}
let ok=opened && eof && !failed && anchor.count==176400 && pcm==anchor
print("\(ok ? "PASS" : "FAIL") controlled MEGA verified bytes -> actual PCM independent anchor bytes=\(pcm.count) chunks=\(chunks) eof=\(eof) fnv=\(String(fnv,radix:16))")
print("scope: local API fixture, full MEGAJS MAC-verified download, engine local-file decode; no live service or default coordinator claim")
exit(ok ? 0:1)
