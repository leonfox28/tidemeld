import SwiftUI

/// What tapping parts of a status (or comment) leads to. A nil callback leaves
/// its target inert.
struct StatusCardActions {
    /// The card itself, or the retweeted post inside it.
    var onOpen: ((Status) -> Void)? = nil
    var onLink: ((StatusLink) -> Void)? = nil
    var onUser: ((WeiboUser) -> Void)? = nil
    /// "展开" on a truncated long post.
    var onExpand: ((Status) -> Void)? = nil
    /// A picture, among the pictures; the status they belong to (none for a
    /// comment's) is where the viewer gets a live photo's video afresh once its
    /// URL has expired. The last is the id of the tile it zooms out of.
    var onPicture: ((_ pics: [PicInfo], _ index: Int, _ status: Status?, _ source: String?) -> Void)? = nil
    /// A video; the index picks one in a post mixing pictures and videos.
    var onVideo: ((_ status: Status, _ index: Int?) -> Void)? = nil
    /// The repost count, which reposts the card's post.
    var onRepost: ((Status) -> Void)? = nil
    /// Deleting a post of the signed-in user's, offered on their posts only.
    var onDelete: ((Status) -> Void)? = nil
}

/// Beside media the text keeps to about a phone's width of line; the media
/// takes the rest.
private let wideMainWidth: CGFloat = 400
private let wideAsideGap: CGFloat = 24
/// With no media, the longest line the text runs to.
private let wideMainAloneWidth: CGFloat = 640
/// From this width a card puts its media beside its text.
let wideCardFrom: CGFloat = 840

/// A status as shown in a timeline, or atop its detail page when [detail],
/// where the card itself isn't tappable and the counts move to the page's tabs.
///
/// Wide, as a wide window's timeline gives it, a timeline card puts its
/// pictures, video or retweeted post beside its text rather than under it.
struct StatusCard: View {
    let status: Status
    var actions = StatusCardActions()
    var detail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !detail, let activity = status.activity { ActivityLine(label: activity) }
            if detail {
                StatusHeader(status: status, actions: actions)
                StatusBody(status: status, actions: actions, selectable: true)
                if let retweeted = status.retweeted { RetweetedView(status: retweeted, actions: actions) }
            } else {
                CardLayout(hasAside: status.retweeted != nil || hasMedia(status)) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusHeader(status: status, actions: actions)
                        // A retweet's own pictures, if it has any, stay with its text.
                        StatusBody(status: status, actions: actions, withMedia: status.retweeted != nil)
                    }
                    StatusCounts(status: status, actions: actions)
                    if let retweeted = status.retweeted {
                        RetweetedView(status: retweeted, actions: actions)
                    } else if hasMedia(status) {
                        StatusMedia(status: status, actions: actions)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, detail ? 12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            if !detail { actions.onOpen?(status) }
        }
    }
}

/// A timeline card's text, its counts and its media, if any. Narrow, they go
/// one under another (text, media, counts). Wide, the media goes to the right
/// of the text and counts; the counts come right after the text, or at the foot
/// of the card if the media runs further down.
private struct CardLayout: Layout {
    let hasAside: Bool

    private func widths(_ width: CGFloat) -> (wide: Bool, main: CGFloat, aside: CGFloat) {
        // The card's own padding counts towards the width a card is given.
        let wide = width + 32 >= wideCardFrom
        guard wide else { return (false, width, width) }
        let main = min(width, hasAside ? wideMainWidth : wideMainAloneWidth)
        return (true, main, max(0, width - wideAsideGap - main))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let w = widths(width)
        let main = subviews[0].sizeThatFits(ProposedViewSize(width: w.main, height: nil)).height
        let footer = subviews[1].sizeThatFits(ProposedViewSize(width: w.main, height: nil)).height
        let aside = subviews.count > 2
            ? subviews[2].sizeThatFits(ProposedViewSize(width: w.aside, height: nil)).height : nil
        if w.wide {
            return CGSize(width: width, height: max(main + footer, aside.map { $0 + 12 } ?? 0))
        }
        return CGSize(width: width, height: main + footer + (aside.map { $0 + 8 } ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = widths(bounds.width)
        let mainProposal = ProposedViewSize(width: w.main, height: nil)
        let main = subviews[0].sizeThatFits(mainProposal).height
        let footer = subviews[1].sizeThatFits(mainProposal).height
        subviews[0].place(at: bounds.origin, proposal: mainProposal)
        let asideProposal = ProposedViewSize(width: w.aside, height: nil)
        if w.wide {
            subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - footer), proposal: mainProposal)
            if subviews.count > 2 {
                subviews[2].place(
                    at: CGPoint(x: bounds.minX + w.main + wideAsideGap, y: bounds.minY), proposal: asideProposal)
            }
        } else {
            var y = bounds.minY + main
            if subviews.count > 2 {
                let aside = subviews[2].sizeThatFits(asideProposal).height
                subviews[2].place(at: CGPoint(x: bounds.minX, y: y + 8), proposal: asideProposal)
                y += 8 + aside
            }
            subviews[1].place(at: CGPoint(x: bounds.minX, y: y), proposal: mainProposal)
        }
    }
}

