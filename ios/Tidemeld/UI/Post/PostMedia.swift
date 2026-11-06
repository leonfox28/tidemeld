import SwiftUI

/// One attachment layout for feed posts, quotes and compact comments.
struct PostMedia: View {
    let items: [MixedMedia]
    var total: Int? = nil
    var compact = false
    var preferVideoCover = true
    var sensitive = false
    var onOpen: ((Int) -> Void)? = nil
    var sourceID: ((Int) -> String)? = nil
    @State private var revealed = false
    var body: some View {
        if !items.isEmpty {
            if sensitive && !revealed {
                VStack(alignment: .leading, spacing: 8) {
                    Label("媒体已隐藏", systemImage: "eye.slash")
                    Text("平台将此媒体标记为敏感内容。默认不加载图片或视频。")
                        .font(.footnote).foregroundStyle(AppTheme.secondary)
                    Button("显示此条媒体") { revealed = true }
                        .buttonStyle(.bordered)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.elevated, in: RoundedRectangle(cornerRadius: 10))
            } else {
                mediaContent
                if sensitive {
                    Button("重新隐藏媒体", systemImage: "eye.slash") { revealed = false }
                        .font(.footnote).buttonStyle(.borderless)
                }
            }
        }
    }

    @ViewBuilder private var mediaContent: some View {
        if compact {
            PostCommentMedia(items: items, onOpen: onOpen, sourceID: sourceID)
        } else if preferVideoCover, items.count == 1, case .video(let video) = items[0] {
            VideoCover(video: video, onTap: { onOpen?(0) })
        } else {
            PicGrid(items: items, total: total, onTap: onOpen, sourceID: sourceID)
        }
    }
}
