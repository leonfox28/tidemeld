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

/// Platform-independent runs. Link IDs are interpreted only by the adapter.
enum PostTextSegment: Sendable, Hashable {
    case plain(String)
    case link(String, String, iconURL: String? = nil)
    case emoticon(url: String, alt: String)
    case expand
}

struct PostText: View {
    let segments: [PostTextSegment]
    var textStyle: Font.TextStyle = .callout
    var selectable = false
    var maxLines: Int? = nil
    var onLink: ((String) -> Void)? = nil
    var onExpand: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.displayScale) private var scale

    var body: some View {
        let images = InlineImages.shared
        let height = glyphHeight
        compose(segments, images: images, height: height)
            .font(.system(textStyle))
            .lineLimit(maxLines)
            .textRenderer(PostInlineImageRenderer())
            .modifier(PostTextSelection(enabled: selectable))
            .lineSpacing(textStyle == .callout ? 4 : 2)
            // Wrap to the available width without accepting a height that clips partial lines.
            // Explicit preview line limits still apply.
            .fixedSize(horizontal: false, vertical: true)
            .tint(AppTheme.accent)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard url.scheme == "tidemeld-segment", let index = Int(url.host ?? "") else {
                        return .systemAction
                    }
                    guard segments.indices.contains(index) else { return .handled }
                    switch segments[index] {
                    case .link(_, let link, _): onLink?(link)
                    case .expand: onExpand?()
                    default: break
                    }
                    return .handled
                }
            )
            .task(id: "\(segments.hashValue)#\(height)") {
                for segment in segments {
                    switch segment {
                    case .emoticon(let url, _), .link(_, _, let url?):
                        images.load(url, height: height, scale: scale)
                    default: break
                    }
                }
            }
    }

    /// How high an emoticon is: a little above the text's cap height, as on
    /// Weibo.
    private var glyphHeight: CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize))
        let font = UIFont.preferredFont(
            forTextStyle: UIFont.TextStyle(textStyle), compatibleWith: traits)
        return (font.pointSize * 1.2).rounded()
    }

    /// Keep inline images in the font's line box. Text(Image) plus a baseline
    /// offset adds its own ascent and descent, making image-bearing lines taller.
    private func compose(_ segments: [PostTextSegment], images: InlineImages, height: CGFloat) -> Text {
        var text = Text(verbatim: "")
        var run = AttributedString()
        func flush() {
            guard !run.characters.isEmpty else { return }
            text = Text("\(text)\(Text(run))")
            run = AttributedString()
        }
        func image(_ image: UIImage, id: Int, label: String = "") {
            flush()
            // The object replacement character has zero advance. Reserve the image's
            // width while retaining the surrounding font's ascent and descent.
            let glyph = Text(verbatim: "\u{FFFC}").kerning(image.size.width)
                .customAttribute(PostInlineImage(id: id, image: image))
                .accessibilityLabel(label)
            text = Text("\(text)\(glyph)")
        }
        for (index, segment) in segments.enumerated() {
            switch segment {
            case .plain(let plain):
                run += AttributedString(plain)
            case .link(let label, _, let icon):
                if let icon, let loaded = images.image(icon, height: height) { image(loaded, id: index) }
                var link = AttributedString(label)
                link.link = URL(string: "tidemeld-segment://\(index)")
                link.foregroundColor = AppTheme.accent
                run += link
            case .emoticon(let url, let alt):
                if let loaded = images.image(url, height: height) {
                    image(loaded, id: index, label: alt)
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

private struct PostInlineImage: TextAttribute {
    // Distinct IDs keep consecutive copies of an emoticon in separate runs.
    let id: Int
    let image: UIImage
}

private struct PostInlineImageRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if let attachment = run[PostInlineImage.self] {
                    let bounds = run.typographicBounds.rect
                    let size = attachment.image.size
                    let height = min(size.height, bounds.height)
                    let width = size.width * height / size.height
                    context.draw(Image(uiImage: attachment.image), in: CGRect(
                        x: bounds.midX - width / 2, y: bounds.midY - height / 2,
                        width: width, height: height))
                } else {
                    context.draw(run)
                }
            }
        }
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

private struct PostTextSelection: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.textSelection(.enabled) } else { content }
    }
}
