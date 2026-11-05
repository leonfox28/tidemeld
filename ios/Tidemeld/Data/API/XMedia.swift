import Foundation

/// X's attachments become the same presentation values as every other platform.
func parseXMedia(_ entries: [JSON]) -> [MixedMedia] {
    entries.compactMap { entry in
        let size = entry["original_info"] ?? entry["sizes"]?["large"]
        let width = Int(size?["width"]?.int ?? size?["w"]?.int ?? 0)
        let height = Int(size?["height"]?.int ?? size?["h"]?.int ?? 0)
        let cover = entry["media_url_https"]?.url
        switch entry["type"]?.string {
        case "photo":
            guard let cover else { return nil }
            return .pic(PicInfo(id: entry["id_str"]?.string ?? cover, type: .pic,
                variants: [PicVariant(url: cover, width: width, height: height)]))
        case "video", "animated_gif":
            let info = entry["video_info"]
            let streams = (info?["variants"]?.objects ?? [])
                .filter { $0["content_type"]?.string == "video/mp4" }
                .sorted { ($0["bitrate"]?.int ?? 0) > ($1["bitrate"]?.int ?? 0) }
                .compactMap { $0["url"]?.url }
            let ratio = info?["aspect_ratio"]?.array?.compactMap(\.int) ?? []
            return .video(VideoInfo(coverURL: cover,
                duration: info?["duration_millis"]?.int.map { Int($0 / 1000) },
                aspectRatio: ratio.count == 2 && ratio[1] > 0 ? Double(ratio[0]) / Double(ratio[1])
                    : (width > 0 && height > 0 ? Double(width) / Double(height) : nil),
                streamURLs: streams))
        default: return nil
        }
    }
}