/// `Status.activity`, above the card, so a post by someone else on a user's
/// profile doesn't pass for theirs.
private struct ActivityLine: View {
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            if label.contains("赞") {
                Image(systemName: "hand.thumbsup").font(.caption)
            } else if label.contains("评论") {
                Image(systemName: "bubble.right").font(.caption)
            }
            Text(label).font(.footnote).lineLimit(1)
        }
        .foregroundStyle(AppTheme.secondary)
    }
}

struct StatusHeader: View {
    let status: Status
    let actions: StatusCardActions

    @Environment(AppGraph.self) private var graph

    var body: some View {
        let user = status.user
        let meta = [
            status.createdAt.map { formatPostTime($0) }, status.source.map { "来自 \($0)" }, status.region,
        ].compactMap { $0 }.joined(separator: "  ")
        let tags = [
            status.pinned ? "置顶" : nil,
            status.visibility != .public ? status.visibility.label : nil,
            status.isAd ? "广告" : nil,
        ].compactMap { $0 }
        HStack(spacing: 10) {
            UserAvatar(user: user, onTap: actions.onUser)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(user?.screenName ?? "微博用户")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                        .lineLimit(1)
                        .onTapGesture {
                            if let user { actions.onUser?(user) }
                        }
                    if let verified = user?.verifiedType, showsVerified(verified) {
                        VerifiedIcon(verifiedType: verified)
                    }
                }
                if !meta.isEmpty {
                    Text(meta).font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            ForEach(tags, id: \.self) { TagLabel(text: $0) }
            if let onDelete = actions.onDelete, let user, user.id == graph.session.state.uid {
                Menu {
                    Button("删除", systemImage: "trash", role: .destructive) { onDelete(status) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body)
                        .foregroundStyle(AppTheme.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("更多")
            }
        }
    }
}

/// The pictures, video or linked page of a status, if it has any.
func hasMedia(_ status: Status) -> Bool {
    let isRetweet = status.retweeted != nil
    return !status.pics.isEmpty || !status.mixedMedia.isEmpty
        || (!isRetweet && (status.video != nil || status.pageCard != nil))
}

/// Text and media of a status, or of the post it retweets when [nested];
/// without [withMedia], only the text, the media being shown elsewhere.
struct StatusBody: View {
    let status: Status
    let actions: StatusCardActions
    var nested = false
    var withMedia = true
    var selectable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !status.text.isEmpty || (nested && status.user != nil) {
                StatusText(
                    html: status.text, urls: status.urls,
                    author: nested ? status.user?.screenName : nil,
                    onLink: actions.onLink,
                    onExpand: actions.onExpand.map { onExpand in { onExpand(status) } }
                )
                .foregroundStyle(AppTheme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(Selectable(enabled: selectable))
            }
            if withMedia, hasMedia(status) { StatusMedia(status: status, actions: actions) }
        }
    }
}

private struct Selectable: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled { content.textSelection(.enabled) } else { content }
    }
}

struct StatusMedia: View {
    let status: Status
    let actions: StatusCardActions

    var body: some View {
        // A retweet carries a copy of its source's page_info; show it only
        // once, inside the retweeted post.
        let isRetweet = status.retweeted != nil
        if !status.pics.isEmpty {
            PicGrid(
                items: status.pics.map(MixedMedia.pic), total: status.picCount,
                onTap: { i in
                    actions.onPicture?(status.pics, i, status, picSourceID(status.id, status.pics[i]))
                },
                sourceID: { i in picSourceID(status.id, status.pics[i]) })
        } else if !status.mixedMedia.isEmpty {
            mixedGrid
        } else if !isRetweet, let video = status.video {
            VideoCover(video: video) { actions.onVideo?(status, nil) }
        } else if !isRetweet, let card = status.pageCard {
            PageCardView(card: card)
        }
    }

