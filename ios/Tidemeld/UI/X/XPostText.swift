import SwiftUI

/// The X adapter recognizes destinations; PostText only renders the runs.
func xTextSegments(_ text: String) -> [PostTextSegment] {
    let pattern =
        #"https?://[^\s<>]+|(?<![\p{L}\p{N}_@])@[A-Za-z0-9_]{1,15}(?![A-Za-z0-9_])|(?<![\p{L}\p{N}_])#[\p{L}\p{M}\p{N}_]+"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [.plain(text)] }
    let source = text as NSString
    var result: [PostTextSegment] = []
    var offset = 0
    for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
        if match.range.location > offset {
            result.append(
                .plain(
                    source.substring(with: NSRange(location: offset, length: match.range.location - offset))))
        }
        let raw = source.substring(with: match.range)
        var label = raw
        let destination: String
        if raw.hasPrefix("@") {
            destination = "https://x.com/\(raw.dropFirst())"
        } else if raw.hasPrefix("#") {
            var url = URLComponents(string: "https://x.com/search")!
            url.queryItems = [URLQueryItem(name: "q", value: raw)]
            destination = url.url!.absoluteString
        } else {
            while let last = label.last, ".,!?;:，。！？；：".contains(last) { label.removeLast() }
            for (close, open) in [(Character(")"), Character("(")), ("]", "["), ("}", "{")] {
                while label.last == close
                    && label.filter({ $0 == close }).count > label.filter({ $0 == open }).count
                { label.removeLast() }
            }
            destination = label
        }
        if let url = URL(string: destination), ["https", "http"].contains(url.scheme), url.host != nil {
            result.append(.link(label, url.absoluteString))
        } else {
            result.append(.plain(label))
        }
        if label.count < raw.count { result.append(.plain(String(raw.dropFirst(label.count)))) }
        offset = NSMaxRange(match.range)
    }
    if offset < source.length { result.append(.plain(source.substring(from: offset))) }
    return result
}

/// Only a profile path is native; X's application routes keep their existing destinations.
func xProfileHandle(_ url: URL) -> String? {
    guard ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(url.host?.lowercased() ?? "") else { return nil }
    let parts = url.path.split(separator: "/")
    guard parts.count == 1 else { return nil }
    let handle = String(parts[0])
    let reserved: Set<String> = ["home", "explore", "search", "settings", "i", "intent", "share", "login", "logout", "signup", "messages", "notifications", "compose", "jobs", "tos", "privacy", "about", "download"]
    guard !reserved.contains(handle.lowercased()), handle.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil else { return nil }
    return handle
}

struct XPostText: View {
    let text: String
    let owner: String
    var author: String? = nil
    var authorHandle: String? = nil
    var textStyle: Font.TextStyle = .callout
    var selectable = false
    var maxLines: Int? = nil
    @Environment(AppGraph.self) private var graph
    var body: some View {
        PostText(
            segments: (author.map { name in [authorHandle.map { PostTextSegment.link("@\(name)：", "https://x.com/\($0)") } ?? .plain("@\(name)：")] } ?? []) + xTextSegments(text),
            textStyle: textStyle, selectable: selectable, maxLines: maxLines, onLink: open
        )
        .foregroundStyle(AppTheme.foreground)
    }
    private func open(_ value: String) {
        guard let url = URL(string: value) else { return }
        let parts = url.pathComponents
        if ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(
            url.host?.lowercased() ?? ""),
            parts.count >= 4, parts[2] == "status", parts[3].allSatisfy(\.isNumber), !parts[3].isEmpty
        {
            graph.router.push(.xStatus(owner: owner, id: parts[3], initial: nil))
        } else if let handle = xProfileHandle(url) {
            graph.router.push(.xProfile(owner: owner, user: XProfileUser(handle: handle)))
        } else {
            graph.openExternally(url)
        }
    }
}
