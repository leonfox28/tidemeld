import Foundation

extension AppGraph {
    func xVideoRequest(owner: String, postID: String, index: Int, known: VideoInfo) -> VideoRequest {
        let revision = accounts.find(owner)?.revision
        return VideoRequest(cover: known.coverURL,
            headers: ["Referer": "https://x.com/", "User-Agent": browserUserAgent]) { [self] refresh in
            @MainActor func checkAccount() throws {
                guard let account = accounts.find(owner), account.revision == revision, !account.expired else {
                    throw WeiboError.sessionExpired
                }
            }
            try checkAccount()
            if !refresh, let url = freshStreamURL(known) { return VideoSource(url: url, fetched: false) }
            let page = try await xInteractions.conversation(owner, id: postID, cursor: nil)
            try checkAccount()
            let videos: [VideoInfo] = page.post?.media.compactMap { if case .video(let video) = $0 { video } else { nil } } ?? []
            guard videos.indices.contains(index), let url = videos[index].streamURLs.first else {
                throw WeiboError.api("这条帖子的视频暂时无法播放")
            }
            return VideoSource(url: url, fetched: true)
        }
    }
}
