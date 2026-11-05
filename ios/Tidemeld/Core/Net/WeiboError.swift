import Foundation

/// A failure talking to Weibo, carrying a message fit to show the user.
enum WeiboError: Error, Sendable, Equatable, LocalizedError {
    /// The stored session is missing, expired, or was rejected.
    case sessionExpired
    /// Weibo wants the user to pass a captcha at the URL before continuing.
    case captchaRequired(URL)
    case rateLimited(status: Int)
    case network
    /// Weibo answered, but with an error or a response we don't understand.
    case api(String, status: Int? = nil)
    /// The request was given up on (its page went away, say): not a failure
    /// to show, as Kotlin's cancellation isn't one.
    case cancelled

    var message: String {
        switch self {
        case .sessionExpired: "登录已过期，请重新登录"
        case .captchaRequired: "需要先完成微博的安全验证"
        case .rateLimited: "请求太频繁，请稍后再试"
        case .network: "网络连接失败，请检查网络"
        case .api(let message, _): message
        case .cancelled: "已取消"
        }
    }

    var errorDescription: String? { message }

    var captchaURL: URL? {
        if case .captchaRequired(let url) = self { return url }
        return nil
    }

    /// [error] as a WeiboError: a cancellation as one, a URL loading error as a
    /// network failure, and anything else as a failed load, as the Kotlin app
    /// shows what isn't a `WeiboException`.
    static func of(_ error: Error) -> WeiboError {
        if let error = error as? WeiboError { return error }
        if isCancellation(error) { return .cancelled }
        if error is URLError { return .network }
        return .api("加载失败")
    }

    static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}

/// The message to show for a failed load.
func loadErrorMessage(_ error: Error) -> String { AppFailure.of(error).message }

private let rateLimitStatuses: Set<Int> = [418, 429, 432]

func isRateLimitStatus(_ status: Int) -> Bool { rateLimitStatuses.contains(status) }

private let loginHosts: Set<String> = [
    "passport.weibo.com", "passport.weibo.cn", "login.sina.com.cn",
]

func isLoginHost(_ host: String?) -> Bool { host.map(loginHosts.contains) ?? false }

/// What came back for a request: its status, the URL it ended up at after
/// redirects, and its body.
struct HTTPReply: Sendable {
    let status: Int
    let url: URL
    let contentType: String?
    let body: Data

    var text: String { String(decoding: body, as: UTF8.self) }

    /// The body as JSON, if it was sent as JSON and parses.
    var json: JSON? {
        guard let type = contentType?.lowercased(),
            type.contains("application/json") || type.contains("text/json") || type.contains("+json")
        else { return nil }
        return JSON.parse(body)
    }
}

/// Returns the JSON object of a Weibo web API reply, or throws the matching
/// [WeiboError].
///
/// The client accepts every HTTP status, so all of Weibo's ways of saying "no"
/// are interpreted here in one place.
func unwrapResponse(_ reply: HTTPReply, json: JSON?) throws(WeiboError) -> JSON {
    let status = reply.status
    if isLoginHost(reply.url.host) { throw .sessionExpired }
    if isRateLimitStatus(status) { throw .rateLimited(status: status) }
    if status == 401 { throw .sessionExpired }

    if let data = json, data.isObject {
        // Numbers and booleans only, as Weibo sends them; JSON null is absent.
        let ok = data["ok"]
        let message = data["message"].flatMap { $0.isNull ? nil : $0 } ?? data["msg"]
        let messageText = message?.rawString ?? message?.string ?? ""
        if ok?.int == -100, ok?.rawString == nil {
            if let url = data["url"]?.string.flatMap(URL.init(string:)),
                url.absoluteString.contains("captcha")
            {
                throw .captchaRequired(url)
            }
            throw .sessionExpired
        }
        // e.g. 403 {"ok":0,"message":"前方有点拥堵，请登录后使用"}
        if status == 403, messageText.contains("登录") { throw .sessionExpired }
        let succeeded: Bool =
            switch ok {
            case nil, .null?: true
            case .int(let value)?: value == 1
            case .bool(let value)?: value
            case .double(let value)?: value == 1
            default: true
            }
        if status >= 400 || !succeeded {
            throw .api(
                message?.rawString?.isEmpty == false ? messageText : "请求失败（\(status)）",
                status: status)
        }
        return data
    }
    if status >= 400 { throw .api("请求失败（\(status)）", status: status) }
    throw .api("微博返回了无法识别的内容", status: status)
}

// This mapping belongs to the platform, not to the shared presentation components.
extension WeiboError: UserFacingFailure {
    var appFailure: AppFailure {
        switch self {
        case .sessionExpired: AppFailure(message: message, recovery: .signIn)
        case .captchaRequired(let url): AppFailure(message: message, recovery: .verify(url))
        case .network: .network
        case .cancelled: .cancelled
        default: AppFailure(message: message)
        }
    }
}
