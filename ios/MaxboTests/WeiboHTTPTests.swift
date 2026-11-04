import Foundation
import Testing

@testable import Maxbo

@Suite(.serialized)
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
