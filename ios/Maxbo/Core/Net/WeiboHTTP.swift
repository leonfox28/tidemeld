import Foundation

/// The browser identity used by both the login web view and API requests, so
/// Weibo sees one consistent desktop browser throughout the session; the same
/// as the Android app's.
let browserUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    + "(KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36"

/// Calls Weibo's web endpoints the way a browser tab on weibo.com would, with
/// the cookies in a [WeiboCookieJar], spaced out by a [RequestThrottle].
///
/// Every HTTP status is accepted; use [unwrapResponse] to interpret replies.
/// Requests are never sent again on their own (PLAN §2).
final class WeiboHTTP: Sendable {
    let jar: WeiboCookieJar
    private let throttle: RequestThrottle
    private let session: URLSession
    private let userAgent: String

    /// [configuration]: tests swap in one that reaches a fake Weibo.
    init(
        jar: WeiboCookieJar, throttle: RequestThrottle,
        configuration: URLSessionConfiguration = .ephemeral, userAgent: String = browserUserAgent
    ) {
        self.jar = jar
        self.throttle = throttle
        self.userAgent = userAgent
        // Cookies are the jar's alone; nothing is cached.
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    /// Sends [request] once the throttle lets it, and reads the whole reply.
    ///
    /// - Parameter upload: whether it carries a file, which gets minutes rather
    ///   than seconds to go up and be answered.
    /// - Parameter plainCrossOrigin: send it as weibo.com's pages send a plain
    ///   cross-origin request, such as a picture upload: with cookies, but
    ///   without the XHR and XSRF headers of its own endpoints.
    func send(_ request: URLRequest, upload: Bool = false, plainCrossOrigin: Bool = false)
        async throws(WeiboError) -> HTTPReply
    {
        var request = request
        request.timeoutInterval = upload ? 120 : 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if request.value(forHTTPHeaderField: "Accept") == nil {
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        }
        if request.value(forHTTPHeaderField: "Accept-Language") == nil {
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        }
        await throttle.acquire()
        defer { Task { await throttle.release() } }
        // The cookies as they are now, not as they were when the request
        // joined the queue: the user may have signed out, or the session been
        // renewed, meanwhile (as OkHttp reads its jar as it sends).
        let delegate = HopHeaders(jar: jar, plainCrossOrigin: plainCrossOrigin)
        request = delegate.prepare(request, explicitReferer: request.value(forHTTPHeaderField: "Referer"))
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: delegate)
        } catch {
            throw .network
        }
        guard let http = response as? HTTPURLResponse else { throw .network }
        jar.apply(http)
        if isRateLimitStatus(http.statusCode) {
            await throttle.backOffMore()
        } else {
            await throttle.resetBackOff()
        }
        return HTTPReply(
            status: http.statusCode, url: http.url ?? request.url!,
            contentType: http.value(forHTTPHeaderField: "Content-Type"), body: data)
    }
}

/// Puts on each hop of a request, redirects included, the cookies and headers
/// of the site it goes to: cookies never reach a host outside their site, and
/// those any hop sets are kept.
private final class HopHeaders: NSObject, URLSessionTaskDelegate, Sendable {
    let jar: WeiboCookieJar
    let plainCrossOrigin: Bool

    init(jar: WeiboCookieJar, plainCrossOrigin: Bool) {
        self.jar = jar
        self.plainCrossOrigin = plainCrossOrigin
    }

    func prepare(_ request: URLRequest, explicitReferer: String? = nil) -> URLRequest {
        var request = request
        for name in ["Cookie", "Referer", "Origin", "X-Requested-With", "X-XSRF-TOKEN"] {
            request.setValue(nil, forHTTPHeaderField: name)
        }
        guard let url = request.url, let site = WeiboCookieJar.siteOf(url.host) else { return request }
        if let cookie = jar.header(for: url) { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let origin = site == WeiboCookieJar.mobile ? "https://m.weibo.cn" : "https://weibo.com"
        request.setValue(explicitReferer ?? "\(origin)/", forHTTPHeaderField: "Referer")
        if !plainCrossOrigin {
            request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
            if let token = jar.value(site, "XSRF-TOKEN") {
                request.setValue(token, forHTTPHeaderField: "X-XSRF-TOKEN")
            }
        }
        if request.httpMethod != nil, request.httpMethod != "GET" {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        return request
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        jar.apply(response)
        return prepare(request)
    }
}

extension URL {
    /// [url] with [query] added; nil values are left out.
    static func with(_ url: String, query: [(String, Any?)]) -> URL {
        let pairs = encodedPairs(query)
        guard !pairs.isEmpty else { return URL(string: url)! }
        return URL(string: url + (url.contains("?") ? "&" : "?") + pairs)!
    }
}

/// [fields] as `name=value&…`, values escaped as a form does; nil values are
/// left out.
func encodedPairs(_ fields: [(String, Any?)]) -> String {
    fields.compactMap { name, value -> String? in
        guard let value else { return nil }
        let encoded = "\(value)".addingPercentEncoding(withAllowedCharacters: .formValue) ?? ""
        return "\(name)=\(encoded)"
    }.joined(separator: "&")
}

/// [fields] as a form body; nil values are left out.
func formBody(_ fields: [(String, Any?)]) -> Data { Data(encodedPairs(fields).utf8) }

extension CharacterSet {
    /// What goes unescaped in a form value: ASCII letters, digits and `-._*`.
    static let formValue = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._*")
}
