import Foundation

/// Literal, case-insensitive keywords. Rules never leave this device.
enum ContentFilter {
    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
    }

    static func keywords(_ value: String) -> [String] {
        var seen: Set<String> = []
        return value.components(separatedBy: .newlines)
            .map { String($0.trimmingCharacters(in: .whitespaces).prefix(200)) }
            .filter { !$0.isEmpty && seen.insert(normalized($0)).inserted }
            .prefix(100).map { $0 }
    }

    static func matches(_ text: String, keywords: String) -> Bool {
        let text = normalized(text)
        return Self.keywords(keywords).contains { text.contains(normalized($0)) }
    }
}
