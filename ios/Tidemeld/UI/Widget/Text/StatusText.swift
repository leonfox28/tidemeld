import SwiftUI

/// Status texts as parsed, so a text drawn again (as an emoticon in it loads,
/// or as its row comes back on screen) isn't parsed again; the Kotlin app keeps
/// them with `remember`.
@MainActor
private enum ParsedTexts {
    struct Key: Hashable {
        let html: String
        let urls: [URLEntity]
        let hiddenPictures: Set<String>
    }

    private static var parsed: [Key: [TextSegment]] = [:]

    static func segments(_ html: String, urls: [URLEntity], hiddenPictures: Set<String>)
        -> [TextSegment]
    {
        let key = Key(html: html, urls: urls, hiddenPictures: hiddenPictures)
        if let segments = parsed[key] { return segments }
        let segments = parseStatusText(html, urls: urls, hiddenPictures: hiddenPictures)
        // A few screens' worth; past that, started over.
        if parsed.count >= 500 { parsed.removeAll(keepingCapacity: true) }
        parsed[key] = segments
        return segments
    }
}

/// The body of a status: text with tappable links, topics, mentions and inline
/// emoticons.
struct StatusText: View {
    /// The status `text` HTML.
    let html: String
    var urls: [URLEntity] = []
    /// Ids of pictures whose links to leave out, e.g. as they show below.
    var hiddenPictures: Set<String> = []
    /// Shown as `@author：` before the text, for retweeted posts.
    var author: String? = nil
    var textStyle: Font.TextStyle = .callout
    var onLink: ((StatusLink) -> Void)? = nil
    /// Called when "展开" at the end of a truncated long post is tapped.
    var onExpand: (() -> Void)? = nil

    var body: some View {
        let source = segments
        let runs: [PostTextSegment] = source.enumerated().map { index, segment in
            switch segment {
            case .plain(let text): .plain(text)
            case .link(let text, _, let icon): .link(text, String(index), iconURL: icon)
            case .emoticon(let url, let alt): .emoticon(url: url, alt: alt)
            case .expand: .expand
            }
        }
        PostText(
            segments: runs, textStyle: textStyle,
            onLink: { key in
                guard let index = Int(key), source.indices.contains(index),
                    case .link(_, let link, _) = source[index]
                else { return }
                onLink?(link)
            }, onExpand: onExpand)
    }

    private var segments: [TextSegment] {
        var segments: [TextSegment] = []
        if let author {
            segments.append(.link("@\(author)", .mention(author)))
            segments.append(.plain("："))
        }
        return segments + ParsedTexts.segments(html, urls: urls, hiddenPictures: hiddenPictures)
    }

}
