import SwiftUI

/// Shared comment geometry. Adapters supply content and account-bound actions.
struct PostComment<Avatar: View, Content: View, Like: View, Replies: View, Below: View>: View {
    let author: String
    let metadata: String
    var isAuthor = false
    var onAuthor: (() -> Void)?
    var onReply: (() -> Void)?
    var menuActions: ProfileActions? = nil
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let content: () -> Content
    @ViewBuilder let like: () -> Like
    @ViewBuilder let replies: () -> Replies
    @ViewBuilder let below: () -> Below

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(author).font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.secondary).lineLimit(1)
                        .onTapGesture { onAuthor?() }
                    if isAuthor {
                        Text("博主").font(.system(size: 10))
                            .foregroundStyle(AppTheme.onPrimaryContainer)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(AppTheme.primaryContainer, in: RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer(minLength: 0)
                    if let menuActions { SocialProfileActions(actions: menuActions, menuLabel: "更多评论操作") }
                }
                content()
                HStack {
                    Text(metadata).font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    like()
                }
                replies()
                below()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .onTapGesture { onReply?() }
    }
}

struct PostCommentLike: View {
    let count: Int
    let liked: Bool
    var pending = false
    let onToggle: (() -> Void)?
    var body: some View {
        Button { if !pending { onToggle?() } } label: {
            HStack(spacing: 3) {
                Image(systemName: liked ? "hand.thumbsup.fill" : "hand.thumbsup")
                Text(count > 0 ? formatCount(count) : "赞").monospacedDigit()
            }
            .font(.caption).foregroundStyle(liked ? AppTheme.primary : AppTheme.secondary)
            .padding(.horizontal, 6).padding(.vertical, 4).contentShape(Rectangle())
        }
        .buttonStyle(.plain).sensoryFeedback(.selection, trigger: liked)
        .accessibilityLabel(count > 0 ? "赞 \(count)" : "赞")
        .accessibilityValue(pending ? "处理中" : liked ? "已赞" : "")
    }
}

struct PostCommentThread<Content: View>: View {
    let count: Int
    let onOpen: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
            Text("共\(count)条回复 >").font(.subheadline).foregroundStyle(AppTheme.accent)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8)).onTapGesture(perform: onOpen)
    }
}

/// Comment attachments stay compact; playback and navigation belong to the adapter.
struct PostCommentMedia: View {
    let items: [MixedMedia]
    var onOpen: ((Int) -> Void)?
    var sourceID: ((Int) -> String)?
    @Environment(AppGraph.self) private var graph
    @Environment(\.displayScale) private var scale
    @Environment(\.mediaNamespace) private var namespace
    var body: some View {
        let pixels = graph.settings.settings.imageQuality.listPixels(96, scale: scale)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 96), spacing: 4)], alignment: .leading, spacing: 4) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                let url: String? = switch item {
                case .pic(let pic): pic.variant(for: pixels).url
                case .video(let video): video.coverURL
                }
                WeiboImage(url: url, maxPixels: 96 * scale).frame(width: 96, height: 96)
                    .overlay {
                        if case .video = item {
                            Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.white)
                                .shadow(radius: 2)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .contentShape(RoundedRectangle(cornerRadius: 4))
                    .onTapGesture { onOpen?(index) }
                    .accessibilityLabel({ if case .video = item { "播放视频" } else { "查看图片" } }())
                    .modifier(TransitionSource(id: sourceID?(index), namespace: namespace))
            }
        }
    }
}
