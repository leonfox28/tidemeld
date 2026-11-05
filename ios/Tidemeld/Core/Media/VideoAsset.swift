import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Streams Weibo's MP4/MOV files through public resource-loading APIs, with
/// the same CDN headers as the browser. Keep this owner alive with the item:
/// AVAssetResourceLoader holds its delegate weakly.
final class WeiboVideoAsset {
    let asset: AVURLAsset
    private let loader: VideoResourceLoader

    init(_ url: URL, configuration: URLSessionConfiguration = .ephemeral) {
        asset = AVURLAsset(url: URL(string: "tidemeld-video://asset/\(UUID())")!)
        loader = VideoResourceLoader(url: url, configuration: configuration)
        asset.resourceLoader.setDelegate(loader, queue: loader.queue)
    }

    deinit { loader.cancel() }
}

/// All mutable state and both sets of delegate callbacks use [queue]. The
/// session retains its delegate until the asset owner invalidates it.
private final class VideoResourceLoader: NSObject, AVAssetResourceLoaderDelegate,
    URLSessionDataDelegate, @unchecked Sendable
{
    let queue = DispatchQueue(label: "tidemeld.video")
    private let url: URL
    private var session: URLSession!
    private var pending: [Int: Transfer] = [:]

    private struct Transfer {
        let loading: AVAssetResourceLoadingRequest
        let task: URLSessionDataTask
        let start: Int64
        var end: Int64?
        var offset: Int64 = 0
    }

    init(url: URL, configuration: URLSessionConfiguration) {
        self.url = url
        super.init()
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let callbacks = OperationQueue()
        callbacks.maxConcurrentOperationCount = 1
        callbacks.underlyingQueue = queue
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: callbacks)
    }

    func cancel() {
        queue.async {
            for id in Array(self.pending.keys) { self.finish(id, error: URLError(.cancelled)) }
            self.session.invalidateAndCancel()
        }
    }

    private func headers(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("https://weibo.com/", forHTTPHeaderField: "Referer")
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return request
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard loadingRequest.request.url?.scheme == "tidemeld-video" else { return false }
        let data = loadingRequest.dataRequest
        let start = max(data?.requestedOffset ?? 0, data?.currentOffset ?? 0)
        // An information-only request still probes a range, so Content-Range
        // gives the full file length without downloading the whole movie.
        let end: Int64?
        if let data {
            end = data.requestsAllDataToEndOfResource ? nil : data.requestedOffset + Int64(data.requestedLength)
        } else {
            end = 2
        }
        var request = headers(URLRequest(url: url))
        request.setValue("bytes=\(start)-\(end.map { String($0 - 1) } ?? "")", forHTTPHeaderField: "Range")
        let task = session.dataTask(with: request)
        pending[task.taskIdentifier] = Transfer(loading: loadingRequest, task: task, start: start, end: end)
        task.resume()
        return true
    }

    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest
    ) {
        guard let id = pending.first(where: { $0.value.loading === loadingRequest })?.key else { return }
        pending.removeValue(forKey: id)?.task.cancel()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard pending[task.taskIdentifier] != nil else { return completionHandler(nil) }
        var request = headers(request)
        request.setValue(task.originalRequest?.value(forHTTPHeaderField: "Range"), forHTTPHeaderField: "Range")
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let id = dataTask.taskIdentifier
        guard var transfer = pending[id] else { return completionHandler(.cancel) }
        do {
            let info = try VideoResponse(response, requestedOffset: transfer.start)
            transfer.offset = info.offset
            transfer.end = min(transfer.end ?? info.length, info.length)
            pending[id] = transfer
            if let content = transfer.loading.contentInformationRequest {
                content.contentType = info.contentType
                content.contentLength = info.length
                content.isByteRangeAccessSupported = info.acceptsRanges
            }
            if transfer.loading.dataRequest == nil {
                finish(id)
                completionHandler(.cancel)
            } else {
                completionHandler(.allow)
            }
        } catch {
            finish(id, error: error)
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        guard var transfer = pending[id], let request = transfer.loading.dataRequest,
            let end = transfer.end
        else { return }
        // A server may ignore Range and return 200. Skip the prefix in that
        // case, and never feed bytes outside AVFoundation's requested range.
        let next = max(transfer.start, request.currentOffset)
        let lower = max(0, next - transfer.offset)
        let upper = min(Int64(data.count), end - transfer.offset)
        if lower < upper { request.respond(with: data.subdata(in: Int(lower)..<Int(upper))) }
        transfer.offset += Int64(data.count)
        pending[id] = transfer
        if request.currentOffset >= end { finish(id) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let transfer = pending[task.taskIdentifier] else { return }
        let complete = transfer.end.map { (transfer.loading.dataRequest?.currentOffset ?? 0) >= $0 } ?? false
        finish(task.taskIdentifier, error: error ?? (complete ? nil : URLError(.networkConnectionLost)))
    }

    private func finish(_ id: Int, error: Error? = nil) {
        guard let transfer = pending.removeValue(forKey: id) else { return }
        if !transfer.loading.isCancelled {
            if let error { transfer.loading.finishLoading(with: error) } else { transfer.loading.finishLoading() }
        }
        transfer.task.cancel()
    }
}

/// Validates range responses before any bytes reach the media parser. A 206
/// Content-Length is only the chunk size; AVFoundation needs the total size.
struct VideoResponse {
    let offset: Int64
    let length: Int64
    let acceptsRanges: Bool
    let contentType: String

    init(_ response: URLResponse, requestedOffset: Int64) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        switch http.statusCode {
        case 206:
            guard let range = http.value(forHTTPHeaderField: "Content-Range"), range.hasPrefix("bytes ")
            else { throw URLError(.badServerResponse) }
            let parts = range.dropFirst(6).split(whereSeparator: { $0 == "-" || $0 == "/" })
            guard parts.count == 3, let first = Int64(parts[0]), let last = Int64(parts[1]),
                let total = Int64(parts[2]), first == requestedOffset, first >= 0,
                last >= first, total > last
            else { throw URLError(.badServerResponse) }
            offset = first
            length = total
            acceptsRanges = true
        case 200:
            guard response.expectedContentLength >= 0 else { throw URLError(.badServerResponse) }
            offset = 0
            length = response.expectedContentLength
            acceptsRanges = http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes"
        default:
            throw URLError(.badServerResponse)
        }
        // Live photos can arrive as application/octet-stream after a redirect
        // to a .mov URL. Supply a media UTI, not the generic MIME type.
        let mimeType = response.mimeType.flatMap { UTType(mimeType: $0) }
        let fileType = response.url.flatMap { UTType(filenameExtension: $0.pathExtension) }
        contentType = [mimeType, fileType].compactMap { $0 }.first { $0.conforms(to: .audiovisualContent) }?
            .identifier ?? UTType.mpeg4Movie.identifier
    }
}
