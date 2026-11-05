import Foundation

/// A piece of a status body.
enum TextSegment: Sendable, Hashable {
    case plain(String)
    /// [iconURL]: the small type icon Weibo puts before some links (web page,
    /// video, …).
    case link(String, StatusLink, iconURL: String? = nil)
    /// An inline emoticon image such as `[doge]`.
    case emoticon(url: String, alt: String)
    /// The "展开" marker at the end of a truncated long post.
    case expand
}

/// Where a link in a status body leads.
enum StatusLink: Sendable, Hashable {
    case mention(String)
    /// A `#话题#`, without the surrounding `#`.
    case topic(String)
    /// Pictures linked from the text rather than attached, such as those of a
    /// repost along the chain (`查看2张图片`); [pics] are empty when the URL
    /// isn't a picture on Weibo's image hosts.
    case image(URL, [PicInfo])
    case web(URL)
}

/// Splits the HTML `text` of a status into segments.
///
/// Weibo's markup is loose (e.g. unquoted `href` values), which the parser
/// tolerates. [urls] resolves `t.cn` short links. Links to the pictures with
/// ids in [hiddenPictures] are left out with their label.
func parseStatusText(
    _ text: String, urls: [URLEntity] = [], hiddenPictures: Set<String> = []
) -> [TextSegment] {
    var segments: [TextSegment] = []
    func addText(_ s: String) {
        guard !s.isEmpty else { return }
        if case .plain(let last) = segments.last {
            segments[segments.count - 1] = .plain(last + s)
        } else {
            segments.append(.plain(s))
        }
    }
    func visit(_ node: HTMLNode) {
        switch node {
        case .text(let text): addText(text)
        case .element(let e):
            if e.name == "br" {
                addText("\n")
            } else if e.name == "img" {
                let alt = e.has("alt") ? e.attr("alt") : e.attr("title")
                if let url = readURL(e.attr("src")) {
                    segments.append(.emoticon(url: url, alt: alt))
                } else {
                    addText(alt)
                }
            } else if e.name == "span", e.hasClass("expand") {
                segments.append(.expand)
            } else if e.name == "a", e.has("data-pid"), hiddenPictures.contains(e.attr("data-pid")) {
                return
            } else if e.name == "a" {
                let label = e.wholeText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let link = linkOf(e, label: label, urls: urls), !label.isEmpty {
                    let icon = e.first("img", className: "icon-link")
                    segments.append(.link(label, link, iconURL: icon.flatMap { readURL($0.attr("src")) }))
                } else {
                    addText(e.wholeText)
                }
            } else {
                e.children.forEach(visit)
            }
        }
    }
    parseHTMLFragment(text).forEach(visit)
    return segments
}

/// The HTML `text` of a status or comment as one line of plain text, for
/// previews: emoticons become their `[name]`, line breaks spaces.
func plainStatusText(_ text: String) -> String {
    parseStatusText(text).map { segment in
        switch segment {
        case .plain(let text): text
        case .link(let text, _, _): text
        case .emoticon(_, let alt): alt
        case .expand: ""
        }
    }
    .joined()
    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    .trimmingCharacters(in: .whitespaces)
}

private func linkOf(_ a: HTMLElement, label: String, urls: [URLEntity]) -> StatusLink? {
    let href = a.attr("href").trimmingCharacters(in: .whitespaces)
    guard !href.isEmpty else { return nil }

    // Mentions: <a href=/n/name usercard="name=name">@name</a>
    if a.has("usercard") || href.hasPrefix("/n/") {
        let name = label.hasPrefix("@") ? String(label.dropFirst()) : label
        return name.isEmpty ? nil : .mention(name)
    }

    let absolute =
        href.hasPrefix("//") ? "https:" + href : href.hasPrefix("/") ? "https://weibo.com" + href : href
    // App-only schemes such as sinaweibo:// can't be opened; keep them as text.
    guard let url = webURL(absolute) else { return nil }
    let host = url.host ?? ""

    if host == "s.weibo.com", label.count >= 2, label.hasPrefix("#"), label.hasSuffix("#") {
        let topic = String(label.dropFirst().dropLast())
        if !topic.isEmpty { return .topic(topic) }
    }
    if a.has("data-pids") || a.has("data-pid") || host.hasSuffix(".sinaimg.cn") {
        return .image(url, linkedPics(a, url: url, urls: urls))
    }
    if host == "t.cn" {
        for entity in urls {
            guard let long = entity.longURL.flatMap(webURL) else { continue }
            if sameURL(entity.shortURL, url) { return .web(long) }
        }
    }
    return .web(url)
}

/// [string] as an http(s) URL, or nil.
func webURL(_ string: String) -> URL? {
    guard let url = URL(string: string) ?? URL(string: string.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? ""),
        let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
    else { return nil }
    return url
}

// A link to several pictures names them all in `data-pids` but links to the
// first; one to a single picture may name it in `data-pid`. The url_struct
// entry of the link has them in full; failing that, they are built from their
// pids, or the link itself.
private func linkedPics(_ a: HTMLElement, url: URL, urls: [URLEntity]) -> [PicInfo] {
    let pids = (a.attr("data-pids").split(separator: ",").map(String.init) + [a.attr("data-pid")])
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    var known: [String: PicInfo] = [:]
    for pic in urls.flatMap(\.pics) { known[pic.id] = pic }
    var seen = Set<String>()
    let pics = pids.filter { seen.insert($0).inserted }.compactMap { known[$0] ?? PicInfo.fromPid($0) }
    if !pics.isEmpty { return pics }
    if (url.host ?? "").hasSuffix(".sinaimg.cn") { return [PicInfo.fromURL(url.absoluteString)] }
    return []
}

private func sameURL(_ short: String, _ url: URL) -> Bool {
    guard let parsed = URL(string: short) else { return false }
    return parsed.host == url.host && parsed.path == url.path
}
