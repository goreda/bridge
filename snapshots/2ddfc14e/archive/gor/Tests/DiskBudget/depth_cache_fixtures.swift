// Disposable filesystem fixtures. Exact production Budget and IO declarations are prepended.
var failures=0,checks=0
func check(_ value:Bool,_ name:String) {checks+=1;if !value {failures+=1;print("FAIL "+name)}else{print("PASS "+name)}}
func refuses(_ expected:DepthCacheBudget.Failure,_ name:String,_ body:()throws->Void) {do{try body();check(false,name)}catch{check((error as? DepthCacheBudget.Failure)==expected,name)}}
let fm=FileManager.default
let base=URL(fileURLWithPath:CommandLine.arguments[1])
try fm.createDirectory(at:base,withIntermediateDirectories:true)
func configure(_ quota:UInt64=1048576) {var p=DepthCacheBudget.Policy();p.quota=quota;p.reserve=0;p.writeHeadroom=0;DepthCacheBudget.policy=p}
func fixture(_ name:String)throws->(URL,URL) {configure();let root=base.appendingPathComponent(name);try fm.createDirectory(at:root,withIntermediateDirectories:true);let pin=try DepthCacheBudget.pin(root:root,key:String(repeating:"a",count:64),create:true);let entry=pin.entry;withExtendedLifetime(pin){};return(root,entry)}
func data(_ n:Int)->Data {Data(repeating:7,count:n)}
func put(_ u:URL,_ n:Int=8)throws {try data(n).write(to:u)}
func size(_ u:URL)->UInt64 {(try? fm.attributesOfItem(atPath:u.path)[.size] as? NSNumber)?.uint64Value ?? 0}
if CommandLine.arguments.count>2 && CommandLine.arguments[2]=="hold" {
 configure();let root=base;let key=String(repeating:"a",count:64);let pin=try DepthCacheBudget.pin(root:root,key:key);try Data().write(to:root.appendingPathComponent("ready"));Thread.sleep(forTimeInterval:1);withExtendedLifetime(pin){};exit(0)
}
if CommandLine.arguments.count>2 && CommandLine.arguments[2]=="append-worker" {
 configure(UInt64(CommandLine.arguments[4])!);let u=base.appendingPathComponent(CommandLine.arguments[3]);let fd=open(u.path,O_WRONLY|O_APPEND);let h=FileHandle(fileDescriptor:fd,closeOnDealloc:true);Thread.sleep(forTimeInterval:0.1)
 for _ in 0..<12 {do {try DepthCacheIO.append(data(128),to:h,url:u)}catch DepthCacheBudget.Failure.quota {break}}
 try h.close();exit(0)
}
// Exact legacy names only; regular owned files, no blanket pattern or recursion.
for name in ["prepare-input.part","prepare-input.part.mp4","prepare-input.mp4"] {
 let(root,entry)=try fixture("legacy-"+name);let u=entry.appendingPathComponent(name);try put(u)
 let removed=try DepthCacheBudget.reapLegacyInputs(root:root)
 check(!fm.fileExists(atPath:u.path) && removed==[entry.lastPathComponent+"/"+name],"owned exact legacy "+name)
 check(DepthCacheBudget.deletable(entry),"owned residual entry stays deletable "+name)
}
do {
 let(root,entry)=try fixture("scope");let names=["prepare-input.part","prepare-input.part.mp4","prepare-input.mp4"]
 for name in names {try put(entry.appendingPathComponent(name))}
 let original=entry.appendingPathComponent("prepare-input.mp4");let unrelated=entry.appendingPathComponent("prepare-input.part.backup");try put(unrelated)
 let unowned=root.appendingPathComponent(String(repeating:"b",count:64));try fm.createDirectory(at:unowned,withIntermediateDirectories:true);for n in names{try put(unowned.appendingPathComponent(n))}
 let sub=entry.appendingPathComponent("nested");try fm.createDirectory(at:sub,withIntermediateDirectories:true);try put(sub.appendingPathComponent(names[0]))
 _=try DepthCacheBudget.reapLegacyInputs(root:root,source:original)
 check(fm.fileExists(atPath:original.path),"active original source excluded")
 check(fm.fileExists(atPath:unrelated.path),"unknown basename untouched")
 check(names.allSatisfy{fm.fileExists(atPath:unowned.appendingPathComponent($0).path)},"unowned legacy names untouched")
 check(fm.fileExists(atPath:sub.appendingPathComponent(names[0]).path),"no recursive legacy removal")
}
for kind in ["symlink","hardlink","directory","entry-symlink"] {
 let(root,entry)=try fixture(kind);let u=entry.appendingPathComponent("prepare-input.mp4");let target=base.appendingPathComponent(kind+"-original");try put(target)
 if kind=="symlink" {try fm.createSymbolicLink(at:u,withDestinationURL:target)}
 if kind=="hardlink" {try fm.linkItem(at:target,to:u)}
 if kind=="directory" {try fm.createDirectory(at:u,withIntermediateDirectories:true);try put(u.appendingPathComponent("keep"))}
 if kind=="entry-symlink" {try put(u);try fm.createSymbolicLink(at:root.appendingPathComponent(String(repeating:"b",count:64)),withDestinationURL:entry)}
 _=try DepthCacheBudget.reapLegacyInputs(root:root,source:kind=="entry-symlink" ? u:nil)
 check(fm.fileExists(atPath:u.path) && size(target)==8,kind+" is not removed/traversed")
}
do {
 let(root,entry)=try fixture("locks");let u=entry.appendingPathComponent("prepare-input.mp4");try put(u)
 var pin:DepthCacheBudget.Pin?=try DepthCacheBudget.pin(root:root,key:entry.lastPathComponent)
 let first=try DepthCacheBudget.reapLegacyInputs(root:root);check(first.isEmpty && fm.fileExists(atPath:u.path),"same-process shared entry pin protects legacy")
 withExtendedLifetime(pin){};pin=nil
 let fd=open(root.appendingPathComponent(".prepare-worker.lock").path,O_CREAT|O_RDWR,mode_t(0o600));_ = flock(fd,LOCK_SH)
 let second=try DepthCacheBudget.reapLegacyInputs(root:root);check(second.isEmpty,"worker lock protects live producer");_=flock(fd,LOCK_UN);close(fd)
 let child=Process();child.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);child.arguments=[root.path,"hold"];try child.run()
 let ready=root.appendingPathComponent("ready");let deadline=Date().addingTimeInterval(5)
 while !fm.fileExists(atPath:ready.path) && Date()<deadline {Thread.sleep(forTimeInterval:0.01)}
 check(fm.fileExists(atPath:ready.path),"cross-process lock handshake")
 let third=try DepthCacheBudget.reapLegacyInputs(root:root);check(third.isEmpty && fm.fileExists(atPath:u.path),"cross-process shared pin protects legacy");child.waitUntilExit();check(child.terminationStatus==0,"pin worker exits")
 _=try DepthCacheBudget.reapLegacyInputs(root:root);check(!fm.fileExists(atPath:u.path),"released entry now reaped")
}
// All budget and filesystem checks below execute unmodified production declarations.
do {
 let(root,entry)=try fixture("sink");let u=entry.appendingPathComponent("depth_shot_00000.dzc");try put(u,8)
 let h=try FileHandle(forWritingTo:u);try h.seekToEnd();let used=try DepthCacheBudget.bytes(root)
 configure(used+4);try DepthCacheIO.append(data(4),to:h,url:u);check(size(u)==12,"append exact quota fit")
 refuses(.quota,"append refuses one byte beyond quota"){try DepthCacheIO.append(data(1),to:h,url:u)};check(size(u)==12,"quota refusal leaves bytes unchanged");try h.close()
 configure();let v=entry.appendingPathComponent("new.json");let used2=try DepthCacheBudget.bytes(root);configure(used2+5);try DepthCacheIO.write(data(5),to:v);check(size(v)==5,"atomic new write exact quota fit")
 refuses(.quota,"atomic replacement charged old plus full new"){try DepthCacheIO.write(data(5),to:v)};check(size(v)==5,"atomic quota refusal preserves old")
 configure();try DepthCacheIO.write(data(3),to:v,atomic:false);check(size(v)==3,"non-atomic write uses real sink")
 let used3=try DepthCacheBudget.bytes(root);configure(used3-1);refuses(.quota,"already-over-quota refuses zero allocation"){try DepthCacheIO.write(Data(),to:v)}
 configure(UInt64.max);let free=DepthCacheBudget.freeBytes(root)!;DepthCacheBudget.policy.reserve=free+1024*1024
 refuses(.freeSpace,"reserve refuses before write"){try DepthCacheIO.write(data(1),to:v)};check(size(v)==3,"reserve refusal preserves bytes")
 configure(UInt64.max);DepthCacheBudget.policy.reserve=UInt64.max;refuses(.freeSpace,"max reserve refuses without overflow"){try DepthCacheIO.write(data(1),to:v)}
 configure(UInt64.max);refuses(.quota,"max allocation quota subtraction is overflow safe"){try DepthCacheBudget.withLock(root){try DepthCacheIO.checkLocked(root:root,bytes:UInt64.max)}}
}
for kind in ["append-wrong-inode","append-symlink","write-hardlink","write-symlink"] {
 let(root,entry)=try fixture(kind);let u=entry.appendingPathComponent("depth_shot_00000.dzc"),other=entry.appendingPathComponent("other.json");try put(other)
 if kind.contains("symlink") {try fm.createSymbolicLink(at:u,withDestinationURL:other)}else{try put(u)}
 if kind=="write-hardlink" {try fm.removeItem(at:u);try fm.linkItem(at:other,to:u)}
 if kind.hasPrefix("append") {let h=try FileHandle(forWritingTo:kind=="append-wrong-inode" ? other:u);refuses(.unsafe,kind){try DepthCacheIO.append(data(2),to:h,url:u)};try h.close()}
 else {refuses(.unsafe,kind){try DepthCacheIO.write(data(2),to:u)}}
 check(size(other)==8,"unsafe target preserved "+kind);_=root
}
do {
 let(root,entry)=try fixture("failed-write-release");let u=entry.appendingPathComponent("test.json");try put(u,4);configure(0)
 refuses(.quota,"transaction reports refusal"){try DepthCacheIO.write(data(1),to:u)}
 configure();try DepthCacheIO.write(data(2),to:u);check(size(u)==2,"failed transaction releases real flock")
 check(DepthCacheIO.root(for:u)?.path==root.path,"sink resolves owned entry root")
 let outside=base.appendingPathComponent("outside.json");try DepthCacheIO.write(data(3),to:outside);check(size(outside)==3,"non-cache writes retain existing behavior")
}
do {
 let(root,entry)=try fixture("eviction");let key=String(repeating:"b",count:64);try put(entry.appendingPathComponent("source_shot_00000.mp4"),400)
 var second:DepthCacheBudget.Pin?=try DepthCacheBudget.pin(root:root,key:key,create:true);let other=second!.entry;try put(other.appendingPathComponent("source_shot_00000.mp4"),400);withExtendedLifetime(second){};second=nil
 try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1)],ofItemAtPath:entry.appendingPathComponent(DepthCacheBudget.marker).path)
 try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:2)],ofItemAtPath:other.appendingPathComponent(DepthCacheBudget.marker).path)
 var p=DepthCacheBudget.Policy();p.quota=500;p.reserve=0;p.writeHeadroom=0
 let removed=try DepthCacheBudget.enforce(root:root,policy:p,free:{100000});check(removed==[entry.lastPathComponent],"LRU inactive entry evicted first")
 let pin=try DepthCacheBudget.pin(root:root,key:key);p.quota=1
 refuses(.quota,"active pin protects file but does not bypass admission quota"){_=try DepthCacheBudget.enforce(root:root,policy:p,free:{100000})};check(fm.fileExists(atPath:other.path),"active pinned entry retained");withExtendedLifetime(pin){}
 p.quota=UInt64.max;p.reserve=1
 refuses(.freeSpace,"unknown free fails closed"){_=try DepthCacheBudget.enforce(root:root,policy:p,free:{nil})}
 p.reserve=0;p.writeHeadroom=UInt64.max
 refuses(.quota,"admission headroom overflow fails closed"){_=try DepthCacheBudget.enforce(root:root,policy:p,additional:1,free:{UInt64.max})}
 p.writeHeadroom=0;p.reserve=UInt64.max
 refuses(.freeSpace,"admission reserve overflow fails closed"){_=try DepthCacheBudget.enforce(root:root,policy:p,additional:1,free:{UInt64.max})}
 p.quota=nil;p.reserve=1000
 check(DepthCacheBudget.quota(capacity:100000,available:10000,used:1000,policy:p)==1000,"derived usable quota unchanged")
 p.quota=42
 check(DepthCacheBudget.quota(capacity:100,available:UInt64.max,used:1,policy:p)==42,"quota override avoids irrelevant overflow")
 refuses(.unsafe,"entry key traversal refused"){_=try DepthCacheBudget.pin(root:root,key:"../film",create:true)}
}
do {
 let(root,entry)=try fixture("simultaneous-writers");try put(entry.appendingPathComponent("a.dzc"),0);try put(entry.appendingPathComponent("b.dzc"),0);let initial=try DepthCacheBudget.bytes(root);let quota=initial+1024
 var children:[Process]=[]
 for name in ["a.dzc","b.dzc"] {let child=Process();child.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);child.arguments=[root.path,"append-worker",entry.lastPathComponent+"/"+name,String(quota)];try child.run();children.append(child)}
 for child in children {child.waitUntilExit();check(child.terminationStatus==0,"concurrent sink worker exits")}
 let used=try DepthCacheBudget.bytes(root);check(used==quota,"two processes share one byte-hard quota, no overrun")
}
print("SUMMARY \(checks) checks, \(failures) failures; exact Linux source/filesystem only, native NOT_RUN")
exit(failures==0 ? 0:1)
