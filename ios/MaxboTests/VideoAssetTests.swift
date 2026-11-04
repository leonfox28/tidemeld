import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Maxbo

struct VideoResponseTests {
    @Test func partialResponseUsesTotalLengthAndQuickTimeType() throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://cdn.test/live.mov")!, statusCode: 206, httpVersion: nil,
            headerFields: ["Content-Range": "bytes 100-199/1000", "Content-Length": "100",
                "Content-Type": "application/octet-stream"])!
        let info = try VideoResponse(response, requestedOffset: 100)
        #expect(info.offset == 100)
        #expect(info.length == 1000)
        #expect(info.acceptsRanges)
        #expect(info.contentType == UTType.quickTimeMovie.identifier)
    }

    @Test(arguments: ["bytes 0-99/1000", "bytes 100-99/1000", "bytes 100-199/150", "bytes 100-199/*", "invalid"])
    func rejectsMalformedOrWrongRanges(_ range: String) {
        let response = HTTPURLResponse(
            url: URL(string: "https://cdn.test/video.mp4")!, statusCode: 206, httpVersion: nil,
            headerFields: ["Content-Range": range])!
        #expect(throws: URLError.self) { try VideoResponse(response, requestedOffset: 100) }
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
@MainActor
struct VideoAssetTests {
    @Test(arguments: [AVFileType.mp4, .mov])
    func loadsAndSeeksWithCDNHeaders(_ type: AVFileType) async throws {
        let bytes = try await movie(type)
        FakeVideo.reset(bytes: bytes)
        let url = URL(string: "https://cdn.test/video.\(type == .mov ? "mov" : "mp4")?ssig=a%2Bb&Expires=9999999999")!
        let video = WeiboVideoAsset(url, configuration: FakeVideo.configuration)
        let playable = try await video.asset.load(.isPlayable)
        #expect(playable)
        let images = AVAssetImageGenerator(asset: video.asset)
        let frame = try await images.image(at: CMTime(seconds: 2, preferredTimescale: 600))
        #expect(frame.image.width == 16)
        let player = AVPlayer(playerItem: AVPlayerItem(asset: video.asset))
        player.automaticallyWaitsToMinimizeStalling = false
        defer { player.replaceCurrentItem(with: nil) }
        let sought = await player.seek(
            to: CMTime(seconds: 1, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        #expect(sought)
        player.play()
        for _ in 0..<200 where player.currentTime().seconds < 1.1 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(player.currentTime().seconds >= 1.1)
        #expect(!FakeVideo.requests.isEmpty)
        #expect(FakeVideo.requests.contains { $0.value(forHTTPHeaderField: "Range") != "bytes=0-1" })
        for request in FakeVideo.requests {
            #expect(request.url == url)
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://weibo.com/")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == browserUserAgent)
            #expect(request.value(forHTTPHeaderField: "Accept-Encoding") == "identity")
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Range")?.hasPrefix("bytes=") == true)
        }
        withExtendedLifetime(video) {}
    }

    @Test func handlesServersThatIgnoreRange() async throws {
        FakeVideo.reset(bytes: try await movie(.mp4), mode: .full)
        let video = WeiboVideoAsset(URL(string: "https://cdn.test/video.mp4")!, configuration: FakeVideo.configuration)
        let images = AVAssetImageGenerator(asset: video.asset)
        let frame = try await images.image(at: CMTime(seconds: 2, preferredTimescale: 600))
        #expect(frame.image.width == 16)
        withExtendedLifetime(video) {}
    }

    @Test(arguments: [FakeVideo.Mode.forbidden, .truncated])
    private func failsRejectedOrTruncatedMedia(_ mode: FakeVideo.Mode) async throws {
        FakeVideo.reset(bytes: try await movie(.mp4), mode: mode)
        let video = WeiboVideoAsset(URL(string: "https://cdn.test/video.mp4")!, configuration: FakeVideo.configuration)
        do {
            _ = try await video.asset.load(.duration)
            Issue.record("Invalid media was accepted")
        } catch {}
        withExtendedLifetime(video) {}
    }

    @Test func releasingOwnerCancelsAnOutstandingDownload() async throws {
        FakeVideo.reset(bytes: Data(), mode: .waiting)
        var video: WeiboVideoAsset? = WeiboVideoAsset(
            URL(string: "https://cdn.test/video.mp4")!, configuration: FakeVideo.configuration)
        let asset = try #require(video?.asset)
        let loading = Task { try await asset.load(.duration) }
        defer { loading.cancel() }
        for _ in 0..<200 where FakeVideo.requests.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!FakeVideo.requests.isEmpty)
        video = nil
        for _ in 0..<200 where FakeVideo.stopped == 0 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(FakeVideo.stopped > 0)
    }

    /// Three synthetic frames, encoded locally; no real Weibo media or session.
    private func movie(_ type: AVFileType) async throws -> Data {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try AVAssetWriter(outputURL: url, fileType: type)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16,
        ])
        let pixels = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        #expect(CVPixelBufferCreate(nil, 16, 16, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
        let frame = try #require(buffer)
        CVPixelBufferLockBaseAddress(frame, [])
        memset(CVPixelBufferGetBaseAddress(frame), 255, CVPixelBufferGetDataSize(frame))
        CVPixelBufferUnlockBaseAddress(frame, [])
        for second in 0..<3 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            #expect(pixels.append(frame, withPresentationTime: CMTime(value: Int64(second), timescale: 1)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return try Data(contentsOf: url)
    }
}

private final class FakeVideo: URLProtocol {
    enum Mode: Sendable { case ranges, full, forbidden, truncated, waiting }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var bytes = Data()
    nonisolated(unsafe) private static var mode = Mode.ranges
    nonisolated(unsafe) private static var received: [URLRequest] = []
    nonisolated(unsafe) private static var cancellations = 0
    private var waiting = false

    static var requests: [URLRequest] { lock.withLock { received } }
    static var stopped: Int { lock.withLock { cancellations } }

    static func reset(bytes: Data, mode: Mode = .ranges) {
        lock.withLock {
            self.bytes = bytes
            self.mode = mode
            received = []
            cancellations = 0
        }
    }

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeVideo.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (bytes, mode) = Self.lock.withLock {
            Self.received.append(request)
            return (Self.bytes, Self.mode)
        }
        if mode == .waiting {
            waiting = true
            return
        }
        let range = request.value(forHTTPHeaderField: "Range")?.dropFirst(6).split(
            separator: "-", omittingEmptySubsequences: false) ?? []
        let start = mode == .full ? 0 : range.first.flatMap { Int($0) } ?? 0
        let end = mode == .full ? bytes.count : min((range.last.flatMap { Int($0) } ?? (bytes.count - 1)) + 1, bytes.count)
        guard start < end else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        var headers = ["Content-Type": "application/octet-stream", "Content-Length": "\(end - start)"]
        if mode != .full { headers["Content-Range"] = "bytes \(start)-\(end - 1)/\(bytes.count)" }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: mode == .forbidden ? 403 : (mode == .full ? 200 : 206),
            httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if mode != .truncated {
            // Several callbacks exercise incremental delivery and byte clipping.
            for offset in stride(from: start, to: end, by: 257) {
                client?.urlProtocol(self, didLoad: bytes.subdata(in: offset..<min(offset + 257, end)))
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        if waiting { Self.lock.withLock { Self.cancellations += 1 } }
    }
}
