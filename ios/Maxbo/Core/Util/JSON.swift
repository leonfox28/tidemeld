import Foundation

/// A JSON value, read leniently: Weibo's fields come and go, and numbers are
/// sometimes sent as strings.
enum JSON: Sendable, Hashable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    /// Parses [data], or returns nil if it isn't JSON.
    static func parse(_ data: Data) -> JSON? {
        guard let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return JSON(foundation: any)
    }

    static func parse(_ text: String) -> JSON? { parse(Data(text.utf8)) }

    init(foundation any: Any) {
        switch any {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                let type = String(cString: number.objCType)
                if type == "d" || type == "f" || number is NSDecimalNumber {
                    let value = number.doubleValue
                    if value == value.rounded(), abs(value) < 9.0e18 {
                        self = .int(Int64(value))
                    } else {
                        self = .double(value)
                    }
                } else {
                    self = .int(number.int64Value)
                }
            }
        case let string as String: self = .string(string)
        case let array as [Any]: self = .array(array.map(JSON.init(foundation:)))
        case let object as [String: Any]: self = .object(object.mapValues(JSON.init(foundation:)))
        default: self = .null
        }
    }

    subscript(key: String) -> JSON? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    /// A non-empty string, or an integer rendered as one; ids are always kept as strings.
    var string: String? {
        switch self {
        case .string(let s): s.isEmpty ? nil : s
        case .int(let i): String(i)
        default: nil
        }
    }

    /// A string as sent, empty ones included.
    var rawString: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var int: Int64? {
        switch self {
        case .int(let i): i
        case .double(let d): d.isFinite ? Int64(d) : nil
        case .string(let s): Int64(s)
        default: nil
        }
    }

    var bool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var object: [String: JSON]? {
        if case .object(let o) = self { return o }
        return nil
    }

    var isObject: Bool { object != nil }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var array: [JSON]? {
        if case .array(let a) = self { return a }
        return nil
    }

    /// The objects in this list, skipping anything else; empty if it isn't a list.
    var objects: [JSON] { array?.filter(\.isObject) ?? [] }

    /// An absolute https URL; Weibo often sends protocol-relative ones.
    var url: String? { readURL(string) }

    func has(_ key: String) -> Bool { object?[key] != nil }

    /// A short description of the shape (keys and types, no values), for diagnostics.
    func shape(maxDepth: Int = 2) -> String {
        switch self {
        case .null: return "null"
        case .bool: return "bool"
        case .int, .double: return "num"
        case .string: return "str"
        case .array(let a):
            guard maxDepth > 0, let first = a.first else { return "[\(a.count)]" }
            return "[\(a.count)×\(first.shape(maxDepth: maxDepth - 1))]"
        case .object(let o):
            guard maxDepth > 0 else { return "{\(o.count)}" }
            let fields = o.keys.sorted().map { "\($0):\(o[$0]!.shape(maxDepth: maxDepth - 1))" }
            return "{\(fields.joined(separator: ","))}"
        }
    }

    /// This value as Foundation objects, for JSONSerialization.
    var foundation: Any {
        switch self {
        case .null: NSNull()
        case .bool(let b): b
        case .int(let i): i
        case .double(let d): d
        case .string(let s): s
        case .array(let a): a.map(\.foundation)
        case .object(let o): o.mapValues(\.foundation)
        }
    }

    /// Compact JSON text.
    var text: String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: foundation, options: [.fragmentsAllowed, .sortedKeys])
        else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// An absolute https URL from a string such as an `<img>`'s `src`.
func readURL(_ value: String?) -> String? {
    guard let url = value, !url.isEmpty else { return nil }
    if url.hasPrefix("//") { return "https:" + url }
    return url.hasPrefix("http") ? url : nil
}

/// [url] over https: Weibo sends some media URLs as plain http, which its hosts
/// also serve over https.
func https(_ url: String) -> String {
    url.hasPrefix("http://") ? "https://" + url.dropFirst(7) : url
}
