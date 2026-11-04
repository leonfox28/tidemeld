import Foundation
import Testing

@testable import Maxbo

/// The tests that reach the one fake Weibo, one at a time.
@Suite(.serialized)
struct FakeWeiboTests {}

extension FakeWeiboTests {
@Suite
struct WeiboHTTPTests {
    private let url = URL(string: "https://weibo.com/ajax/x")!

    @Test func aQueuedRequestGoesWithTheCookiesAsTheyAreWhenItIsSent() async throws {
        FakeWeibo.reset()
        let jar = WeiboCookieJar([WeiboCookieJar.web: ["SUB": "old", "XSRF-TOKEN": "t1"]])
        let throttle = RequestThrottle(maxConcurrent: 1, minInterval: .milliseconds(300))
        let http = WeiboHTTP(jar: jar, throttle: throttle, configuration: FakeWeibo.configuration)

        async let first = http.send(URLRequest(url: url))
        async let second = http.send(URLRequest(url: url))
        // The second waits its turn meanwhile.
        try await Task.sleep(for: .milliseconds(100))
        jar.replaceAll([WeiboCookieJar.web: ["SUB": "new", "XSRF-TOKEN": "t2"]])
        _ = try await (first, second)

        let sent = FakeWeibo.requests
        #expect(sent.map { $0.value(forHTTPHeaderField: "Cookie") } == ["SUB=old; XSRF-TOKEN=t1", "SUB=new; XSRF-TOKEN=t2"])
        #expect(sent.map { $0.value(forHTTPHeaderField: "X-XSRF-TOKEN") } == ["t1", "t2"])
    }
}

@Suite
struct ImageDownloadTests {
    private func loader() -> ImageLoader {
        ImageLoader(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent("test-images-\(UUID())"),
            limitMB: 1, configuration: FakeWeibo.configuration)
    }

    private let url = "https://wx1.sinaimg.cn/orj360/a.jpg"

    @Test func aPictureNoLongerWantedStopsDownloading() async throws {
        FakeWeibo.reset { _ in .init(contentType: "image/jpeg", body: "jpeg", delay: .seconds(2)) }
        let loader = loader()

        let wanted = Task { try await loader.data(url) }
        try await Task.sleep(for: .milliseconds(200))
        wanted.cancel()
        _ = try? await wanted.value
        try await Task.sleep(for: .milliseconds(200))

        #expect(FakeWeibo.abandoned == 1)
    }

    @Test func itGoesOnWhileAnotherStillWantsIt() async throws {
        FakeWeibo.reset { _ in .init(contentType: "image/jpeg", body: "jpeg", delay: .milliseconds(500)) }
        let loader = loader()

        let first = Task { try await loader.data(url) }
        let second = Task { try await loader.data(url) }
        try await Task.sleep(for: .milliseconds(200))
        first.cancel()

        #expect(try await second.value == Data("jpeg".utf8))
        #expect(FakeWeibo.requests.count == 1)
        #expect(FakeWeibo.abandoned == 0)
    }
}
}
