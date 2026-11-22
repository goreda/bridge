import Foundation

/// Public value type of the clean-room media facade contract.
/// Contract source: goreda/bridge GROUP-INBOX.md @ d37421b04b06d7c07eef36daf3ac8c0e6569cfb4, packet P-B1.
/// The shape below is verbatim from the public contract; Codable is additive
/// (used only to read generated JSON fixtures), it does not change the contract.
public enum MediaValue: Equatable, Sendable {
    case none, bool(Bool), number(Double), text(String), list([MediaValue]), object([String: MediaValue])
}

extension MediaValue: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum ValueType: String, Codable { case none, bool, number, text, list, object }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = try c.decode(ValueType.self, forKey: .type)
        switch t {
        case .none: self = .none
        case .bool: self = .bool(try c.decode(Bool.self, forKey: .value))
        case .number: self = .number(try c.decode(Double.self, forKey: .value))
        case .text: self = .text(try c.decode(String.self, forKey: .value))
        case .list: self = .list(try c.decode([MediaValue].self, forKey: .value))
        case .object: self = .object(try c.decode([String: MediaValue].self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none: try c.encode(ValueType.none, forKey: .type)
        case .bool(let v): try c.encode(ValueType.bool, forKey: .type); try c.encode(v, forKey: .value)
        case .number(let v): try c.encode(ValueType.number, forKey: .type); try c.encode(v, forKey: .value)
        case .text(let v): try c.encode(ValueType.text, forKey: .type); try c.encode(v, forKey: .value)
        case .list(let v): try c.encode(ValueType.list, forKey: .type); try c.encode(v, forKey: .value)
        case .object(let v): try c.encode(ValueType.object, forKey: .type); try c.encode(v, forKey: .value)
        }
    }
}
