import SwiftUI

/// X adapts its content to the shared card; the card knows no platform or account APIs.
struct XPostCard: View {
    let post: XPost
    let owner: String
    var detail = false
    @Environment(AppGraph.self) private var graph
    @Environment(\.displayScale) private var scale
    var body: some View {
        XPostActionHost(post: post, owner: owner) { actions in
            PostCard(
                detail: detail, activity: post.repostedBy.map { "\($0) 转发" }, onOpen: open,
                hasAside: post.quote != nil
                    || (!detail && !post.media.isEmpty),
                header: {
                    PostHeader(
                        name: post.author,
                        metadata: "@\(post.handle)"
                            + (post.createdAt.map { " · \(formatPostTime($0))" } ?? ""),
                        sourceIcon: Image("PlatformX"), sourceLabel: "X",
                        tags: post.promoted ? ["广告"] : [],
                        avatar: {
                            Group {
                                if let avatar = post.avatar {
                                    WeiboImage(url: avatar, maxPixels: 40 * scale)
                                } else {
                                    Image(systemName: "person.fill").foregroundStyle(
                                        AppTheme.secondary)
                                }
                            }.frame(width: 40, height: 40).clipShape(Circle())
                        }, badge: {},
                        menu: {})
                },
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.text).font(.callout).lineSpacing(4).foregroundStyle(
                            AppTheme.foreground
                        ).frame(maxWidth: .infinity, alignment: .leading)
                        if detail || post.quote != nil { XPostMedia(items: post.media, postID: post.originalID, owner: owner) }
                    }
                },
                aside: {
                    if let quote = post.quote {
                        QuotedPost(onOpen: {
                            graph.router.push(
                                .xStatus(
                                    owner: owner, id: quote.url.lastPathComponent, initial: nil))
                        }) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("@\(quote.author)：\(quote.text)").font(.callout).lineSpacing(4)
                                    .foregroundStyle(AppTheme.foreground)
                                XPostMedia(items: quote.media, postID: quote.url.lastPathComponent, owner: owner)
                            }
                        }
                    } else if !detail {
                        XPostMedia(items: post.media, postID: post.originalID, owner: owner)
                    }
                }, footer: { PostInteractionBar(actions: actions) })
        }
    }
    private func open() {
        graph.router.push(.xStatus(owner: owner, id: post.originalID, initial: post))
    }
}

private struct XPostMedia: View {
    let items: [MixedMedia]
    let postID: String
    let owner: String
    @Environment(AppGraph.self) private var graph
    @State private var source = UUID().uuidString
    private var pics: [PicInfo] { items.compactMap { if case .pic(let pic) = $0 { pic } else { nil } } }
    var body: some View {
        if items.count == 1, case .video(let video) = items[0] {
            VideoCover(video: video) { open(0) }
        } else if !items.isEmpty {
            PicGrid(items: items, onTap: open, sourceID: { index in
                if case .pic(let pic) = items[index] { picSourceID(source, pic) } else { "\(source):\(index)" }
            })
        }
    }
    private func open(_ index: Int) {
        let before = items.prefix(index)
        switch items[index] {
        case .pic(let pic):
            graph.router.viewer = ViewerRequest(pics: pics,
                index: before.filter { if case .pic = $0 { true } else { false } }.count,
                sourceID: picSourceID(source, pic))
        case .video(let video):
            graph.router.video = graph.xVideoRequest(owner: owner, postID: postID,
                index: before.filter { if case .video = $0 { true } else { false } }.count, known: video)
        }
    }
}

/// Keeps X-specific repost choices and network operations outside the shared visual components.
struct XPostActionHost<Content: View>: View {
    let post: XPost
    let owner: String
    var onReply: (() -> Void)?
    @ViewBuilder let content: (PostInteractionActions) -> Content
    @Environment(AppGraph.self) private var graph
    @State private var showingRepost = false
    @State private var showingQuote = false
    var body: some View {
        let state = graph.xInteractions.state(owner, post)
        let available = graph.accounts.find(owner).map { !$0.expired } == true
        content(
            PostInteractionActions(
                reposts: state.metrics.reposts, comments: state.metrics.replies,
                likes: state.metrics.likes,
                liked: state.metrics.liked, reposted: state.metrics.reposted,
                likePending: state.busy, repostPending: state.busy,
                onRepost: available ? { showingRepost = true } : nil,
                onComment: onReply ?? {
                    graph.router.push(.xStatus(owner: owner, id: post.originalID, initial: post))
                },
                onLike: available ? { write(.like) } : nil)
        )
        .confirmationDialog("转发", isPresented: $showingRepost, titleVisibility: .visible) {
            Button(state.metrics.reposted ? "取消转发" : "转发到我的时间线") { write(.repost) }
            Button("引用转发") { showingQuote = true }
        }
        .sheet(isPresented: $showingQuote) { XComposer(owner: owner, post: post, quote: true) }
    }
    private func write(_ action: XWrite) {
        Task {
            do { try await graph.xInteractions.write(owner, post: post, action: action) } catch {
                graph.toasts.showError(error, router: graph.router)
            }
        }
    }
}
