import Foundation
import Synchronization

/// Cookies keyed by site, then by cookie name.
typealias Cookies = [String: [String: String]]

/// Cookies for Weibo's two sites, kept in memory and scoped per site.
///
/// The web API spans weibo.com (desktop web API, passport) and weibo.cn
/// (m.weibo.cn). Scoping per site instead of per exact domain and path is all
/// these endpoints need, and keeps the jar trivial to persist.
final class WeiboCookieJar: Sendable {
    static let web = "weibo.com"
    static let mobile = "weibo.cn"
    static let sites = [web, mobile]

    private let state: Mutex<State>

    private struct State {
        var sites: [String: [(name: String, value: String)]] = [:]
        var listeners: [UUID: @Sendable () -> Void] = [:]
        var generation = 0
        var credentialRevision = 0
        var responseSink: (@Sendable (URL, [HTTPCookie]) -> Void)?
    }

    init(_ cookies: Cookies = [:]) {
        var state = State()
        Self.replace(&state, with: cookies)
        self.state = Mutex(state)
    }

    /// Freeze the request identity; only the matching generation can adopt response cookies.
    func forRequest() -> (Int, WeiboCookieJar) {
        let (ticket, credentials, cookies) = state.withLock { state in
            (state.generation, state.credentialRevision, state.sites.mapValues { Dictionary($0.map { ($0.name, $0.value) }, uniquingKeysWith: { $1 }) })
        }
        let copy = WeiboCookieJar(cookies)
        copy.state.withLock { state in state.responseSink = { [self] url, cookies in apply(url, cookies, expectedGeneration: credentials) } }
        return (ticket, copy)
    }

    var identity: Int { state.withLock { $0.generation } }

    func isCurrent(_ ticket: Int) -> Bool { state.withLock { $0.generation == ticket } }

    /// The site [host] belongs to, or nil if it isn't a Weibo host.
    static func siteOf(_ host: String?) -> String? {
        guard let host = host?.lowercased() else { return nil }
        return sites.first { host == $0 || host.hasSuffix(".\($0)") }
    }

    var isEmpty: Bool { state.withLock { $0.sites.values.allSatisfy(\.isEmpty) } }

    func value(_ site: String, _ name: String) -> String? {
        state.withLock { $0.sites[site]?.last { $0.name == name }?.value }
    }

    func names(_ site: String) -> [String] {
        state.withLock { $0.sites[site]?.map(\.name) ?? [] }
    }

    /// The `Cookie` header for a request to [url], or nil if there is none.
    func header(for url: URL) -> String? {
        state.withLock { state in
            guard let site = Self.siteOf(url.host), let cookies = state.sites[site], !cookies.isEmpty
            else { return nil }
            return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        }
    }

    /// Applies the `Set-Cookie` headers of [response].
    func apply(_ response: HTTPURLResponse) {
        guard let url = response.url, let fields = response.allHeaderFields as? [String: String]
        else { return }
        apply(url, HTTPCookie.cookies(withResponseHeaderFields: fields, for: url))
    }

    /// Applies [cookies] set by a response from [url]. Cookies for another
    /// site, which the response's host can't set, are dropped, as a browser
    /// drops them.
    func apply(_ url: URL, _ cookies: [HTTPCookie], expectedGeneration: Int? = nil) {
        guard let site = Self.siteOf(url.host), !cookies.isEmpty else { return }
        let now = Date()
        let changed = state.withLock { state in
            if let expectedGeneration, state.credentialRevision != expectedGeneration { return false }
            var jar = state.sites[site] ?? []
            var changed = false
            for cookie in cookies {
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                guard Self.siteOf(domain) == site else { continue }
                let index = jar.firstIndex { $0.name == cookie.name }
                if let expires = cookie.expiresDate, expires <= now {
                    if let index {
                        jar.remove(at: index)
                        changed = true
                    }
                } else if let index {
                    if jar[index].value != cookie.value {
                        jar[index].value = cookie.value
                        changed = true
                    }
                } else {
                    jar.append((cookie.name, cookie.value))
                    changed = true
                }
            }
            state.sites[site] = jar
            return changed
        }
        if changed { notifyListeners() }
        state.withLock { $0.responseSink }?(url, cookies)
    }

    func replaceAll(_ cookies: Cookies, newIdentity: Bool = false) {
        state.withLock { if newIdentity { $0.generation += 1 }; $0.credentialRevision += 1; Self.replace(&$0, with: cookies) }
        notifyListeners()
    }

    func clear() {
        let changed = state.withLock { state in
            state.generation += 1
            state.credentialRevision += 1
            defer { state.sites.removeAll() }
            return !state.sites.isEmpty
        }
        if changed { notifyListeners() }
    }

    func toCookies() -> Cookies {
        state.withLock { state in
            state.sites.filter { !$0.value.isEmpty }.mapValues { cookies in
                Dictionary(cookies.map { ($0.name, $0.value) }, uniquingKeysWith: { $1 })
            }
        }
    }

    /// Calls [listener] after every change, on the thread that made it.
    @discardableResult
    func addListener(_ listener: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        state.withLock { $0.listeners[id] = listener }
        return id
    }

    func removeListener(_ id: UUID) {
        _ = state.withLock { $0.listeners.removeValue(forKey: id) }
    }

    private func notifyListeners() {
        for listener in state.withLock({ Array($0.listeners.values) }) { listener() }
    }

    private static func replace(_ state: inout State, with cookies: Cookies) {
        state.sites.removeAll()
        for (site, values) in cookies where sites.contains(site) {
            state.sites[site] = values.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        }
    }
}
