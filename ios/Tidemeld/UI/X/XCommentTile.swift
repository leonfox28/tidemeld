import SwiftUI

/// X supplies replies to the same compact comment row as Weibo.
struct XCommentTile: View {
    let post: XPost
    let owner: String
    var authorHandle: String?
    var preview: [XPost] = []
    var onSent: (() -> Void)?
    @Environment(AppGraph.self) private var graph
    @State private var showingReply = false

    var body: some View {
        PostContentFilter(text: ([post.contentFilterText] + preview.map(\.contentFilterText)).joined(separator: "\n"), owner: owner, authors: post.contentAuthorIDs + preview.flatMap(\.contentAuthorIDs)) { unfilteredContent }
    }

    @ViewBuilder private var unfilteredContent: some View {
        XPostActionHost(post: post, owner: owner, onReply: { showingReply = true }) { actions in
            PostComment(
                author: post.author,
                metadata: [post.createdAt.map { formatPostTime($0) }, "@\(post.handle)"].compactMap { $0 }
                    .joined(separator: "  "),
                isAuthor: authorHandle != nil && post.handle.lowercased() == authorHandle?.lowercased(),
                onAuthor: openAuthor,
                onReply: { showingReply = true },
                menuActions: graph.xSafetyActions(post: post, owner: owner),
                avatar: { PostAvatar(url: post.avatar, label: post.author, size: 32, onTap: openAuthor) },
                content: {
                    if !post.text.isEmpty {
                        XPostText(text: post.text, owner: owner)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    XPostMedia(items: post.media, postID: post.originalID, owner: owner, sensitive: post.sensitive, compact: true)
                    if let quote = post.quote?.post {
                        QuotedPost(onOpen: {
                            graph.router.push(
                                .xStatus(owner: owner, id: quote.originalID, initial: quote))
                        }) {
                            VStack(alignment: .leading, spacing: 6) {
                                if let reference = xReplyReference(
                                    quote.replyTo, handles: quote.replyToHandles,
                                    owner: owner, originalID: quote.originalID, router: graph.router)
                                {
                                    PostReplyContext(reference: reference)
                                }
                                XPostText(
                                    text: quote.text, owner: owner, author: quote.author, authorHandle: quote.handle, textStyle: .subheadline)
                                XPostMedia(
                                    items: quote.media, postID: quote.originalID, owner: owner, sensitive: quote.sensitive,
                                    compact: true)
                            }
                        }
                    }
                },
                like: {
                    PostCommentLike(
                        count: actions.likes, liked: actions.liked, pending: actions.likePending,
                        onToggle: actions.onLike)
                },
                replies: {
                    if actions.comments > 0 || !preview.isEmpty {
                        PostCommentThread(count: max(actions.comments, preview.count), onOpen: openThread) {
                            ForEach(Array(preview.prefix(2))) { reply in
                                XPostText(
                                    text: reply.text.isEmpty ? "[媒体]" : reply.text, owner: owner,
                                    author: reply.author, authorHandle: reply.handle, textStyle: .subheadline, maxLines: 2)
                            }
                        }
                    }
                }, below: {}
            )
            .contextMenu {
                Button("回复", systemImage: "arrowshape.turn.up.left") { showingReply = true }
                Button("查看对话", systemImage: "bubble.left.and.bubble.right", action: openThread)
                if let repost = actions.onRepost {
                    Button("转发", systemImage: "arrow.2.squarepath", action: repost)
                }
                Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = post.text }
            }
        }
        .sheet(isPresented: $showingReply) { XComposer(owner: owner, post: post, onSent: onSent) }
    }

    private func openAuthor() {
        graph.router.push(.xProfile(owner: owner, user: post.profileUser))
    }

    private func openThread() {
        graph.router.push(.xStatus(owner: owner, id: post.originalID, initial: post))
    }
}
