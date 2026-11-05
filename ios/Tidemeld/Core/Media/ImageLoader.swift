import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

// Signature parameters on avatar URLs that change every few hours.
private let signatureParams: Set<String> = ["Expires", "ssig", "KID"]

/// The cache key for [url]: signature parameters are dropped, so a re-signed URL
/// for the same picture hits the cache, and so is plain http, which is fetched
/// over https anyway.
func imageCacheKey(_ url: String) -> String {
    guard var components = URLComponents(string: https(url)) else { return url }
    if let items = components.queryItems {
        let kept = items.filter { !signatureParams.contains($0.name) }
        components.queryItems = kept.isEmpty ? nil : kept
    }
    return components.string ?? url
}

/// Loads Weibo's pictures: every request has weibo.com as its Referer (Weibo's
/// image hosts answer 403 without it, and a browser tab on weibo.com sends it
/// too), goes over https, and pictures are kept in a disk cache whose size the
/// settings limit.
final class ImageLoader: @unchecked Sendable {
    private let session: URLSession
    private let disk: URLCache
    private let memory = NSCache<NSString, UIImage>()
    /// The memory key each picture was last decoded under, by cache key, to
    /// find it at whatever size it was.
    private var lastDecoded: [String: String] = [:]
    private let lastDecodedLock = NSLock()
    private let inflight = Inflight()

