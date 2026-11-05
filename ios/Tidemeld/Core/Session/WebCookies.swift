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
    func clearDomains(_ domains: [String]) async
    func setCookies(host: String, cookies: [String: String]) async
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

    func setCookies(host: String, cookies: [String: String]) async {
        guard ["x.com", "weibo.com", "weibo.cn"].contains(host) else { return }
        for (name, value) in cookies {
            guard name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil,
                  !value.contains(where: { $0 == ";" || $0 == "\r" || $0 == "\n" }) else { continue }
            var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: "." + host, .path: "/", .secure: "TRUE"]
            if ["auth_token", "SUB", "SUBP"].contains(name) { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
            if let cookie = HTTPCookie(properties: properties) { await store.setCookie(cookie) }
        }
    }

    func cookies(for url: URL) async -> [String: String] {
        cookiesSent(to: url, from: await store.allCookies())
    }

    func clearAll() async {
        await WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies], modifiedSince: .distantPast)
    }

    func clearDomains(_ domains: [String]) async {
        for cookie in await store.allCookies() {
            let host = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                await store.deleteCookie(cookie)
            }
        }
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
