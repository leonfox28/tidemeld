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

private func offline() -> URLSessionConfiguration {
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
