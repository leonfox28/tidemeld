import SwiftUI

private let gridGap: CGFloat = 4
private let maxShown = 9

/// The pictures of a status: one sized to its shape, otherwise a grid of square
/// cells (2×2 for four, three columns else, at most nine). Posts mixing
/// pictures and videos show both in it.
struct PicGrid: View {
    let items: [MixedMedia]
    /// How many items the status has; beyond nine shows as "+N".
    var total: Int? = nil
    /// Called with the index in [items].
    var onTap: ((Int) -> Void)? = nil
    /// Where a tapped picture zooms out of, by its index.
    var sourceID: ((Int) -> String)? = nil

    @Environment(\.mediaNamespace) private var namespace

    var body: some View {
        let shown = Array(items.prefix(maxShown))
        let hidden = (total ?? items.count) - shown.count
        PicGridLayout(count: shown.count, singleRatio: items.count == 1 ? aspectRatio(items[0]) : nil) {
            ForEach(shown.indices, id: \.self) { i in
                MediaTile(item: shown[i], long: items.count == 1)
                    .overlay {
                        if i == shown.count - 1, hidden > 0 {
                            Text("+\(hidden)")
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.black.opacity(0.45))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(RoundedRectangle(cornerRadius: 4))
                    .onTapGesture { onTap?(i) }
                    .modifier(TransitionSource(id: sourceID?(i), namespace: namespace))
            }
        }
    }

    private func aspectRatio(_ item: MixedMedia) -> Double {
        switch item {
        case .pic(let pic): pic.aspectRatio ?? 1
        case .video(let video): video.aspectRatio ?? 1
        }
    }
}

/// Marks a view as where a zoom transition starts, when it has an id.
struct TransitionSource: ViewModifier {
    let id: String?
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let id, let namespace {
            content.environment(\.imageTransitionSourceID, id)
                .matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    /// Where pictures and videos zoom out of into their viewers.
    @Entry var mediaNamespace: Namespace.ID? = nil
}

/// Lays out one item sized to its shape (extreme shapes cropped) at 70% of the
/// width, or square cells in rows that share the width.
private struct PicGridLayout: Layout {
    let count: Int
    let singleRatio: Double?

    private var columns: Int { count == 4 ? 2 : 3 }

    private func cell(_ width: CGFloat) -> CGFloat { (width - gridGap * 2) / 3 }

    private func singleSize(_ width: CGFloat) -> CGSize {
        let ratio = min(max(singleRatio ?? 1, 0.6), 1.8)
        let side = width * 0.7
        return ratio >= 1 ? CGSize(width: side, height: side / ratio) : CGSize(width: side * ratio, height: side)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        if count == 1 { return CGSize(width: width, height: singleSize(width).height) }
        let rows = (count + columns - 1) / columns
        let cell = cell(width)
        return CGSize(width: width, height: CGFloat(rows) * cell + CGFloat(max(0, rows - 1)) * gridGap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if count == 1, let first = subviews.first {
            let size = singleSize(bounds.width)
            first.place(at: bounds.origin, proposal: ProposedViewSize(size))
            return
        }
        let cell = cell(bounds.width)
        for (i, subview) in subviews.enumerated() {
            let row = i / columns
            let column = i % columns
            subview.place(
                at: CGPoint(
                    x: bounds.minX + CGFloat(column) * (cell + gridGap),
                    y: bounds.minY + CGFloat(row) * (cell + gridGap)),
                proposal: ProposedViewSize(width: cell, height: cell))
        }
    }
}

/// A picture or a video cover, with its badge; the size it is given picks the
/// picture's rendition.
private struct MediaTile: View {
    let item: MixedMedia
    /// A single item, which shows the top of a long picture.
    let long: Bool

    @Environment(AppGraph.self) private var graph
    @Environment(\.displayScale) private var scale

    var body: some View {
        GeometryReader { geo in
            switch item {
            case .pic(let pic): picture(pic, geo.size)
            case .video(let video): videoCover(video, geo.size)
            }
        }
    }

    private func picture(_ pic: PicInfo, _ size: CGSize) -> some View {
        let quality = graph.settings.settings.imageQuality
        let pixels = quality.listPixels(min(size.width, size.height), scale: scale)
        let variant = pic.variant(for: pixels)
        let badge: String? =
            pic.type == .gif ? "GIF" : pic.type == .livePhoto ? "实况" : pic.isLong ? "长图" : nil
        return WeiboImage(
            url: variant.url,
            // A long picture shows its top across the width.
            maxPixels: pic.isLong
                ? min(4096, size.width * scale / (pic.aspectRatio ?? 1))
                : max(size.width, size.height) * scale,
            alignment: pic.isLong ? .top : .center
        )
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottomTrailing) {
            if let badge { MediaBadge(label: badge).padding(4) }
        }
    }

    private func videoCover(_ video: VideoInfo, _ size: CGSize) -> some View {
        WeiboImage(url: video.coverURL, maxPixels: max(size.width, size.height) * scale)
            .frame(width: size.width, height: size.height)
            .overlay { PlayIcon(size: 36) }
            .overlay(alignment: .bottomTrailing) {
                if let duration = video.duration, duration > 0 {
                    MediaBadge(label: formatDuration(duration)).padding(4)
                }
            }
    }
}
