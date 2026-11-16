import Foundation
import GorAVCore
import GorAVPlaybackCore
#if os(Linux)
import Glibc
#endif
let env=ProcessInfo.processInfo.environment
let node=env["M2_NODE"]!,script=env["M2_SOURCE_FAKE"]!,root=env["M2_SOURCE_CACHE"]!
var failed=0
func check(_ label:String,_ ok:Bool){print("\(ok ? "PASS":"FAIL") \(label)");if !ok{failed+=1}}
check("share explicit prepare",OpenURLRouter.route("https://transfer.it/t/owned") == .needsTransferResolver)
for invalid in ["http://transfer.it/t/owned","https://transfer.it/s/owned","https://www.transfer.it/t/owned","https://transfer.it/t/a//","https://transfer.it/t/a?x=secret","https://transfer.it/t/%61"]{
 check("invalid transfer never rawmedia",{if case .refused(.transferLinkShape)=OpenURLRouter.route(invalid){return true};return false}())
}
func prepare(_ mode:String,_ mega:Bool=false,_ cancellation:SourcePreparationCancellation = .init(),_ timeout:Double=2)throws->PreparedLocalMedia{
 try NodeSourcePreparation.prepare(url:mega ? "https://mega.nz/file/\(mode)#SecretKey":"https://transfer.it/t/\(mode)",selectedFilename:mega ? nil:"owned.wav",nodeExecutable:node,script:script,cacheRoot:root,timeout:timeout,cancellation:cancellation)
}
for mega in [false,true]{
 let value=try prepare("ok",mega);check("registered source yields validated local cache",value.bytes==128 && FileManager.default.fileExists(atPath:value.path));let directory=URL(fileURLWithPath:value.path).deletingLastPathComponent();check("private source cache",((try FileManager.default.attributesOfItem(atPath:directory.path)[.posixPermissions]) as? NSNumber)?.intValue==0o700);check("request removed before handoff",!FileManager.default.fileExists(atPath:directory.appendingPathComponent("request.json").path));try value.release();try value.release();check("lease release idempotent",!FileManager.default.fileExists(atPath:directory.path))
}
for (mode,kind) in [("escape","bad_result"),("wrongsize","bad_cache"),("symlink","bad_cache"),("badjson","bad_result"),("noisy","stdout_limit"),("refuse","source_refused"),("slow","timeout")]{
 do{_ = try prepare(mode,false,.init(),0.2);check("refuse \(kind)",false)}catch{check("typed \(kind) redacted",(error as? SourcePreparationError) == .kind(kind,""));check("failed preparation removes cache",(try FileManager.default.contentsOfDirectory(atPath:root)).isEmpty)}
}
let cancelled=SourcePreparationCancellation();cancelled.cancel();do{_ = try prepare("ok",false,cancelled);check("precancel",false)}catch{check("precancel typed",(error as? SourcePreparationError) == .kind("cancelled",""))}
let inflight=SourcePreparationCancellation();Thread.detachNewThread{Thread.sleep(forTimeInterval:0.1);inflight.cancel()}
do{_ = try prepare("slow",false,inflight);check("inflight cancel",false)}catch{check("inflight cancel typed",(error as? SourcePreparationError) == .kind("cancelled",""))}
do{_ = try NodeSourcePreparation.prepare(url:"https://transfer.it/t/ok",nodeExecutable:node,script:script,cacheRoot:root);check("filename required",false)}catch{check("filename required typed",(error as? SourcePreparationError) == .kind("selection_required",""))}
check("no orphan cache",(try FileManager.default.contentsOfDirectory(atPath:root)).isEmpty)
print("source-coordinator-process: \(failed==0 ? "all pass":"FAIL") controlled process fixture only; no service or Darwin")
exit(failed==0 ? 0:1)
