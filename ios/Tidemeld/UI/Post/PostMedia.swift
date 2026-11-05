import SwiftUI

/// One attachment layout for feed posts, quotes and compact comments.
struct PostMedia: View {
    let items: [MixedMedia]
    var total: Int? = nil
    var compact = false
    var preferVideoCover = true
    var onOpen: ((Int) -> Void)? = nil
    var sourceID: ((Int) -> String)? = nil
    var body: some View {
        if !items.isEmpty {
            if compact {
                PostCommentMedia(items: items, onOpen: onOpen, sourceID: sourceID)
            } else if preferVideoCover, items.count == 1, case .video(let video) = items[0] {
                VideoCover(video: video, onTap: { onOpen?(0) })
            } else {
                PicGrid(items: items, total: total, onTap: onOpen, sourceID: sourceID)
            }
        }
    }
}
