import SwiftUI

struct VideoCover: View {
    let video: VideoInfo
    let onTap: () -> Void

    var body: some View {
        // Portrait videos are cropped square to keep the timeline compact.
        let ratio = min(max(video.aspectRatio ?? 16.0 / 9, 1), 16.0 / 9)
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { WeiboImage(url: video.coverURL, maxPixels: 1200) }
            .overlay { PlayIcon() }
            .overlay(alignment: .bottomTrailing) {
                if let duration = video.duration, duration > 0 {
                    MediaBadge(label: formatDuration(duration)).padding(6)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .onTapGesture(perform: onTap)
            .accessibilityLabel("播放视频")
    }
}
