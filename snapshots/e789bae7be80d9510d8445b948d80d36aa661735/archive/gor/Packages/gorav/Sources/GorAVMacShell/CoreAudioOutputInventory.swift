#if canImport(CoreAudio) && canImport(AudioUnit)
import Foundation
import CoreAudio
import AudioUnit
import GorAVPlaybackCore

/// Read-only HAL inventory. Never changes the system default output device.
public enum CoreAudioOutputInventory {
    private static func address(_ selector:AudioObjectPropertySelector,
                                _ scope:AudioObjectPropertyScope=kAudioObjectPropertyScopeGlobal)->AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector:selector,mScope:scope,mElement:kAudioObjectPropertyElementMain)
    }
    private static func scalar<T>(_ object:AudioObjectID,_ selector:AudioObjectPropertySelector,
                                  initial:T)->T? {
        var a=address(selector),value=initial,size=UInt32(MemoryLayout<T>.size)
        let status=withUnsafeMutableBytes(of:&value) {bytes in
            AudioObjectGetPropertyData(object,&a,0,nil,&size,bytes.baseAddress!)
        }
        guard status==noErr,size==MemoryLayout<T>.size else{return nil}
        return value
    }
    public static func uid(_ device:AudioDeviceID)->String? {
        string(device,kAudioDevicePropertyDeviceUID)
    }
    private static func string(_ object:AudioObjectID,_ selector:AudioObjectPropertySelector)->String? {
        // HAL supplies a CFString property; no guessed name/UID fallback.
        var a=address(selector),value:CFString="" as CFString
        var size=UInt32(MemoryLayout<CFString>.size)
        let status=AudioObjectGetPropertyData(object,&a,0,nil,&size,&value)
        guard status==noErr,size==MemoryLayout<CFString>.size else{return nil}
        let result=value as String
        return result.isEmpty ? nil:result
    }
    private static func hasOutput(_ device:AudioDeviceID)->Bool {
        var a=address(kAudioDevicePropertyStreams,kAudioObjectPropertyScopeOutput),size:UInt32=0
        return AudioObjectGetPropertyDataSize(device,&a,0,nil,&size)==noErr && size>=MemoryLayout<AudioStreamID>.size
    }
    public static func snapshot(currentUID:String?=nil)throws->AudioOutputDeviceInventory {
        var a=address(kAudioHardwarePropertyDevices),size:UInt32=0
        var status=AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size)
        guard status==noErr,size%UInt32(MemoryLayout<AudioDeviceID>.size)==0 else {throw AudioDeviceFailure(.inventory,status:status)}
        var ids=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        if !ids.isEmpty {
            status=ids.withUnsafeMutableBytes {bytes in
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,bytes.baseAddress!)
            }
            guard status==noErr,Int(size)<=ids.count*MemoryLayout<AudioDeviceID>.size else {throw AudioDeviceFailure(.inventory,status:status)}
            ids=Array(ids.prefix(Int(size)/MemoryLayout<AudioDeviceID>.size))
        }
        var devices=[AudioOutputDevice]()
        for id in ids where hasOutput(id) {
            guard let uid=uid(id),let name=string(id,kAudioObjectPropertyName),
                  let alive:UInt32=scalar(id,kAudioDevicePropertyDeviceIsAlive,initial:0) else{continue}
            devices.append(.init(uid:uid,name:name,isAlive:alive != 0))
        }
        let defaultID:AudioDeviceID?=scalar(AudioObjectID(kAudioObjectSystemObject),kAudioHardwarePropertyDefaultOutputDevice,initial:AudioDeviceID(0))
        return .init(devices:devices,defaultUID:defaultID.flatMap(uid),currentUID:currentUID)
    }
    public static func resolve(uid:String)throws->AudioDeviceID {
        var a=address(kAudioHardwarePropertyDevices),size:UInt32=0
        var status=AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size)
        guard status==noErr,size%UInt32(MemoryLayout<AudioDeviceID>.size)==0 else{throw AudioDeviceFailure(.inventory,status:status)}
        var ids=[AudioDeviceID](repeating:0,count:Int(size)/MemoryLayout<AudioDeviceID>.size)
        if !ids.isEmpty {
            status=ids.withUnsafeMutableBytes {AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&a,0,nil,&size,$0.baseAddress!)}
            guard status==noErr,Int(size)<=ids.count*MemoryLayout<AudioDeviceID>.size else{throw AudioDeviceFailure(.inventory,status:status)}
            ids=Array(ids.prefix(Int(size)/MemoryLayout<AudioDeviceID>.size))
        }
        guard let device=ids.first(where:{Self.uid($0)==uid && hasOutput($0)}) else {throw AudioDeviceFailure(.unavailable)}
        return device
    }
    public static func currentUID(unit:AudioUnit)throws->String {
        var id=AudioDeviceID(0),size=UInt32(MemoryLayout<AudioDeviceID>.size)
        let status=AudioUnitGetProperty(unit,kAudioOutputUnitProperty_CurrentDevice,kAudioUnitScope_Global,0,&id,&size)
        guard status==noErr,size==MemoryLayout<AudioDeviceID>.size,let uid=uid(id) else{throw AudioDeviceFailure(.readback,status:status)}
        return uid
    }
}

/// HAL notifications only signal a serialized readback by the owner. No unit
/// access, callback payload dereference, or device mutation in the listener.
final class CoreAudioOutputWatch: @unchecked Sendable {
    private let queue=DispatchQueue(label:"gorav.audio.output-watch")
    private var block:AudioObjectPropertyListenerBlock?
    private var listBlock:AudioObjectPropertyListenerBlock?
    private var listAddress=AudioObjectPropertyAddress(mSelector:kAudioHardwarePropertyDevices,
        mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    private var device:AudioDeviceID
    private var address=AudioObjectPropertyAddress(mSelector:kAudioDevicePropertyDeviceIsAlive,
        mScope:kAudioObjectPropertyScopeGlobal,mElement:kAudioObjectPropertyElementMain)
    init(device:AudioDeviceID,changed:@escaping @Sendable ()->Void)throws {
        self.device=device
        let callback:AudioObjectPropertyListenerBlock={_,_ in changed()}
        let status=AudioObjectAddPropertyListenerBlock(device,&address,queue,callback)
        guard status==noErr else{throw AudioDeviceFailure(.inventory,status:status)}
        block=callback
        let listStatus=AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&listAddress,queue,callback)
        guard listStatus==noErr else {
            // No unit or callback payload is captured. Removal failure can
            // retain only the weak-owner signal, not a dangling HAL handle.
            AudioObjectRemovePropertyListenerBlock(device,&address,queue,callback)
            block=nil
            throw AudioDeviceFailure(.inventory,status:listStatus)
        }
        listBlock=callback
    }
    deinit {
        if let block {AudioObjectRemovePropertyListenerBlock(device,&address,queue,block)}
        if let listBlock {AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject),&listAddress,queue,listBlock)}
        // The callback owns only the supplied weak-owner signal closure, never
        // this watch or an AudioUnit. A removal failure cannot dangle unit data.
    }
}
#endif
