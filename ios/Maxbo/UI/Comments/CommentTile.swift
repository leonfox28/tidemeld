import SwiftUI

/// A comment with its author, pictures, time and like button; with [onThread],
/// also a preview of its replies that opens the whole thread.
struct CommentTile<Below: View>: View {
    let comment: Comment
    /// The status author, whose comments are labelled 博主.
    var authorId: String? = nil
    var actions = StatusCardActions()
    var onThread: (() -> Void)? = nil
    /// Tapping the comment, e.g. to reply to it.
    var onTap: (() -> Void)? = nil
    /// Deleting it, offered from its context menu: the user's own only.
    var onDelete: (() -> Void)? = nil
    /// Shown last, e.g. the post a notification's comment is on.
    @ViewBuilder var below: () -> Below

    var body: some View {
        let user = comment.user
        let meta = [comment.createdAt.map { formatPostTime($0) }, comment.source].compactMap { $0 }
            .joined(separator: "  ")
        HStack(alignment: .top, spacing: 10) {
            UserAvatar(user: user, size: 32, onTap: actions.onUser)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(user?.screenName ?? "微博用户")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.secondary)
                        .lineLimit(1)
                        .onTapGesture {
                            if let user { actions.onUser?(user) }
                        }
                    if let user, user.id == authorId {
                        Text("博主")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.onPrimaryContainer)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(AppTheme.primaryContainer, in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                if !comment.text.isEmpty {
                    StatusText(
                        html: comment.text, urls: comment.urls,
                        // A reply links its picture too; it shows below.
                        hiddenPictures: Set(comment.pics.map(\.id)),
                        onLink: actions.onLink
                    )
                    .foregroundStyle(AppTheme.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !comment.pics.isEmpty { CommentPictures(comment: comment, actions: actions) }
                HStack {
                    Text(meta).font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    CommentLikeButton(comment: comment)
                }
                if let onThread, comment.replyCount > 0 {
                    ThreadPreview(comment: comment, actions: actions, onTap: onThread)
                }
                below()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .contextMenu {
            if let onTap {
                Button("回复", systemImage: "arrowshape.turn.up.left", action: onTap)
            }
            Button("复制", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = plainStatusText(comment.text)
            }
            if let onDelete {
                Button("删除", systemImage: "trash", role: .destructive, action: onDelete)
            }
        }
    }
}

extension CommentTile where Below == EmptyView {
    init(
        comment: Comment, authorId: String? = nil, actions: StatusCardActions = StatusCardActions(),
        onThread: (() -> Void)? = nil, onTap: (() -> Void)? = nil, onDelete: (() -> Void)? = nil
    ) {
        self.init(
            comment: comment, authorId: authorId, actions: actions, onThread: onThread, onTap: onTap,
            onDelete: onDelete, below: { EmptyView() })
    }
}

/// The comment's like button; while a like is on its way it takes taps all the
/// same, so they don't reply to the comment.
private struct CommentLikeButton: View {
    let comment: Comment
    @Environment(AppGraph.self) private var graph

    var body: some View {
        let target = LikeTarget(kind: .comment, id: comment.id)
        let shown = graph.likes.shown(target, loaded: comment.like)
        Button {
            if !shown.pending { graph.toggleLike(target, loaded: comment.like) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: shown.like.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                Text(shown.like.count > 0 ? formatCount(shown.like.count) : "赞").monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(shown.like.liked ? AppTheme.primary : AppTheme.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: shown.like.liked)
    }
}

private struct CommentPictures: View {
    let comment: Comment
    let actions: StatusCardActions
    @Environment(AppGraph.self) private var graph
    @Environment(\.displayScale) private var scale
    @Environment(\.mediaNamespace) private var namespace

    private let size: CGFloat = 96

    var body: some View {
        let pixels = graph.settings.settings.imageQuality.listPixels(size, scale: scale)
        HStack(spacing: 4) {
            ForEach(Array(comment.pics.enumerated()), id: \.offset) { i, pic in
                let source = picSourceID(comment.id, pic)
                WeiboImage(url: pic.variant(for: pixels).url, maxPixels: size * scale)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(RoundedRectangle(cornerRadius: 4))
                    .onTapGesture { actions.onPicture?(comment.pics, i, nil, source) }
                    .modifier(TransitionSource(id: source, namespace: namespace))
            }
        }
    }
}

/// The first replies of a thread and its size; tapping opens the thread.
private struct ThreadPreview: View {
    let comment: Comment
    let actions: StatusCardActions
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(comment.replies) { reply in
                StatusText(
                    html: reply.text, urls: reply.urls, author: reply.user?.screenName,
                    textStyle: .subheadline, onLink: actions.onLink
                )
                .foregroundStyle(AppTheme.foreground)
            }
            Text("共\(comment.replyCount)条回复 >")
                .font(.subheadline)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: onTap)
    }
}
