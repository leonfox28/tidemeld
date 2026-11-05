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
                    || (!detail && (!post.pictures.isEmpty || post.videoCover != nil)),
                header: {
                    PostHeader(
                        name: post.author,
                        metadata: "@\(post.handle)"
                            + (post.createdAt.map { " · \(formatPostTime($0))" } ?? ""),
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
                        menu: {
                            Menu {
                                Button("在 X 网页中打开") {
                                    graph.router.push(.accountWeb(owner, post.url))
                                }
                            } label: {
                                Image(systemName: "ellipsis").font(.body).foregroundStyle(
                                    AppTheme.secondary
                                ).frame(width: 32, height: 32).contentShape(Rectangle())
                            }.accessibilityLabel("更多选项")
                        })
                },
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(post.text).font(.callout).lineSpacing(4).foregroundStyle(
                            AppTheme.foreground
                        ).frame(maxWidth: .infinity, alignment: .leading)
                        if detail || post.quote != nil { XPostMedia(post: post, owner: owner) }
                    }
                },
                aside: {
                    if let quote = post.quote {
                        QuotedPost(onOpen: {
                            graph.router.push(
                                .xStatus(
                                    owner: owner, id: quote.url.lastPathComponent, initial: nil))
                        }) {
                            Text("@\(quote.author)：\(quote.text)").font(.callout).lineSpacing(4)
                                .foregroundStyle(AppTheme.foreground)
                        }
                    } else if !detail {
                        XPostMedia(post: post, owner: owner)
                    }
                }, footer: { PostInteractionBar(actions: actions) })
        }
    }
    private func open() {
        graph.router.push(.xStatus(owner: owner, id: post.originalID, initial: post))
    }
}

private struct XPostMedia: View {
    let post: XPost
    let owner: String
    @Environment(AppGraph.self) private var graph
    @State private var source = UUID().uuidString
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !post.pictures.isEmpty {
                PicGrid(
                    items: post.pictures.map { .pic($0) },
                    onTap: { index in
                        graph.router.viewer = ViewerRequest(
                            pics: post.pictures, index: index,
                            sourceID: picSourceID(source, post.pictures[index]))
                    }, sourceID: { picSourceID(source, post.pictures[$0]) })
            }
            if let cover = post.videoCover {
                Color.clear.aspectRatio(16.0 / 9, contentMode: .fit)
                    .overlay { WeiboImage(url: cover, maxPixels: 1200) }.overlay { PlayIcon() }
                    .clipShape(RoundedRectangle(cornerRadius: 8)).contentShape(Rectangle())
                    .onTapGesture { graph.router.push(.accountWeb(owner, post.url)) }
                    .accessibilityLabel("在 X 中播放视频")
            }
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
