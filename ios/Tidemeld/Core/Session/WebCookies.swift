import Foundation
import WebKit

/// The web views' cookie store, shared by the login page, the in-app browser
/// and session renewal. Weibo's session cookie (`SUB`) is HttpOnly: page
/// scripts can't see it, but the store can (PLAN §8 item 6).
@MainActor
protocol WebCookies: AnyObject {
    /// The cookies a web view would send to [url], keyed by name.
    func cookies(for url: URL) async -> [String: String]

    /// Deletes every web view cookie, signing the embedded browser out.
    func clearAll() async
}

extension WebCookies {
    /// The web views' cookies for Weibo's two sites, keyed by site.
    func readWeiboCookies() async -> Cookies {
        [
            WeiboCookieJar.web: await cookies(for: URL(string: "https://weibo.com/")!),
            WeiboCookieJar.mobile: await cookies(for: URL(string: "https://m.weibo.cn/")!),
        ]
    }
}

@MainActor
final class WebKitCookies: WebCookies {
    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    func cookies(for url: URL) async -> [String: String] {
        cookiesSent(to: url, from: await store.allCookies())
    }

    func clearAll() async {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
    }
}

/// The ones of [cookies] a browser would send to [url], keyed by name; where
/// names repeat, the one for the longer path wins, as it comes first in a
/// browser's `Cookie` header.
nonisolated func cookiesSent(to url: URL, from cookies: [HTTPCookie], now: Date = .now) -> [String: String] {
    guard let host = url.host?.lowercased() else { return [:] }
    let path = url.path.isEmpty ? "/" : url.path
    var sent: [String: (value: String, pathLength: Int)] = [:]
    for cookie in cookies {
        let domain = cookie.domain.lowercased()
        let matches =
            domain.hasPrefix(".")
            ? host == domain.dropFirst() || host.hasSuffix(domain)
            : host == domain
        guard matches, path.hasPrefix(cookie.path),
            cookie.expiresDate.map({ $0 > now }) ?? true,
            !cookie.isSecure || url.scheme == "https"
        else { continue }
        if let existing = sent[cookie.name], existing.pathLength > cookie.path.count { continue }
        sent[cookie.name] = (cookie.value, cookie.path.count)
    }
    return sent.mapValues(\.value)
}
