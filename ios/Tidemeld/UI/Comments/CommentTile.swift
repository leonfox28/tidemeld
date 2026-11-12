import SwiftUI

/// Weibo adapts comments to the common row, retaining its links, likes and thread semantics.
struct CommentTile<Below: View>: View {
    let comment: Comment
    var authorId: String? = nil
    var actions = StatusCardActions()
    var onThread: (() -> Void)? = nil
    var onTap: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    @ViewBuilder var below: () -> Below
    @Environment(AppGraph.self) private var graph
    @State private var source = UUID().uuidString

    var body: some View {
        PostContentFilter(text: comment.contentFilterText, authors: comment.contentAuthorIDs) { unfilteredContent }
    }

    @ViewBuilder private var unfilteredContent: some View {
        let user = comment.user
        let meta = [comment.createdAt.map { formatPostTime($0) }, comment.source].compactMap { $0 }.joined(separator: "  ")
        PostComment(
            author: user?.screenName ?? "微博用户", metadata: meta,
            isAuthor: user != nil && user?.id == authorId,
            onAuthor: user.flatMap { user in actions.onUser.map { action in { action(user) } } },
            onReply: onTap,
            avatar: { UserAvatar(user: user, size: 32, onTap: actions.onUser) },
            content: {
                if !comment.text.isEmpty {
                    StatusText(html: comment.text, urls: comment.urls,
                        hiddenPictures: Set(comment.pics.map(\.id)), onLink: actions.onLink)
                        .foregroundStyle(AppTheme.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !comment.pics.isEmpty {
                    PostCommentMedia(items: comment.pics.map(MixedMedia.pic), onOpen: { index in
                        actions.onPicture?(comment.pics, index, nil, picSourceID(source, comment.pics[index]))
                    }, sourceID: { picSourceID(source, comment.pics[$0]) })
                }
            },
            like: { CommentLikeButton(comment: comment) },
            replies: {
                if let onThread, comment.replyCount > 0 {
                    PostCommentThread(count: comment.replyCount, onOpen: onThread) {
                        ForEach(comment.replies) { reply in
                            StatusText(html: reply.text, urls: reply.urls, author: reply.user?.screenName,
                                textStyle: .subheadline, onLink: actions.onLink)
                                .foregroundStyle(AppTheme.foreground)
                        }
                    }
                }
            }, below: below
        )
        .modifier(SocialContextMenu(actions: graph.weiboSafetyActions(id: comment.id, kind: .comment, user: comment.user)) {
            if let onTap { Button("回复", systemImage: "arrowshape.turn.up.left", action: onTap) }
            Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = plainStatusText(comment.text) }
            if let onDelete { Button("删除", systemImage: "trash", role: .destructive, action: onDelete) }
        })
    }
}

extension CommentTile where Below == EmptyView {
    init(comment: Comment, authorId: String? = nil, actions: StatusCardActions = StatusCardActions(),
         onThread: (() -> Void)? = nil, onTap: (() -> Void)? = nil, onDelete: (() -> Void)? = nil) {
        self.init(comment: comment, authorId: authorId, actions: actions, onThread: onThread,
                  onTap: onTap, onDelete: onDelete, below: { EmptyView() })
    }
}

private struct CommentLikeButton: View {
    let comment: Comment
    @Environment(AppGraph.self) private var graph
    var body: some View {
        let target = LikeTarget(kind: .comment, id: comment.id)
        let shown = graph.likes.shown(target, loaded: comment.like)
        PostCommentLike(count: shown.like.count, liked: shown.like.liked, pending: shown.pending,
            onToggle: { graph.toggleLike(target, loaded: comment.like) })
    }
}