    init(directory: URL, limitMB: Int, configuration: URLSessionConfiguration = .default) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
        disk = URLCache(memoryCapacity: 0, diskCapacity: limitMB * 1024 * 1024, directory: directory)
        memory.totalCostLimit = 96 * 1024 * 1024
    }

    /// A decoded picture already in memory, to show without a placeholder flash.
    func cached(_ url: String, maxPixels: CGFloat?) -> UIImage? {
        memory.object(forKey: memoryKey(url, maxPixels) as NSString)
    }

    /// The picture at [url] if in memory at any size, as a list showed it.
    func cachedAtAnySize(_ url: String) -> UIImage? {
        guard let key = lastDecodedLock.withLock({ lastDecoded[imageCacheKey(url)] }) else { return nil }
        return memory.object(forKey: key as NSString)
    }

    /// The picture at [url], decoded to at most [maxPixels] on its longer side
    /// (nil for full size). Animated GIFs come out animated.
    func image(_ url: String, maxPixels: CGFloat?) async throws -> UIImage {
        let key = memoryKey(url, maxPixels)
        if let image = memory.object(forKey: key as NSString) { return image }
        let data = try await self.data(url)
        // Gone off screen meanwhile: not worth decoding.
        try Task.checkCancellation()
        guard let image = Self.decode(data, maxPixels: maxPixels) else { throw WeiboError.api("无法显示图片") }
        let frames = max(1, image.images?.count ?? 1)
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale) * 4 * frames
        memory.setObject(image, forKey: key as NSString, cost: cost)
        lastDecodedLock.withLock { lastDecoded[imageCacheKey(url)] = key }
        return image
    }

    /// The bytes of the picture at [url], from the disk cache when there.
    func data(_ url: String) async throws -> Data {
        let key = imageCacheKey(url)
        guard let keyURL = URL(string: key) else { throw WeiboError.api("无效的图片地址") }
        let cacheRequest = URLRequest(url: keyURL)
        if let cached = disk.cachedResponse(for: cacheRequest) { return cached.data }
        return try await inflight.run(key) { [session, disk] in
            guard let url = URL(string: https(url)) else { throw WeiboError.api("无效的图片地址") }
            var request = URLRequest(url: url, timeoutInterval: 30)
            let xMedia = url.host == "twimg.com" || (url.host?.hasSuffix(".twimg.com") ?? false)
            request.setValue(xMedia ? "https://x.com/" : "https://weibo.com/", forHTTPHeaderField: "Referer")
            request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw WeiboError.network
            }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                throw WeiboError.api("图片加载失败")
            }
            disk.storeCachedResponse(CachedURLResponse(response: response, data: data), for: cacheRequest)
            return data
        }
    }

    var diskUsage: Int { disk.currentDiskUsage }

    func setLimit(mb: Int) {
        disk.diskCapacity = mb * 1024 * 1024
    }

    /// Empties both caches, the disk one off the main thread.
    func clear() async {
        let disk = disk
        await Task.detached { disk.removeAllCachedResponses() }.value
        memory.removeAllObjects()
    }

    private func memoryKey(_ url: String, _ maxPixels: CGFloat?) -> String {
        "\(imageCacheKey(url))#\(maxPixels.map { Int($0) } ?? 0)"
    }

    /// Decodes [data], downsampled to [maxPixels]; an animated picture all its
    /// frames, smaller still if they would take more memory than one should.
    static func decode(_ data: Data, maxPixels: CGFloat?) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var longSide = maxPixels
        if let size = pixelSize(source) {
            longSide = min(maxPixels ?? .infinity, max(size.width, size.height))
            if count > 1 { longSide = min(longSide!, animatedSide(size, frames: count, maxPixels: maxPixels)) }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, longSide ?? 4096),
        ]
        if count > 1, let animated = animatedImage(source, count: count, options: options) { return animated }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image)
    }

    private static func pixelSize(_ source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
            let height = properties[kCGImagePropertyPixelHeight] as? CGFloat, width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// The longer side an animated picture of [size] can be decoded to, all
    /// [frames] of it held at once (UIKit plays frames decoded beforehand): 16
    /// MB in a list, which a grid of nine can take, 64 MB in the viewer.
    static func animatedSide(_ size: CGSize, frames: Int, maxPixels: CGFloat?) -> CGFloat {
        let budget: CGFloat = (maxPixels ?? .infinity) <= 1024 ? 16 * 1024 * 1024 : 64 * 1024 * 1024
        let shape = min(size.width, size.height) / max(size.width, size.height)
        // frames × 4 bytes × side × (side × shape) ≤ budget
        return (budget / (CGFloat(min(frames, maxFrames)) * 4 * shape)).squareRoot().rounded(.down)
    }

    /// Long GIFs are cut short rather than shrunk to nothing.
    private static let maxFrames = 300

    private static func animatedImage(_ source: CGImageSource, count: Int, options: [CFString: Any]) -> UIImage? {
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<min(count, maxFrames) {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary)
            else { continue }
            frames.append(UIImage(cgImage: image))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay =
                gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1
            duration += delay < 0.02 ? 0.1 : delay
        }
        guard !frames.isEmpty else { return nil }
        return frames.count == 1 ? frames[0] : UIImage.animatedImage(with: frames, duration: duration)
    }
}

/// Requests for the same key share one download, which stops once none of
/// them wants it any more: a picture scrolled past isn't downloaded on, as Coil
/// cancels a request as its image leaves the screen.
private actor Inflight {
    private struct Download {
        let task: Task<Data, Error>
        var waiting: Set<UUID>
    }

    private var downloads: [String: Download] = [:]

    func run(_ key: String, _ work: @escaping @Sendable () async throws -> Data) async throws -> Data {
        let waiter = UUID()
        let task: Task<Data, Error>
        if let download = downloads[key] {
            task = download.task
            downloads[key]?.waiting.insert(waiter)
        } else {
            task = Task { try await work() }
            downloads[key] = Download(task: task, waiting: [waiter])
        }
        defer { leave(key, waiter) }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.leave(key, waiter) }
        }
    }

    private func leave(_ key: String, _ waiter: UUID) {
        guard var download = downloads[key], download.waiting.remove(waiter) != nil else { return }
        if download.waiting.isEmpty {
            download.task.cancel()
            downloads[key] = nil
        } else {
            downloads[key] = download
        }
    }
}
