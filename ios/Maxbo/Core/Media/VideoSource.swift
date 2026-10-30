import AVFoundation
import Foundation

/// Headers for Weibo's video CDN, which like its image hosts expects a
/// weibo.com Referer.
let videoHTTPHeaders = ["Referer": "https://weibo.com/", "User-Agent": browserUserAgent]

/// An asset for [url] that asks Weibo's CDN with [videoHTTPHeaders].
func weiboVideoAsset(_ url: URL) -> AVURLAsset {
    // The key AVFoundation reads request headers from; it has no public name.
    AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": videoHTTPHeaders])
}

/// When a signed media URL stops working, from its `Expires` parameter; nil
/// for unsigned URLs.
func signedURLExpiry(_ url: String) -> Date? {
    URLComponents(string: url)?.queryItems?.first { $0.name == "Expires" }?.value
        .flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:))
}

/// Whether [url] stays valid for at least [margin] after [now]; unsigned URLs
/// always do.
func isFresh(_ url: String, now: Date = .now, margin: TimeInterval = 300) -> Bool {
    guard let expiry = signedURLExpiry(url) else { return true }
    return expiry > now.addingTimeInterval(margin)
}

/// A stream URL of [video] that stays valid for at least [margin] after [now],
/// or nil when they have all expired or are about to.
func freshStreamURL(_ video: VideoInfo?, now: Date = .now, margin: TimeInterval = 300) -> String? {
    video?.streamURLs.first { isFresh($0, now: now, margin: margin) }
}

/// Where to play a video from; [fetched] when the status was fetched again for
/// it.
struct VideoSource: Sendable, Equatable {
    let url: String
    let fetched: Bool
}

/// Where to play the video of status [id] from: [known]'s URL while it is
/// fresh, or else (or when [refresh] is set) one from re-fetching the status.
/// `fetched` tells which, so a rejected URL is refreshed only once. In a post
/// mixing pictures and videos, [index] picks the video as `Status.video(at:)`
/// does.
func resolveVideoURL(
    _ api: WeiboAPI, id: String, index: Int? = nil, known: VideoInfo? = nil, refresh: Bool = false,
    now: Date = .now
) async throws -> VideoSource {
    if !refresh, let url = freshStreamURL(known, now: now) { return VideoSource(url: url, fetched: false) }
    let status = try await api.fetchStatus(id)
    guard let url = status.video(at: index)?.streamURLs.first else {
        throw WeiboError.api("这条微博的视频暂时无法播放")
    }
    return VideoSource(url: url, fetched: true)
}

/// Where to play the moving part of live photo [pic] from: its own URL while it
/// is fresh, or else (or when [refresh] is set) the one in its status
/// [statusId] fetched again. Without a [statusId] its own URL is all there is.
func resolveLivePhotoURL(
    _ api: WeiboAPI, pic: PicInfo, statusId: String?, refresh: Bool = false, now: Date = .now
) async throws -> VideoSource {
    if let known = pic.liveVideo, statusId == nil || (!refresh && isFresh(known, now: now)) {
        return VideoSource(url: known, fetched: false)
    }
    guard let statusId else { throw WeiboError.api("这张实况照片暂时无法播放") }
    let status = try await api.fetchStatus(statusId)
    guard let url = (status.pics + status.mixedPics).first(where: { $0.id == pic.id })?.liveVideo else {
        throw WeiboError.api("这张实况照片暂时无法播放")
    }
    return VideoSource(url: url, fetched: true)
}
