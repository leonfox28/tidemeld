import Foundation
import Testing

@testable import Tidemeld

/// The tests that reach the one fake Weibo, one at a time.
@Suite(.serialized)
struct FakeWeiboTests {}

extension FakeWeiboTests {
@Suite
struct WeiboHTTPTests {
    private let url = URL(string: "https://weibo.com/ajax/x")!

    @Test func aQueuedRequestIsCancelledWhenTheAccountChanges() async throws {
        FakeWeibo.reset()
        let jar = WeiboCookieJar([WeiboCookieJar.web: ["SUB": "old", "XSRF-TOKEN": "t1"]])
        let throttle = RequestThrottle(maxConcurrent: 1, minInterval: .milliseconds(300))
        let http = WeiboHTTP(jar: jar, throttle: throttle, configuration: FakeWeibo.configuration)
        _ = try await http.send(URLRequest(url: url))
        let second = Task { try await http.send(URLRequest(url: url)) }
        try await Task.sleep(for: .milliseconds(100))
        jar.replaceAll([WeiboCookieJar.web: ["SUB": "other", "XSRF-TOKEN": "t2"]], newIdentity: true)
        await #expect(throws: WeiboError.cancelled) { try await second.value }
        #expect(FakeWeibo.requests.count == 1)
        #expect(FakeWeibo.requests.first?.value(forHTTPHeaderField: "Cookie") == "SUB=old; XSRF-TOKEN=t1")
    }

    @Test func lateResponseCookiesCannotOverwriteANewlySelectedAccount() async throws {
        FakeWeibo.reset { _ in .init(headers: ["Set-Cookie": "SUB=stale; Path=/"], delay: .milliseconds(300)) }
        let jar = WeiboCookieJar([WeiboCookieJar.web: ["SUB": "old"]])
        let http = WeiboHTTP(jar: jar, throttle: RequestThrottle(minInterval: .zero), configuration: FakeWeibo.configuration)
        let pending = Task { try await http.send(URLRequest(url: url)) }
        try await Task.sleep(for: .milliseconds(100))
        jar.replaceAll([WeiboCookieJar.web: ["SUB": "other"]], newIdentity: true)
        await #expect(throws: WeiboError.cancelled) { try await pending.value }
        #expect(jar.value("weibo.com", "SUB") == "other")
        #expect(FakeWeibo.requests.first?.value(forHTTPHeaderField: "Cookie") == "SUB=old")
    }

    @Test func aRequestGivenUpOnSaysSoRatherThanBlamingTheNetwork() async throws {
        FakeWeibo.reset { _ in .init(delay: .seconds(2)) }
        let http = WeiboHTTP(
            jar: WeiboCookieJar([:]), throttle: RequestThrottle(minInterval: .zero),
            configuration: FakeWeibo.configuration)

        let request = Task { try await http.send(URLRequest(url: url)) }
        try await Task.sleep(for: .milliseconds(200))
        request.cancel()

        await #expect(throws: WeiboError.cancelled) { try await request.value }
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

extension FakeWeiboTests {
@MainActor @Suite
struct StatusWriteTests {
    /// A repost of a long post, cut short as lists have it.
    private let cutRepost = Status.from(
        json(#"{"id":"2","text":"转发理由","user":{"id":"8","screen_name":"转发的人"},"retweeted_status":{"id":"1","text":"原文","user":{"id":"9","screen_name":"原作者"}}}"#))!

    @Test func aRepostSheetWaitingOnTheFullTextIsDroppedOnceThePageIsLeft() async throws {
        FakeWeibo.reset { _ in
            .init(body: #"{"id":"2","text":"转发理由","longText":{"content":"转发理由全文"},"user":{"id":"8","screen_name":"转发的人"},"retweeted_status":{"id":"1","text":"原文"}}"#, delay: .milliseconds(500))
        }
        let graph = testGraph(configuration: FakeWeibo.configuration)
        graph.router.push(.status(id: "2", initial: nil))

        graph.repost(cutRepost)
        graph.router.pop()
        try await Task.sleep(for: .seconds(1))

        #expect(FakeWeibo.requests.count == 1)
        #expect(graph.router.repost == nil)
    }

    @Test func onThePageItOpens() async throws {
        FakeWeibo.reset { _ in
            .init(body: #"{"id":"2","text":"转发理由","longText":{"content":"转发理由全文"},"user":{"id":"8","screen_name":"转发的人"},"retweeted_status":{"id":"1","text":"原文"}}"#)
        }
        let graph = testGraph(configuration: FakeWeibo.configuration)

        graph.repost(cutRepost)
        try await Task.sleep(for: .milliseconds(500))

        #expect(graph.router.repost?.quote == "//@转发的人:转发理由全文")
    }
}
}
