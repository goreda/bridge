import Foundation

/// Public protocol surface of packet P-B1, verbatim from the public contract.
public protocol MediaEngine: AnyObject {
    func command(_ name: String, arguments: [MediaValue]) throws -> MediaValue
    func get(_ property: String) throws -> MediaValue
    func set(_ property: String, value: MediaValue) throws
    func observe(_ property: String, token: UInt64, callback: @escaping (MediaValue) -> Void) throws
    func unobserve(token: UInt64)
}

public protocol MediaFacade: MediaEngine {}
