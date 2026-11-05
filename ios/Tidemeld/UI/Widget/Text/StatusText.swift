import Observation
import SwiftUI
import UIKit

/// Emoticons and link icons, drawn at the size of the text they sit in.
///
/// Each is watched on its own: one loading redraws only the texts that have it,
/// not every text on screen with an emoticon.
@MainActor
final class InlineImages {
    @MainActor static let shared = InlineImages()

    @MainActor @Observable
    final class Slot {
        var image: UIImage?
    }

    private var slots: [String: Slot] = [:]
    private var loading: Set<String> = []

    func image(_ url: String, height: CGFloat) -> UIImage? {
        slot("\(url)#\(height)").image
    }

    /// Loads [url] for text whose glyphs are [height] high, unless it is
    /// loaded or loading.
    func load(_ url: String, height: CGFloat, scale: CGFloat) {
        let key = "\(url)#\(height)"
        let slot = slot(key)
        guard slot.image == nil, loading.insert(key).inserted else { return }
        Task {
            defer { loading.remove(key) }
            guard let source = try? await ImageLoader.shared.image(url, maxPixels: height * scale * 2)
            else { return }
            let size = CGSize(
                width: height * source.size.width / max(source.size.height, 1), height: height)
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            slot.image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    private func slot(_ key: String) -> Slot {
        if let slot = slots[key] { return slot }
        let slot = Slot()
        slots[key] = slot
        return slot
    }
}

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

    static func segments(_ html: String, urls: [URLEntity], hiddenPictures: Set<String>) -> [TextSegment] {
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

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var scale

    var body: some View {
        let segments = self.segments
        let images = InlineImages.shared
        let height = glyphHeight
        compose(segments, images: images, height: height)
            .font(.system(textStyle))
            .lineSpacing(textStyle == .callout ? 4 : 2)
            .tint(AppTheme.accent)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard url.scheme == "tidemeld-segment", let index = Int(url.host ?? "") else {
                        return .systemAction
                    }
                    switch segments[index] {
                    case .link(_, let link, _): onLink?(link)
                    case .expand: onExpand?()
                    default: break
                    }
                    return .handled
                }
            )
            .task(id: "\(html)#\(height)") {
                for segment in segments {
                    switch segment {
                    case .emoticon(let url, _), .link(_, _, let url?):
                        images.load(url, height: height, scale: scale)
                    default: break
                    }
                }
            }
    }

    private var segments: [TextSegment] {
        var segments: [TextSegment] = []
        if let author {
            segments.append(.link("@\(author)", .mention(author)))
            segments.append(.plain("："))
        }
        return segments + ParsedTexts.segments(html, urls: urls, hiddenPictures: hiddenPictures)
    }

    /// How high an emoticon is: a little above the text's cap height, as on
    /// Weibo.
    private var glyphHeight: CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let font = UIFont.preferredFont(forTextStyle: UIFont.TextStyle(textStyle), compatibleWith: traits)
        return (font.pointSize * 1.2).rounded()
    }

    /// The segments as one text: runs of words and links as attributed
    /// strings, with emoticons as images between them.
    private func compose(_ segments: [TextSegment], images: InlineImages, height: CGFloat) -> Text {
        var text = Text(verbatim: "")
        var run = AttributedString()
        func flush() {
            guard !run.characters.isEmpty else { return }
            text = Text("\(text)\(Text(run))")
            run = AttributedString()
        }
        func image(_ image: UIImage) {
            flush()
            // Centred on the text rather than sat on its baseline.
            let glyph = Text(Image(uiImage: image)).baselineOffset(-height * 0.2)
            text = Text("\(text)\(glyph)")
        }
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .plain(let plain):
                run += AttributedString(plain)
            case .link(let label, _, let icon):
                if let icon, let loaded = images.image(icon, height: height) { image(loaded) }
                var link = AttributedString(label)
                link.link = URL(string: "tidemeld-segment://\(index)")
                link.foregroundColor = AppTheme.accent
                run += link
            case .emoticon(let url, let alt):
                if let loaded = images.image(url, height: height) {
                    image(loaded)
                } else {
                    run += AttributedString(alt)
                }
            case .expand:
                var expand = AttributedString("展开")
                expand.link = URL(string: "tidemeld-segment://\(index)")
                expand.foregroundColor = AppTheme.accent
                run += expand
            }
        }
        flush()
        return text
    }
}

extension UIFont.TextStyle {
    init(_ style: Font.TextStyle) {
        switch style {
        case .largeTitle: self = .largeTitle
        case .title: self = .title1
        case .title2: self = .title2
        case .title3: self = .title3
        case .headline: self = .headline
        case .subheadline: self = .subheadline
        case .callout: self = .callout
        case .footnote: self = .footnote
        case .caption: self = .caption1
        case .caption2: self = .caption2
        default: self = .body
        }
    }
}
