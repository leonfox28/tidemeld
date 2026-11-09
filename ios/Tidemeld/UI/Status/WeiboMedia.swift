import Foundation

private let weiboMediaHeaders = ["Referer": "https://weibo.com/", "User-Agent": browserUserAgent]

func weiboVideoRequest(api: WeiboAPI, status: Status, index: Int?) -> VideoRequest {
    VideoRequest(cover: status.video(at: index)?.coverURL, headers: weiboMediaHeaders) { refresh in
        try await resolveVideoURL(api, id: status.id, index: index, known: status.video(at: index), refresh: refresh)
    }
}

func weiboVideoRequest(api: WeiboAPI, link: WeiboVideoLink) -> VideoRequest {
    VideoRequest(cover: nil, headers: weiboMediaHeaders) { _ in
        let video = try await api.fetchLinkedVideo(link)
        guard let url = video.streamURLs.first else { throw WeiboError.api("这段视频暂时无法播放") }
        return VideoSource(url: url, fetched: true)
    }
}

func weiboPhotoMotion(api: WeiboAPI, statusId: String?) -> PhotoMotion {
    PhotoMotion(headers: weiboMediaHeaders, canRefresh: statusId != nil) { pic, refresh in
        try await resolveLivePhotoURL(api, pic: pic, statusId: statusId, refresh: refresh)
    }
}
