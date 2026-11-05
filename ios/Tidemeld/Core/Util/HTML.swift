import Foundation

/// A node of an HTML fragment: text, or an element with its children.
enum HTMLNode: Sendable {
    case text(String)
    case element(HTMLElement)
}

/// An element of an HTML fragment. Names and attribute names are lowercase.
struct HTMLElement: Sendable {
    let name: String
    let attributes: [String: String]
    var children: [HTMLNode]

    func attr(_ name: String) -> String { attributes[name] ?? "" }
    func has(_ name: String) -> Bool { attributes[name] != nil }

    func hasClass(_ name: String) -> Bool {
        attr("class").split(whereSeparator: \.isWhitespace).contains { $0 == name }
    }

    /// All the text inside, as written.
    var wholeText: String {
        children.map { node in
            switch node {
            case .text(let text): text
            case .element(let element): element.name == "br" ? "\n" : element.wholeText
            }
        }.joined()
    }

    /// The first element inside named [name] with class [className], depth first.
    func first(_ name: String, className: String? = nil) -> HTMLElement? {
        for case .element(let child) in children {
            if child.name == name, className.map(child.hasClass) ?? true { return child }
            if let found = child.first(name, className: className) { return found }
        }
        return nil
    }
}

/// Parses an HTML fragment as Weibo writes it in status bodies: loose markup
/// (unquoted attribute values, unclosed tags), which this tolerates as a
/// browser would, if far less thoroughly.
func parseHTMLFragment(_ html: String) -> [HTMLNode] {
    var parser = HTMLParser(Array(html.unicodeScalars))
    return parser.parse()
}

private let voidElements: Set<String> = [
    "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track",
    "wbr",
]

private struct HTMLParser {
    let s: [Unicode.Scalar]
    var i = 0
    /// Open elements, the fragment itself at the bottom.
    var stack: [HTMLElement] = [HTMLElement(name: "#root", attributes: [:], children: [])]
    var text = String.UnicodeScalarView()

    init(_ s: [Unicode.Scalar]) { self.s = s }

    mutating func parse() -> [HTMLNode] {
        while i < s.count {
            if s[i] == "<", i + 1 < s.count {
                let next = s[i + 1]
                if next == "!" {
                    flushText()
                    skipComment()
                    continue
                }
                if next == "/" || next.properties.isAlphabetic {
                    flushText()
                    if next == "/" { closeTag() } else { openTag() }
                    continue
                }
            }
            if s[i] == "&" {
                text.append(contentsOf: entity().unicodeScalars)
                continue
            }
            text.append(s[i])
            i += 1
        }
        flushText()
        while stack.count > 1 { popElement() }
        return stack[0].children
    }

    mutating func flushText() {
        guard !text.isEmpty else { return }
        stack[stack.count - 1].children.append(.text(String(text)))
        text = String.UnicodeScalarView()
    }

    mutating func popElement() {
        let element = stack.removeLast()
        stack[stack.count - 1].children.append(.element(element))
    }

    mutating func skipComment() {
        // `<!--…-->`, or `<!doctype …>` and the like.
        if matches("<!--") {
            i += 4
            while i < s.count, !matches("-->") { i += 1 }
            i = min(s.count, i + 3)
        } else {
            while i < s.count, s[i] != ">" { i += 1 }
            i = min(s.count, i + 1)
        }
    }

    func matches(_ literal: String) -> Bool {
        var j = i
        for c in literal.unicodeScalars {
            guard j < s.count, s[j] == c else { return false }
            j += 1
        }
        return true
    }

    mutating func name() -> String {
        var name = String.UnicodeScalarView()
        while i < s.count, !isSpace(s[i]), s[i] != ">", s[i] != "/", s[i] != "=" {
            name.append(s[i])
            i += 1
        }
        return String(name).lowercased()
    }

    mutating func closeTag() {
        i += 2
        let name = name()
        while i < s.count, s[i] != ">" { i += 1 }
        i = min(s.count, i + 1)
        // Close up to the matching element; a stray end tag is ignored.
        guard let depth = stack.lastIndex(where: { $0.name == name }), depth > 0 else { return }
        while stack.count > depth { popElement() }
    }

    mutating func openTag() {
        i += 1
        let name = name()
        var attributes: [String: String] = [:]
        var selfClosing = false
        while i < s.count {
            skipSpace()
            guard i < s.count else { break }
            if s[i] == ">" {
                i += 1
                break
            }
            if s[i] == "/" {
                selfClosing = true
                i += 1
                continue
            }
            let attribute = self.name()
            if attribute.isEmpty {
                i += 1
                continue
            }
            skipSpace()
            var value = ""
            if i < s.count, s[i] == "=" {
                i += 1
                skipSpace()
                value = attributeValue()
            }
            if attributes[attribute] == nil { attributes[attribute] = value }
        }
        let element = HTMLElement(name: name, attributes: attributes, children: [])
        if selfClosing || voidElements.contains(name) {
            stack[stack.count - 1].children.append(.element(element))
        } else {
            stack.append(element)
        }
    }

    mutating func attributeValue() -> String {
        guard i < s.count else { return "" }
        var value = String.UnicodeScalarView()
        let quote = s[i]
        if quote == "\"" || quote == "'" {
            i += 1
            while i < s.count, s[i] != quote {
                if s[i] == "&" {
                    value.append(contentsOf: entity().unicodeScalars)
                } else {
                    value.append(s[i])
                    i += 1
                }
            }
            i = min(s.count, i + 1)
        } else {
            while i < s.count, !isSpace(s[i]), s[i] != ">" {
                if s[i] == "&" {
                    value.append(contentsOf: entity().unicodeScalars)
                } else {
                    value.append(s[i])
                    i += 1
                }
            }
        }
        return String(value)
    }

    mutating func skipSpace() {
        while i < s.count, isSpace(s[i]) { i += 1 }
    }

    func isSpace(_ c: Unicode.Scalar) -> Bool {
        c == " " || c == "\n" || c == "\t" || c == "\r" || c == "\u{0C}"
    }

    /// Decodes the character reference at `&`, or takes the `&` as it is.
    mutating func entity() -> String {
        var j = i + 1
        var body = String.UnicodeScalarView()
        while j < s.count, j - i <= 10, s[j] != ";", s[j] == "#" || s[j].properties.isAlphabetic
            || ("0"..."9").contains(s[j])
        {
            body.append(s[j])
            j += 1
        }
        let name = String(body)
        let terminated = j < s.count && s[j] == ";"
        var decoded: String?
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map {
                String(Character($0))
            }
        } else if name.hasPrefix("#") {
            decoded = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map {
                String(Character($0))
            }
        } else {
            decoded = namedEntities[name]
        }
        guard let decoded else {
            i += 1
            return "&"
        }
        i = terminated ? j + 1 : j
        return decoded
    }
}

private let namedEntities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    "middot": "·", "hellip": "…", "mdash": "—", "ndash": "–", "ldquo": "“", "rdquo": "”",
    "lsquo": "‘", "rsquo": "’", "copy": "©", "reg": "®", "times": "×",
]

/// [fragment] as plain text: the text of its HTML, or itself if it has none.
func plainTextOfHTML(_ fragment: String?) -> String? {
    guard let fragment else { return nil }
    let text: String
    if fragment.contains("<") {
        let root = HTMLElement(name: "#root", attributes: [:], children: parseHTMLFragment(fragment))
        text = root.wholeText
    } else {
        text = fragment
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func escapeHTML(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}
