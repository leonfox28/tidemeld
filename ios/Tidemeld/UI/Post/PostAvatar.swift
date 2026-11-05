import SwiftUI

/// A round avatar of [user], tappable when [onTap] is set.
struct PostAvatar: View {
    let url: String?
    var label = "头像"
    var size: CGFloat = 40
    var onTap: (() -> Void)? = nil
    @Environment(\.displayScale) private var scale

    var body: some View {
        Group {
            if let url {
                WeiboImage(url: url, maxPixels: size * scale)
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(AppTheme.onPrimaryContainer)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.primaryContainer)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .contentShape(Circle())
        .onTapGesture {
            onTap?()
        }
        .allowsHitTesting(onTap != nil)
        .accessibilityLabel(label)
    }
}