    // Pictures open in the viewer among the post's other pictures; videos play
    // by their place among its videos.
    private var mixedGrid: some View {
        let items = status.mixedMedia
        func picIndex(_ i: Int) -> Int {
            items.prefix(i).filter { if case .pic = $0 { true } else { false } }.count
        }
        return PicGrid(
            items: items, total: status.picCount,
            onTap: { i in
                let before = items.prefix(i)
                switch items[i] {
                case .pic(let pic):
                    actions.onPicture?(status.mixedPics, picIndex(i), status, picSourceID(status.id, pic))
                case .video:
                    actions.onVideo?(status, before.filter { if case .video = $0 { true } else { false } }.count)
                }
            },
            sourceID: { i in
                if case .pic(let pic) = items[i] { picSourceID(status.id, pic) } else { "\(status.id)/v\(i)" }
            })
    }
}

/// The id a picture's tile goes by, for the viewer to zoom out of it.
func picSourceID(_ owner: String, _ pic: PicInfo) -> String { "\(owner)/\(pic.id)" }

private struct VideoCover: View {
    let video: VideoInfo
    let onTap: () -> Void
    @Environment(\.displayScale) private var scale

    var body: some View {
        // Portrait videos are cropped square to keep the timeline compact.
        let ratio = min(max(video.aspectRatio ?? 16.0 / 9, 1), 16.0 / 9)
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { WeiboImage(url: video.coverURL, maxPixels: 1200) }
            .overlay { PlayIcon() }
            .overlay(alignment: .bottomTrailing) {
                if let duration = video.duration, duration > 0 {
                    MediaBadge(label: formatDuration(duration)).padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(perform: onTap)
    }
}

private struct PageCardView: View {
    let card: PageCard
    @Environment(\.displayScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            if let image = card.imageURL {
                WeiboImage(url: image, maxPixels: 64 * scale).frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title).font(.subheadline.weight(.medium)).lineLimit(1)
                if let description = card.description {
                    Text(description).font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(2)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppTheme.foreground)
        .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct RetweetedView: View {
    let status: Status
    let actions: StatusCardActions

    var body: some View {
        // Deleted or hidden posts come without an author or time and can't be
        // opened; those in `statuses/mentions` may lack only the author.
        let canOpen = actions.onOpen != nil && (status.user != nil || status.createdAt != nil)
        StatusBody(status: status, actions: actions, nested: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture {
                if canOpen { actions.onOpen?(status) }
            }
    }
}

/// Repost, comment and like counts; the repost count is a repost button and the
/// like count a like button.
struct StatusCounts: View {
    let status: Status
    let actions: StatusCardActions

    @Environment(AppGraph.self) private var graph

    var body: some View {
        let target = LikeTarget(kind: .status, id: status.id)
        let shown = graph.likes.shown(target, loaded: status.like)
        HStack(spacing: 0) {
            CountButton(symbol: "arrow.2.squarepath", count: status.repostsCount, label: "转发") {
                actions.onRepost?(status)
            }
            // Opens the status, as the card does.
            CountButton(symbol: "bubble.right", count: status.commentsCount, label: "评论") {
                actions.onOpen?(status)
            }
            CountButton(
                symbol: shown.like.liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                count: shown.like.count, label: "赞", tint: shown.like.liked ? AppTheme.primary : nil
            ) {
                // While a like is on its way, the button takes no taps but still
                // swallows them, so they don't open the status.
                guard !shown.pending else { return }
                graph.toggleLike(target, loaded: status.like)
            }
            .sensoryFeedback(.selection, trigger: shown.like.liked)
        }
    }
}

private struct CountButton: View {
    let symbol: String
    let count: Int
    let label: String
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.footnote)
                Text(count > 0 ? formatCount(count) : label).font(.footnote).monospacedDigit()
            }
            .foregroundStyle(tint ?? AppTheme.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "\(label) \(count)" : label)
    }
}
