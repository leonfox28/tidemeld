import SwiftUI
import UIKit

extension ImageLoader {
    /// The app's loader, made before the first frame; views read it as they
    /// are made, to show a picture already in memory without a placeholder.
    @MainActor static var shared: ImageLoader!
}

/// A Weibo-hosted image filling its frame, with a placeholder while loading and
/// tap-to-retry when it fails.
///
/// Callers pick a rendition close to the displayed size (see
/// `PicInfo.variant(for:)`) and say how many pixels to decode it to, so lists
/// never hold full-size pictures.
struct WeiboImage: View {
    @Environment(\.imageTransitionSourceID) private var sourceID
    @Environment(\.imageTransitionSources) private var sources
    let url: String?
    /// The longer side to decode to, in pixels; nil for the picture's own size.
    var maxPixels: CGFloat? = nil
    var contentMode: ContentMode = .fill
    var alignment: Alignment = .center
    /// Whether to fill the area while loading; off for inline emoticons.
    var placeholder = true

    @State private var loaded: UIImage?
    @State private var loadedKey: String?
    @State private var failed = false
    @State private var attempt = 0

    private var key: String? { url.map { "\($0)#\(maxPixels ?? 0)" } }

    var body: some View {
        let image =
            loadedKey == key
            ? loaded : url.flatMap { ImageLoader.shared.cached($0, maxPixels: maxPixels) }
        Color.clear
            .overlay(alignment: alignment) {
                if let image {
                    if let sourceID, let sources {
                        TransitionImage(image: image, contentMode: contentMode, alignment: alignment,
                                        sourceID: sourceID, sources: sources)
                    } else if image.images != nil {
                        AnimatedImage(image: image, contentMode: contentMode)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                    }
                }
            }
            .background(placeholder && image == nil ? AppTheme.elevated : .clear)
            .overlay {
                // Anywhere on it tries again, rather than doing what a tap on
                // the picture does, as in the Kotlin app.
                if failed, placeholder {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(AppTheme.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { attempt += 1 }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("加载失败，点击重试")
                }
            }
            .clipped()
            .task(id: "\(key ?? "")#\(attempt)") {
                guard let url, image == nil || loadedKey != key else { return }
                failed = false
                do {
                    let image = try await ImageLoader.shared.image(url, maxPixels: maxPixels)
                    loaded = image
                    loadedKey = key
                } catch {
                    if !Task.isCancelled { failed = true }
                }
            }
    }
}

/// An animated picture (a GIF), playing.
struct AnimatedImage: UIViewRepresentable {
    let image: UIImage
    var contentMode: ContentMode = .fill

    func makeUIView(context: Context) -> UIImageView {
        let view = UIImageView()
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateUIView(_ view: UIImageView, context: Context) {
        view.contentMode = contentMode == .fill ? .scaleAspectFill : .scaleAspectFit
        if view.image !== image {
            view.image = image
            view.startAnimating()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIImageView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

/// Weibo supplies content and navigation to the common avatar.
struct UserAvatar: View {
    let user: WeiboUser?
    var size: CGFloat = 40
    var onTap: ((WeiboUser) -> Void)? = nil
    var body: some View {
        PostAvatar(
            url: user?.avatarURL, label: user?.screenName ?? "头像", size: size,
            onTap: user.flatMap { user in onTap.map { action in { action(user) } } })
    }
}

/// Whether [verifiedType] (`WeiboUser.verifiedType`) has a mark.
func showsVerified(_ verifiedType: Int?) -> Bool {
    verifiedType.map { (0...7).contains($0) } ?? false
}

/// Weibo's verification mark: gold for people, blue for organisations.
struct VerifiedIcon: View {
    let verifiedType: Int
    var size: CGFloat = 14

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size))
            .foregroundStyle(verifiedType == 0 ? Color(rgb: 0xFFA000) : Color(rgb: 0x1E88E5))
            .accessibilityLabel("认证")
    }
}

/// A small label such as 广告 or 置顶: outlined, or filled with [color].
struct TagLabel: View {
    let text: String
    var color: Color? = nil

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color == nil ? AppTheme.secondary : .white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background {
                if let color {
                    RoundedRectangle(cornerRadius: 3).fill(color)
                } else {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(AppTheme.outline)
                }
            }
    }
}

/// A small label over media, such as GIF or a video duration.
struct MediaBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(.black.opacity(0.54), in: RoundedRectangle(cornerRadius: 3))
    }
}

/// The play mark over a video cover.
struct PlayIcon: View {
    var size: CGFloat = 52

    var body: some View {
        Image(systemName: "play.circle.fill")
            .font(.system(size: size))
            .foregroundStyle(.white.opacity(0.85))
            .shadow(color: .black.opacity(0.4), radius: 8)
            .accessibilityLabel("播放")
    }
}
