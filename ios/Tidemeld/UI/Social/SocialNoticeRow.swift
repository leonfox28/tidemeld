import SwiftUI

struct SocialNoticeRow<Avatar: View, Content: View>: View {
    let author: String
    let activity: String
    var time: String? = nil
    var onOpen: (() -> Void)? = nil
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        "\(Text(author).fontWeight(.medium).foregroundStyle(AppTheme.secondary)) \(activity)"
                    ).font(.subheadline).lineLimit(1)
                    if let time { Text(time).font(.caption).foregroundStyle(AppTheme.secondary) }
                }
                content()
            }
        }.foregroundStyle(AppTheme.foreground).padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture {
                onOpen?()
            }
    }
}

struct PostSummary: View {
    let author: String?
    let text: String
    var thumbnail: String? = nil
    var onOpen: (() -> Void)? = nil
    @Environment(\.displayScale) private var scale
    var body: some View {
        HStack(spacing: 8) {
            if let thumbnail {
                WeiboImage(url: thumbnail, maxPixels: 48 * scale).frame(width: 48, height: 48).clipShape(
                    RoundedRectangle(cornerRadius: 4))
            }
            Text("\(Text(author.map { "@\($0)：" } ?? "").fontWeight(.medium))\(text)")
                .font(.caption).foregroundStyle(AppTheme.secondary).lineLimit(2).frame(
                    maxWidth: .infinity, alignment: .leading)
        }.padding(8).background(AppTheme.elevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8)).onTapGesture { onOpen?() }
    }
}
