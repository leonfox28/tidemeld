import SwiftUI

/// Closures are bound to the source account by the platform adapter.
struct PostInteractionActions {
    var reposts = 0
    var comments = 0
    var likes = 0
    var liked = false
    var reposted = false
    var likePending = false
    var repostPending = false
    var onRepost: (() -> Void)?
    var onComment: (() -> Void)?
    var onLike: (() -> Void)?
}

struct PostInteractionBar: View {
    let actions: PostInteractionActions
    var body: some View {
        HStack(spacing: 0) {
            PostCountButton(
                symbol: "arrow.2.squarepath", count: actions.reposts, label: "转发",
                selected: actions.reposted, pending: actions.repostPending, action: actions.onRepost
            )
            PostCountButton(
                symbol: "bubble.right", count: actions.comments, label: "评论",
                action: actions.onComment)
            PostCountButton(
                symbol: actions.liked ? "hand.thumbsup.fill" : "hand.thumbsup",
                count: actions.likes, label: "赞", selected: actions.liked,
                pending: actions.likePending, action: actions.onLike
            )
            .sensoryFeedback(.selection, trigger: actions.liked)
        }
    }
}

private struct PostCountButton: View {
    let symbol: String
    let count: Int
    let label: String
    var selected = false
    var pending = false
    let action: (() -> Void)?
    var body: some View {
        Button {
            if !pending { action?() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.footnote)
                Text(count > 0 ? formatCount(count) : label).font(.footnote).monospacedDigit()
            }.foregroundStyle(selected ? AppTheme.primary : AppTheme.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain).opacity(pending || action == nil ? 0.6 : 1)
            .accessibilityLabel(count > 0 ? "\(label) \(count)" : label)
            .accessibilityValue(pending ? "处理中" : selected ? "已\(label)" : "")
    }
}

struct PostDetailToolbar: ToolbarContent {
    let actions: PostInteractionActions
    var body: some ToolbarContent {
        ToolbarSpacer(.flexible, placement: .bottomBar)
        ToolbarItemGroup(placement: .bottomBar) {
            Button("写评论", systemImage: "square.and.pencil") { actions.onComment?() }.disabled(
                actions.onComment == nil)
            Button(actions.reposted ? "已转发" : "转发", systemImage: "arrow.2.squarepath") {
                actions.onRepost?()
            }.disabled(actions.repostPending || actions.onRepost == nil)
            Button {
                actions.onLike?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: actions.liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                    if actions.likes > 0 { Text(formatCount(actions.likes)).monospacedDigit() }
                }
            }.disabled(actions.likePending || actions.onLike == nil)
                .tint(actions.liked ? AppTheme.primary : nil)
                .accessibilityLabel(actions.likes > 0 ? "赞 \(actions.likes)" : "赞")
                .sensoryFeedback(.selection, trigger: actions.liked)
        }
    }
}
