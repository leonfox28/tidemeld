import Foundation

@testable import Maxbo

/// Signed in as uid 7, as the Android tests' `signedIn`.
let signedIn = StoredSession(account: Account(uid: "7"), cookies: [WeiboCookieJar.web: ["SUB": "x"]])

final class FakeSessionStorage: SessionStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: StoredSession?

    init(_ stored: StoredSession? = nil) { self.stored = stored }

    func load() -> StoredSession? { lock.withLock { stored } }
    func save(_ session: StoredSession) { lock.withLock { stored = session } }
    func clear() { lock.withLock { stored = nil } }
}

@MainActor
final class FakeWebCookies: WebCookies {
    var cookies: Cookies = [:]

    func cookies(for url: URL) async -> [String: String] {
        WeiboCookieJar.siteOf(url.host).flatMap { cookies[$0] } ?? [:]
    }

    func clearAll() async { cookies = [:] }
}

/// Renews with [cookies], or fails when there are none.
@MainActor
final class FakeRenewer: SessionRenewer {
    var cookies: Cookies?

    func renew(lapsedSub: String?, adopt: @escaping @MainActor (Cookies) async -> Bool) async -> Bool {
        guard let cookies else { return false }
        return await adopt(cookies)
    }
}

/// A session and an API on it, with fakes for what is outside the app. Without
/// a [configuration], requests fail as if offline.
@MainActor
func testSession(
    restored: StoredSession? = signedIn, configuration: URLSessionConfiguration? = nil
) -> (SessionController, WeiboAPI) {
    let throttle = RequestThrottle(minInterval: .zero)
    let httpFor = { (jar: WeiboCookieJar) in
        WeiboHTTP(jar: jar, throttle: throttle, configuration: configuration ?? offline())
    }
    let session = SessionController(
        restored: restored, storage: FakeSessionStorage(restored), webCookies: FakeWebCookies(),
        renewer: FakeRenewer(), httpFor: httpFor)
    let api = WeiboAPI(http: httpFor(session.jar)) { [weak session] sentAt in
        await session?.renewOrExpire(sentAt: sentAt) ?? false
    }
    return (session, api)
}

final class FakeSettingsStorage: SettingsStorage {
    var settings = AppSettings()
    func load() -> AppSettings { settings }
    func save(_ settings: AppSettings) { self.settings = settings }
}

/// An [AppGraph] of fakes, signed in as uid 7 unless [restored] says otherwise.
@MainActor
func testGraph(restored: StoredSession? = signedIn) -> AppGraph {
    let (session, api) = testSession(restored: restored)
    let images = ImageLoader(
        directory: FileManager.default.temporaryDirectory.appendingPathComponent("test-images-\(UUID())"),
        limitMB: 1, configuration: offline())
    return AppGraph(
        settings: SettingsController(storage: FakeSettingsStorage()), session: session, api: api,
        webCookies: FakeWebCookies(), images: images)
}

func offline() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [Offline.self]
    return configuration
}

/// Fails every request, as with no network.
private final class Offline: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

/// Weibo as far as the tests' requests go: records each request and answers it
/// with [respond]. One for the whole test run, as URL loading makes its own
/// instances; suites that use it run serialized, and [reset] it first.
final class FakeWeibo: URLProtocol {
    struct Reply: Sendable {
        var status = 200
        var contentType = "application/json"
        var body = "{}"
        /// How long Weibo takes to answer.
        var delay: Duration = .zero
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var respond: @Sendable (URLRequest) -> Reply = { _ in Reply() }
    nonisolated(unsafe) private static var received: [URLRequest] = []
    nonisolated(unsafe) private static var stopped = 0

    static var requests: [URLRequest] { lock.withLock { received } }
    /// How many requests were given up before their answer.
    static var abandoned: Int { lock.withLock { stopped } }

    static func reset(_ respond: @escaping @Sendable (URLRequest) -> Reply = { _ in Reply() }) {
        lock.withLock {
            self.respond = respond
            received = []
            stopped = 0
        }
    }

    private let state = NSLock()
    nonisolated(unsafe) private var answered = false

    static var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeWeibo.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let respond = Self.lock.withLock {
            Self.received.append(request)
            return Self.respond
        }
        let reply = respond(request)
        guard reply.delay > .zero else { return answer(reply) }
        let seconds = Double(reply.delay.components.seconds) + Double(reply.delay.components.attoseconds) / 1e18
        let me = Unchecked(self)
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { me.value.answer(reply) }
    }

    private func answer(_ reply: Reply) {
        guard state.withLock({ answered ? false : { answered = true; return true }() }) else { return }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": reply.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        let unanswered = state.withLock { answered ? false : { answered = true; return true }() }
        if unanswered { Self.lock.withLock { Self.stopped += 1 } }
    }
}

/// [value], handed across threads where it is known to be safe.
struct Unchecked<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
