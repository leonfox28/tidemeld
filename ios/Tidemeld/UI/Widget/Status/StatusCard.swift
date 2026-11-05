import SwiftUI

/// What tapping parts of a status (or comment) leads to. A nil callback leaves
/// its target inert.
struct StatusCardActions {
    var onLike: ((Status) -> Void)? = nil
    /// The card itself, or the retweeted post inside it.
    var onOpen: ((Status) -> Void)? = nil
    var onLink: ((StatusLink) -> Void)? = nil
    var onUser: ((WeiboUser) -> Void)? = nil
    /// "展开" on a truncated long post.
    var onExpand: ((Status) -> Void)? = nil
    /// A picture, among the pictures; the status they belong to (none for a
    /// comment's) is where the viewer gets a live photo's video afresh once its
    /// URL has expired. The last is the id of the tile it zooms out of.
    var onPicture:
        ((_ pics: [PicInfo], _ index: Int, _ status: Status?, _ source: String?) -> Void)? = nil
    /// A video; the index picks one in a post mixing pictures and videos.
    var onVideo: ((_ status: Status, _ index: Int?) -> Void)? = nil
    /// The repost count, which reposts the card's post.
    var onRepost: ((Status) -> Void)? = nil
    /// Deleting a post of the signed-in user's, offered on their posts only.
    var onDelete: ((Status) -> Void)? = nil
}

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
        PostCard(
            detail: detail, activity: status.activity,
            onOpen: actions.onOpen.map { open in { open(status) } },
            hasAside: status.retweeted != nil || (!detail && hasMedia(status)),
            header: { StatusHeader(status: status, actions: actions) },
            content: {
                StatusBody(
                    status: status, actions: actions, withMedia: detail || status.retweeted != nil,
                    selectable: detail)
            },
            aside: {
                if let retweeted = status.retweeted {
                    RetweetedView(status: retweeted, actions: actions)
                } else if !detail, hasMedia(status) {
                    StatusMedia(status: status, actions: actions)
                }
            },
            footer: { StatusCounts(status: status, actions: actions) })
    }
}

struct StatusHeader: View {
    let status: Status
    let actions: StatusCardActions

    @Environment(AppGraph.self) private var graph

    var body: some View {
        let user = status.user
        let meta = [
            status.createdAt.map { formatPostTime($0) }, status.source.map { "来自 \($0)" },
            status.region,
        ].compactMap { $0 }.joined(separator: "  ")
        let tags = [
            status.pinned ? "置顶" : nil,
            status.visibility != .public ? status.visibility.label : nil,
            status.isAd ? "广告" : nil,
        ].compactMap { $0 }
        PostHeader(
            name: user?.screenName ?? "微博用户", metadata: meta, tags: tags,
            onAuthor: user.flatMap { user in actions.onUser.map { action in { action(user) } } },
            avatar: { UserAvatar(user: user, onTap: actions.onUser) },
            badge: {
                if let verified = user?.verifiedType, showsVerified(verified) {
                    VerifiedIcon(verifiedType: verified)
                }
            },
            menu: {
                if let onDelete = actions.onDelete, let user, user.id == graph.session.state.uid {
                    Menu {
                        Button("删除", systemImage: "trash", role: .destructive) { onDelete(status) }
                    } label: {
                        Image(systemName: "ellipsis").font(.body).foregroundStyle(
                            AppTheme.secondary
                        ).frame(width: 32, height: 32).contentShape(Rectangle())
                    }.accessibilityLabel("更多")
                }
            })
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
    /// What its tiles' ids start with: this card's own, as the same post can
    /// show twice at once (two reposts of it, or a card under its own detail
    /// page), and the viewer should zoom out of the tile tapped.
    @State private var owner = UUID().uuidString

    var body: some View {
        // A retweet carries a copy of its source's page_info; show it only
        // once, inside the retweeted post.
        let isRetweet = status.retweeted != nil
        if !status.pics.isEmpty {
            PicGrid(
                items: status.pics.map(MixedMedia.pic), total: status.picCount,
                onTap: { i in
                    actions.onPicture?(status.pics, i, status, picSourceID(owner, status.pics[i]))
                },
                sourceID: { i in picSourceID(owner, status.pics[i]) })
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
                    actions.onPicture?(
                        status.mixedPics, picIndex(i), status, picSourceID(owner, pic))
                case .video:
                    actions.onVideo?(
                        status, before.filter { if case .video = $0 { true } else { false } }.count)
                }
            },
            sourceID: { i in
                if case .pic(let pic) = items[i] {
                    picSourceID(owner, pic)
                } else {
                    "\(owner)/v\(i)"
                }
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
                    Text(description).font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(
                        2)
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
        QuotedPost(onOpen: canOpen ? { actions.onOpen?(status) } : nil) {
            StatusBody(status: status, actions: actions, nested: true)
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
        PostInteractionBar(
            actions: PostInteractionActions(
                reposts: status.repostsCount, comments: status.commentsCount,
                likes: shown.like.count,
                liked: shown.like.liked, likePending: shown.pending,
                onRepost: actions.onRepost.map { action in { action(status) } },
                onComment: actions.onOpen.map { action in { action(status) } },
                onLike: {
                    if let onLike = actions.onLike {
                        onLike(status)
                    } else {
                        graph.toggleLike(target, loaded: status.like)
                    }
                }))
    }
}
