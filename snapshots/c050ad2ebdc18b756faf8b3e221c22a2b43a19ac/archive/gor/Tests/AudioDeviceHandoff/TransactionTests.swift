import Foundation

final class Provider:AudioDeviceHandoffProvider {
    var events=[String](),units:[UInt64:String]=[1:"old"],active:Set<UInt64>=[1]
    var failures:Set<String>=[],inventoryRows=[AudioOutputDevice(uid:"old",name:"old",isAlive:true),.init(uid:"new",name:"new",isAlive:true)]
    var mismatchNew=false,mismatchOld=false
    var retained=[UInt64](),removeOn="",fallbackOn=""
    func step(_ event:String,_ op:AudioDeviceOperation)throws {
        events.append(event)
        if event==removeOn {inventoryRows.removeAll(where:{$0.uid=="new"})}
        if event==fallbackOn {units[2]="old"}
        if failures.contains(event) {throw AudioDeviceFailure(op,status: -71)}
    }
    func inventory()throws->AudioOutputDeviceInventory {
        try step("inventory",.inventory)
        return .init(devices:inventoryRows,defaultUID:"old",currentUID:units[1])
    }
    func prepare(uid:String)throws->UInt64 {try step("prepare",.prepare);units[2]=uid;return 2}
    func quiesce(_ token:UInt64)throws {try step("quiesce\(token)",.quiesce);active.remove(token)}
    func activate(_ token:UInt64)throws {try step("activate\(token)",.activate);precondition(active.isEmpty);active.insert(token)}
    func currentUID(_ token:UInt64)throws->String {
        try step("read\(token)",.readback)
        if (token==2 && mismatchNew) || (token==1 && mismatchOld && events.contains("activate1")){return "wrong"}
        guard let uid=units[token] else{throw AudioDeviceFailure(.readback)};return uid
    }
    func dispose(_ token:UInt64)throws {try step("dispose\(token)",.dispose);precondition(!active.contains(token));units.removeValue(forKey:token)}
    func retainTerminal(_ tokens:[UInt64]) {events.append("retain");retained=tokens}
}
@main struct Run {
 static func main() {
    var count=0
    func check(_ condition:Bool,_ label:String){count+=1;if !condition {print("FAIL "+label);exit(1)}}
    do {
        let p=Provider();var owner=AudioOutputDeviceTransaction(currentToken:1)
        check(owner.select(uid:"new",provider:p) == .accepted(currentUID:"new"),"accepted only readback")
        check(p.events == ["inventory","read1","prepare","quiesce1","activate2","read2","inventory","dispose1","read2","inventory"],"actual order")
        check(owner.currentToken==2 && !owner.terminal,"committed token")
        check(p.active==[2] && p.units==[2:"new"],"only new remains")
    }
    do {
        let p=Provider();var owner=AudioOutputDeviceTransaction(currentToken:1)
        check(owner.select(uid:"old",provider:p) == .accepted(currentUID:"old"),"same actual device")
        check(p.events == ["inventory","read1","read1","inventory"],"same selection touches no unit")
    }
    for fail in ["inventory","read1","prepare"] {
        let p=Provider();p.failures=[fail];var owner=AudioOutputDeviceTransaction(currentToken:1)
        if case .refused = owner.select(uid:"new",provider:p) {check(true,"early refused")}else{check(false,fail)}
        check(p.active==[1] && owner.currentToken==1 && !owner.terminal,"early untouched")
    }
    for uid in ["","absent"] {
        let p=Provider();var owner=AudioOutputDeviceTransaction(currentToken:1)
        check(owner.select(uid:uid,provider:p) == .refused(AudioDeviceFailure(.unavailable)),"invalid unavailable")
        check(p.events==["inventory"],"not guessed")
    }
    for failed in ["activate2","read2","mismatch"] {
        let p=Provider();p.failures=failed=="mismatch" ? []:[failed];p.mismatchNew=failed=="mismatch"
        var owner=AudioOutputDeviceTransaction(currentToken:1)
        let result=owner.select(uid:"new",provider:p)
        if case .rolledBack(_,let current)=result {check(current=="old","rollback readback")}else{check(false,"rollback "+failed)}
        check(p.active==[1] && p.units==[1:"old"] && owner.currentToken==1,"old restored")
        check(!owner.terminal,"rollback not terminal")
        check(Array(p.events.suffix(5)) == ["quiesce2","dispose2","activate1","read1","inventory"],"rollback exact order")
    }
    for fail in ["quiesce1","quiesce2","dispose2","activate1","dispose1","oldMismatch"] {
        let p=Provider();p.failures=[fail]
        if fail != "quiesce1" && fail != "dispose1" {p.failures.insert("read2")}
        p.mismatchOld=fail=="oldMismatch"
        var owner=AudioOutputDeviceTransaction(currentToken:1)
        let result=owner.select(uid:"new",provider:p)
        if case .terminal=result {check(true,"terminal result")}else{check(false,"terminal "+fail)}
        check(owner.terminal && p.retained==[1,2],"terminal retains")
        let before=p.events
        check(owner.select(uid:"old",provider:p) == .refused(AudioDeviceFailure(.stopped)),"terminal closed")
        check(p.events==before,"terminal no new calls")
        if fail=="quiesce1" {check(!p.events.contains("activate2") && !p.events.contains("dispose1"),"unsafe stop never proceeds")}
    }
    do {
        let p=Provider();var owner=AudioOutputDeviceTransaction(currentToken:1)
        check(owner.validateCurrent(provider:p) == .accepted(currentUID:"old"),"current validated")
        p.inventoryRows=[]
        if case .terminal=owner.validateCurrent(provider:p) {check(true,"hot unplug")}else{check(false,"hot unplug")}
        check(owner.terminal && p.retained==[1],"unplug retains handle")
    }
    for event in ["activate2","dispose1"] {
        let p=Provider();p.removeOn=event;var owner=AudioOutputDeviceTransaction(currentToken:1)
        let result=owner.select(uid:"new",provider:p)
        if event=="activate2" {
            if case .rolledBack(_,"old")=result {check(true,"removal before commit rolls back")}else{check(false,"removed activation accepted")}
            check(owner.selectedUID==nil && !owner.terminal,"failed first selection not pinned")
        } else {
            if case .terminal=result {check(true,"removal during disposal terminal")}else{check(false,"removed final acceptance")}
            check(owner.terminal && p.retained==[2],"post-dispose loss retained")
        }
    }
    do {
        let p=Provider();p.fallbackOn="dispose1";var owner=AudioOutputDeviceTransaction(currentToken:1)
        if case .terminal=owner.select(uid:"new",provider:p) {check(true,"fallback during disposal terminal")}else{check(false,"fallback final acceptance")}
    }
    for removed in [false,true] {
        let p=Provider();var owner=AudioOutputDeviceTransaction(currentToken:1)
        check(owner.select(uid:"new",provider:p) == .accepted(currentUID:"new"),"bind selected UID")
        check(owner.selectedUID=="new","selected identity persisted")
        p.units[2]="old"
        if removed {p.inventoryRows.removeAll(where:{$0.uid=="new"})}
        if case .terminal=owner.validateCurrent(provider:p) {check(true,"fallback terminal")}else{check(false,"fallback must not accept alive old")}
        check(owner.selectedUID=="new" && owner.terminal && p.retained==[2],"never repin fallback")
    }
    do {
        let p=Provider();var owner=AudioOutputDeviceTransaction(currentToken:1,selectedUID:"new")
        if case .terminal=owner.select(uid:"old",provider:p) {check(true,"selection validates binding first")}else{check(false,"selection bypassed loss")}
        check(!p.events.contains("prepare"),"lost selected route cannot silently recover")
    }
    print("PASS \(count) real transaction failure/rollback checks")
 }
}
