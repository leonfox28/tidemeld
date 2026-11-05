import Foundation

struct XQuote: Sendable {
    let author: String
    let text: String
    let url: URL
}

struct XPost: Sendable, Identifiable {
    var id: String
    let author: String
    let handle: String
    let avatar: String?
    let text: String
    var createdAt: Date?
    let pictures: [PicInfo]
    let videoCover: String?
    let videoURL: String?
    let quote: XQuote?
    var repostedBy: String? = nil
    var promoted: Bool = false
    let originalID: String
    var url: URL { URL(string: "https://x.com/\(handle)/status/\(originalID)")! }
}

func parseXPost(_ value: JSON?, promoted: Bool = false, depth: Int = 0) -> XPost? {
    guard depth < 4, let root = value?["tweet"] ?? value,
        let id = root["rest_id"]?.string, let legacy = root["legacy"]
    else { return nil }
    let user = root["core"]?["user_results"]?["result"]
    guard let handle = user?["core"]?["screen_name"]?.string ?? user?["legacy"]?["screen_name"]?.string,
        handle.range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil
    else { return nil }
    let author = user?["core"]?["name"]?.string ?? user?["legacy"]?["name"]?.string ?? handle
    if let retweet = legacy["retweeted_status_result"]?["result"],
        var post = parseXPost(retweet, promoted: promoted, depth: depth + 1)
    {
        post.id = id
        post.repostedBy = author
        post.createdAt = parseWeiboDate(legacy["created_at"]?.string)
        return post
    }
    let note = root["note_tweet"]?["note_tweet_results"]?["result"]
    var text = note?["text"]?.string ?? legacy["full_text"]?.string ?? ""
    for entity in (note?["entity_set"]?["urls"] ?? legacy["entities"]?["urls"])?.objects ?? [] {
        if let short = entity["url"]?.string, let long = entity["expanded_url"]?.string {
            text = text.replacingOccurrences(of: short, with: long)
        }
    }
    text = text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
    let media = legacy["extended_entities"]?["media"]?.objects ?? []
    let pictures = media.filter { $0["type"]?.string == "photo" }.compactMap { $0["media_url_https"]?.url }
        .map(PicInfo.fromURL)
    let video = media.first { ["video", "animated_gif"].contains($0["type"]?.string ?? "") }
    let stream = video?["video_info"]?["variants"]?.objects.filter {
        $0["content_type"]?.string == "video/mp4"
    }
    .max { ($0["bitrate"]?.int ?? 0) < ($1["bitrate"]?.int ?? 0) }?["url"]?.url
    let quote = parseXPost(root["quoted_status_result"]?["result"], depth: depth + 1)
    return XPost(
        id: id, author: author, handle: handle,
        avatar: user?["avatar"]?["image_url"]?.url ?? user?["legacy"]?["profile_image_url_https"]?.url,
        text: text, createdAt: parseWeiboDate(legacy["created_at"]?.string), pictures: pictures,
        videoCover: video?["media_url_https"]?.url, videoURL: stream,
        quote: quote.map { XQuote(author: $0.author, text: $0.text, url: $0.url) }, promoted: promoted,
        originalID: id)
}

func parseXTimeline(_ json: JSON, previousCursor: String? = nil) throws -> Paged<XPost> {
    guard let instructions = json["data"]?["home"]?["home_timeline_urt"]?["instructions"]?.array else {
        throw WeiboError.api("X 信息流格式已变化，请稍后更新应用")
    }
    var posts: [XPost] = []
    var cursor: String?
    func item(_ content: JSON?) {
        if content?["cursorType"]?.string == "Bottom" { cursor = content?["value"]?.string }
        let candidate = content?["itemContent"] ?? content
        if let post = parseXPost(
            candidate?["tweet_results"]?["result"], promoted: candidate?["promotedMetadata"] != nil)
        {
            posts.append(post)
        }
        for child in content?["items"]?.objects ?? [] {
            let nested = child["item"]?["itemContent"]
            if let post = parseXPost(
                nested?["tweet_results"]?["result"], promoted: nested?["promotedMetadata"] != nil)
            {
                posts.append(post)
            }
        }
    }
    for instruction in instructions {
        for entry in instruction["entries"]?.objects ?? [] { item(entry["content"]) }
        if let entry = instruction["entry"] { item(entry["content"]) }
    }
    var seen: Set<String> = []
    return Paged(
        items: posts.filter { seen.insert($0.id).inserted },
        nextCursor: cursor == previousCursor ? nil : cursor)
}

