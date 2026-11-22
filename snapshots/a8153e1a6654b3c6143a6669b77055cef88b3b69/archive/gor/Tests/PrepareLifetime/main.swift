import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
let args=CommandLine.arguments
if args.contains("--probe") {
    PrepareProcessLifetime.watchOwner(arguments:args)
    print("READY",getpid());fflush(stdout)
    while true { Thread.sleep(forTimeInterval:1) }
} else if args.contains("--parent") {
    let p=Process();p.executableURL=URL(fileURLWithPath:args[0]);p.arguments=["--probe",PrepareProcessLifetime.ownerFlag,String(getpid())]
    try! p.run();while true {Thread.sleep(forTimeInterval:1)}
} else if args.contains("--remux") {
    print(PrepareInputRemux.arguments(source:args[2],destination:args[3]).joined(separator:"\n"))
} else if args.contains("--lane") {
    let root=URL(fileURLWithPath:args[2]);let fd=PrepareProcessLifetime.acquireLane(root:root,cancelled:{false})!
    print("ENTER");fflush(stdout);Thread.sleep(forTimeInterval:0.4);PrepareProcessLifetime.releaseLane(fd)
} else {
    typealias N=PrepareProcessLifetime.Node
    let nodes=[N(pid:10,parent:1,command:"a"),N(pid:11,parent:10,command:"b"),N(pid:12,parent:11,command:"c"),N(pid:13,parent:1,command:"other")]
    precondition(PrepareProcessLifetime.descendants(of:10,nodes:nodes)==[12,11])
    let film=URL(fileURLWithPath:"/f.mkv");var now=0.0,starts=0,stops=0
    let l=ThreeDPrepareLauncher(spawn:{{_,_ in starts+=1;return .init(stop:{stops+=1})}},report:{_ in})
    l.clock={now}
    func tick(_ e:String){l.update(mode:"sbs",film:film,playhead:0,info:(24,100),quality:"full",experiments:e,preflightReason:nil)}
    for i in 0..<100 {now=Double(i)*0.01;tick(i%2==0 ? "ema":"dav2")}
    precondition(starts==0,"churn started a model worker")
    now=2;tick("dav2");precondition(starts==1)
    now=3;tick("");precondition(stops==1 && starts==1)
    now=4;tick("");precondition(starts==2)
    l.cancelForMediaTransition();precondition(stops==2 && !l.isPreparing)
    now=5;tick("");precondition(starts==2)
    now=6;tick("");precondition(starts==3)
    print("PASS actual launcher coalesces 100 flips; cancels retiring media; resumes settled reopen; descendant graph excludes unrelated")
}
