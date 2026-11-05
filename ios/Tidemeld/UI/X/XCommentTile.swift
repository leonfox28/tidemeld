import SwiftUI

/// X supplies replies to the same compact comment row as Weibo.
struct XCommentTile: View {
    let post: XPost
    let owner: String
    var authorHandle: String?
    var preview: [XPost] = []
    var onSent: (() -> Void)?
    @Environment(AppGraph.self) private var graph
    @Environment(\.displayScale) private var scale
    @State private var showingReply = false

    var body: some View {
        XPostActionHost(post: post, owner: owner, onReply: { showingReply = true }) { actions in
            PostComment(
                author: post.author,
                metadata: [post.createdAt.map { formatPostTime($0) }, "@\(post.handle)"].compactMap { $0 }.joined(separator: "  "),
                isAuthor: authorHandle != nil && post.handle.lowercased() == authorHandle?.lowercased(),
                onReply: { showingReply = true },
                avatar: {
                    Group {
                        if let url = post.avatar { WeiboImage(url: url, maxPixels: 32 * scale) }
                        else { Image(systemName: "person.fill").foregroundStyle(AppTheme.secondary) }
                    }.frame(width: 32, height: 32).clipShape(Circle())
                },
                content: {
                    if !post.text.isEmpty {
                        Text(post.text).font(.callout).foregroundStyle(AppTheme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    XPostMedia(items: post.media, postID: post.originalID, owner: owner, compact: true)
                    if let quote = post.quote {
                        QuotedPost(onOpen: { graph.router.push(.xStatus(owner: owner, id: quote.url.lastPathComponent, initial: nil)) }) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("@\(quote.author)：\(quote.text)").font(.subheadline)
                                XPostMedia(items: quote.media, postID: quote.url.lastPathComponent, owner: owner, compact: true)
                            }
                        }
                    }
                },
                like: {
                    PostCommentLike(count: actions.likes, liked: actions.liked, pending: actions.likePending, onToggle: actions.onLike)
                },
                replies: {
                    if actions.comments > 0 || !preview.isEmpty {
                        PostCommentThread(count: max(actions.comments, preview.count), onOpen: openThread) {
                            ForEach(Array(preview.prefix(2))) { reply in
                                Text("@\(reply.author)：\(reply.text.isEmpty ? "[媒体]" : reply.text)")
                                    .font(.subheadline).foregroundStyle(AppTheme.foreground).lineLimit(2)
                            }
                        }
                    }
                }, below: {}
            )
            .contextMenu {
                Button("回复", systemImage: "arrowshape.turn.up.left") { showingReply = true }
                Button("查看对话", systemImage: "bubble.left.and.bubble.right", action: openThread)
                if let repost = actions.onRepost { Button("转发", systemImage: "arrow.2.squarepath", action: repost) }
                Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = post.text }
            }
        }
        .sheet(isPresented: $showingReply) { XComposer(owner: owner, post: post, onSent: onSent) }
    }

    private func openThread() {
        graph.router.push(.xStatus(owner: owner, id: post.originalID, initial: post))
    }
}
