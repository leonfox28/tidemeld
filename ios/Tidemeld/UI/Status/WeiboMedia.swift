import Foundation

private let weiboMediaHeaders = ["Referer": "https://weibo.com/", "User-Agent": browserUserAgent]

func weiboVideoRequest(api: WeiboAPI, status: Status, index: Int?) -> VideoRequest {
    VideoRequest(cover: status.video(at: index)?.coverURL, headers: weiboMediaHeaders) { refresh in
        try await resolveVideoURL(api, id: status.id, index: index, known: status.video(at: index), refresh: refresh)
    }
}

func weiboPhotoMotion(api: WeiboAPI, statusId: String?) -> PhotoMotion {
    PhotoMotion(headers: weiboMediaHeaders, canRefresh: statusId != nil) { pic, refresh in
        try await resolveLivePhotoURL(api, pic: pic, statusId: statusId, refresh: refresh)
    }
}
