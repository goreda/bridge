import Foundation

public struct AudioOutputDevice: Equatable, Sendable {
    public let uid: String
    public let name: String
    public let isAlive: Bool
    public init(uid: String, name: String, isAlive: Bool) {
        self.uid=uid;self.name=name;self.isAlive=isAlive
    }
}
public struct AudioOutputDeviceInventory: Equatable, Sendable {
    public let devices: [AudioOutputDevice]
    public let defaultUID: String?
    /// Actual output-unit readback, not the requested preference.
    public let currentUID: String?
    public init(devices:[AudioOutputDevice],defaultUID:String?,currentUID:String?) {
        self.devices=devices;self.defaultUID=defaultUID;self.currentUID=currentUID
    }
}
public enum AudioDeviceOperation: String, Sendable {
    case inventory, prepare, quiesce, activate, readback, dispose, rollback, unavailable, stopped
}
public struct AudioDeviceFailure: Error, Equatable, Sendable {
    public let operation: AudioDeviceOperation
    public let status: Int32?
    public init(_ operation:AudioDeviceOperation,status:Int32?=nil) {self.operation=operation;self.status=status}
}
public enum AudioDeviceSelectionResult: Equatable, Sendable {
    case accepted(currentUID:String)
    case refused(AudioDeviceFailure)
    case rolledBack(failure:AudioDeviceFailure,currentUID:String)
    /// No success is published; all involved provider handles stay retained.
    case terminal(failure:AudioDeviceFailure,rollback:AudioDeviceFailure)
}

/// Synchronous provider operations. The owner must serialize against seek,
/// stop, volume and producer writes. quiesce must stop and drain admitted
/// callbacks; a failure MUST NOT permit dispose or a second output consumer.
/// Tokens denote real retained units. This is not a provider-lifetime proof.
public protocol AudioDeviceHandoffProvider: AnyObject {
    /// DefaultOutput follows the system setting, so selecting its current UID
    /// explicitly still requires a fixed-device replacement.
    var requiresReplacementForSelection:Bool {get}
    func inventory() throws -> AudioOutputDeviceInventory
    func prepare(uid:String) throws -> UInt64
    func quiesce(_ token:UInt64) throws
    func activate(_ token:UInt64) throws
    func currentUID(_ token:UInt64) throws -> String
    func dispose(_ token:UInt64) throws
    func retainTerminal(_ tokens:[UInt64])
}

public extension AudioDeviceHandoffProvider {
    var requiresReplacementForSelection:Bool {false}
}

/// Real transaction control flow, shared unchanged by the native sink adapter
/// and portable failure-injection tests. Never changes the old handle before
/// preparing an opt-in replacement; never reports accepted before readback.
public struct AudioOutputDeviceTransaction {
    public private(set) var currentToken:UInt64
    public private(set) var terminal=false
    /// Nil only before an explicit selection. Never infer a replacement UID
    /// from provider fallback readback after a selection has been accepted.
    public private(set) var selectedUID:String?
    public init(currentToken:UInt64,selectedUID:String?=nil) {
        self.currentToken=currentToken;self.selectedUID=selectedUID
    }
    private func verify(_ token:UInt64,expected:String,provider:AudioDeviceHandoffProvider)throws {
        guard try provider.currentUID(token)==expected else {throw AudioDeviceFailure(.readback)}
        let inventory=try provider.inventory()
        guard inventory.devices.contains(where:{$0.uid==expected && $0.isAlive}) else {throw AudioDeviceFailure(.unavailable)}
    }
    private func failure(_ error:Error,_ operation:AudioDeviceOperation)->AudioDeviceFailure {
        error as? AudioDeviceFailure ?? AudioDeviceFailure(operation)
    }
    public mutating func select(uid:String,provider:AudioDeviceHandoffProvider)->AudioDeviceSelectionResult {
        guard !terminal else{return .refused(AudioDeviceFailure(.stopped))}
        if selectedUID != nil {
            if case .terminal(let first,let rollback)=validateCurrent(provider:provider) {
                return .terminal(failure:first,rollback:rollback)
            }
        }
        let old=currentToken,previous:String,new:UInt64
        do {
            let inventory=try provider.inventory()
            guard !uid.isEmpty,inventory.devices.contains(where:{$0.uid==uid && $0.isAlive}) else {
                return .refused(AudioDeviceFailure(.unavailable))
            }
            previous=try provider.currentUID(old)
            if previous==uid && !provider.requiresReplacementForSelection {
                try verify(old,expected:uid,provider:provider)
                selectedUID=uid
                return .accepted(currentUID:previous)
            }
            new=try provider.prepare(uid:uid)
        } catch {return .refused(failure(error,.prepare))}
        do {try provider.quiesce(old)} catch {
            let first=failure(error,.quiesce)
            // Failed quiescence means old output may still be in a callback.
            // Do not start new, dispose old or claim a working rollback.
            terminal=true;provider.retainTerminal([old,new])
            return .terminal(failure:first,rollback:AudioDeviceFailure(.quiesce))
        }
        do {
            try provider.activate(new)
            try verify(new,expected:uid,provider:provider)
        } catch {
            let first=failure(error,.activate)
            do {
                try provider.quiesce(new)
                try provider.dispose(new)
                try provider.activate(old)
                try verify(old,expected:selectedUID ?? previous,provider:provider)
                return .rolledBack(failure:first,currentUID:previous)
            } catch {
                terminal=true;provider.retainTerminal([old,new])
                return .terminal(failure:first,rollback:failure(error,.rollback))
            }
        }
        do {try provider.dispose(old)} catch {
            terminal=true;provider.retainTerminal([old,new])
            return .terminal(failure:failure(error,.dispose),rollback:AudioDeviceFailure(.dispose))
        }
        currentToken=new
        selectedUID=uid
        // A route can disappear during disposal too. Recheck before publishing.
        return validateCurrent(provider:provider)
    }
    /// Hot-unplug is a typed terminal silence request, not a guessed fallback.
    /// The provider retains callbacks/handles; application recovery is separate.
    public mutating func validateCurrent(provider:AudioDeviceHandoffProvider)->AudioDeviceSelectionResult {
        guard !terminal else{return .refused(AudioDeviceFailure(.stopped))}
        do {
            let uid:String
            if let selectedUID {uid=selectedUID} else {uid=try provider.currentUID(currentToken)}
            try verify(currentToken,expected:uid,provider:provider)
            return .accepted(currentUID:uid)
        } catch {
            terminal=true;provider.retainTerminal([currentToken])
            return .terminal(failure:failure(error,.unavailable),rollback:AudioDeviceFailure(.unavailable))
        }
    }
}