/// The web client's public protocol; no developer API key or aggregation server is involved.
final class XWebAPI: Sendable {
    private let session: URLSession
    private let spec: JSON
    private let throttle: RequestThrottle
    init(
        spec: JSON, throttle: RequestThrottle = RequestThrottle(),
        configuration: URLSessionConfiguration = .ephemeral
    ) {
        self.spec = spec
        self.throttle = throttle
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }
    func verify(_ input: [String: String]) async throws -> StoredSession {
        var cookies = input
        guard !(cookies["auth_token"] ?? "").isEmpty, !(cookies["ct0"] ?? "").isEmpty else {
            throw WeiboError.sessionExpired
        }
        let home = try await get(URL(string: "https://x.com/home")!, cookies: &cookies, api: false)
        let pattern = #""user_id"\s*:\s*"(\d+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: home, range: NSRange(home.startIndex..., in: home)),
            let range = Range(match.range(at: 1), in: home)
        else { throw WeiboError.api("尚未确认 X 登录，请完成网页登录后重试") }
        let uid = String(home[range])
        let data = try await query(
            "UserByRestId",
            variables: .object(["userId": .string(uid), "withSafetyModeUserFields": .bool(true)]),
            cookies: &cookies)
        let user = data["data"]?["user"]?["result"]
        guard user?["rest_id"]?.string == uid else { throw WeiboError.sessionExpired }
        let name =
            user?["core"]?["name"]?.string ?? user?["legacy"]?["name"]?.string
            ?? user?["legacy"]?["screen_name"]?.string
        return StoredSession(account: Account(uid: uid, screenName: name), cookies: ["x.com": cookies])
    }
    func timeline(
        _ stored: StoredSession, cursor: String?, onCookies: (@Sendable (Cookies) async -> Void)? = nil
    ) async throws -> Paged<XPost> {
        var cookies = stored.cookies["x.com"] ?? [:]
        var variables: [String: JSON] = [
            "count": .int(20), "includePromotedContent": .bool(true),
            "latestControlAvailable": .bool(true), "withCommunity": .bool(true),
            "enableRanking": .bool(false), "requestContext": .string(cursor == nil ? "launch" : "scroll"),
            "seenTweetIds": .array([]),
        ]
        if let cursor { variables["cursor"] = .string(cursor) }
        do {
            let result = try await query(
                "HomeLatestTimeline", variables: .object(variables), cookies: &cookies)
            if cookies != stored.cookies["x.com"] { await onCookies?(["x.com": cookies]) }
            return try parseXTimeline(result, previousCursor: cursor)
        } catch {
            if cookies != stored.cookies["x.com"] { await onCookies?(["x.com": cookies]) }
            throw error
        }
    }
    private func query(_ operation: String, variables: JSON, cookies: inout [String: String]) async throws
        -> JSON
    {
        guard let operationSpec = spec["operations"]?[operation],
            let queryID = operationSpec["queryId"]?.string
        else { throw WeiboError.api("X 接口配置不可用") }
        var url = URLComponents(string: "https://api.x.com/graphql/\(queryID)/\(operation)")!
        url.queryItems = [
            URLQueryItem(name: "variables", value: variables.text),
            URLQueryItem(name: "features", value: operationSpec["features"]?.text),
        ]
        guard let json = JSON.parse(try await get(url.url!, cookies: &cookies, api: true)) else {
            throw WeiboError.api("X 返回了无法识别的内容")
        }
        let errors = json["errors"]?.objects ?? []
        let code = errors.first?["code"]?.int ?? 0
        if [32, 89, 215].contains(code) { throw WeiboError.sessionExpired }
        if code == 88 {
            await throttle.backOffMore()
            throw WeiboError.rateLimited(status: 429)
        }
        if !errors.isEmpty, json["data"] == nil { throw WeiboError.api("X 暂时无法读取，请在官方网页检查账号状态") }
        return json
    }
    private func get(_ url: URL, cookies: inout [String: String], api: Bool) async throws -> String {
        guard url.scheme == "https", ["x.com", "api.x.com"].contains(url.host ?? "") else {
            throw WeiboError.api("无效的 X 请求地址")
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            cookies.filter { !$0.key.contains("\n") && !$0.value.contains("\n") && !$0.value.contains("\r") }
                .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "),
            forHTTPHeaderField: "Cookie")
        if api {
            request.setValue("Bearer \(Self.webBearer)", forHTTPHeaderField: "Authorization")
            request.setValue(cookies["ct0"], forHTTPHeaderField: "x-csrf-token")
            request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
            request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
            request.setValue("zh-cn", forHTTPHeaderField: "x-twitter-client-language")
        }
        await throttle.acquire()
        defer { Task { await throttle.release() } }
        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request, delegate: NoXRedirects())
        guard let http = response as? HTTPURLResponse else { throw WeiboError.network }
        if (200...299).contains(http.statusCode), let fields = http.allHeaderFields as? [String: String] {
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
                let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                if domain == "x.com" || domain == "api.x.com" {
                    if let expiry = cookie.expiresDate, expiry <= Date() {
                        cookies.removeValue(forKey: cookie.name)
                    } else {
                        cookies[cookie.name] = cookie.value
                    }
                }
            }
        }
        switch http.statusCode {
        case 200...299: return String(decoding: data, as: UTF8.self)
        case 401: throw WeiboError.sessionExpired
        case 429:
            await throttle.backOffMore()
            throw WeiboError.rateLimited(status: 429)
        case 403: throw WeiboError.api("X 拒绝了请求，请在官方网页检查登录或安全验证", status: 403)
        case 300...399: throw WeiboError.api("请完成 X 官方网页登录后重试")
        default: throw WeiboError.api("X 加载失败（\(http.statusCode)）", status: http.statusCode)
        }
    }
    private static let webBearer =
        "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
}

private final class NoXRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}
