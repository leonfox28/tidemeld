import Foundation

/// An immutable reference allows nested quotes without discarding the post needed by detail pages.
final class XQuote: Sendable {
    let post: XPost
    init(_ post: XPost) { self.post = post }
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
    var metrics = XMetrics()
    var replyTo: String? = nil
    var attachments: [MixedMedia] = []
    var replyToHandles: [String] = []
    var media: [MixedMedia] {
        if !attachments.isEmpty { return attachments }
        return pictures.map(MixedMedia.pic)
            + (videoCover != nil || videoURL != nil
                ? [.video(VideoInfo(coverURL: videoCover, streamURLs: videoURL.map { [$0] } ?? []))] : [])
    }
    var url: URL { URL(string: "https://x.com/\(handle)/status/\(originalID)")! }
}

struct XMetrics: Sendable, Equatable {
    var likes = 0
    var reposts = 0
    var replies = 0
    var liked = false
    var reposted = false
}

struct XConversation: Sendable {
    let post: XPost?
    let replies: Paged<XPost>
    var ancestors: [XPost] = []
}

func parseXConversation(_ json: JSON, focalID: String, previousCursor: String? = nil) throws
    -> XConversation
{
    guard
        let instructions = json["data"]?["threaded_conversation_with_injections_v2"]?[
            "instructions"]?
            .array
    else { throw WeiboError.api("X 暂时无法读取这条帖子的评论") }
    let page = parseXEntries(instructions, previousCursor: previousCursor)
    let posts = Dictionary(page.items.map { ($0.originalID, $0) }, uniquingKeysWith: { first, _ in first })
    let focal = posts[focalID]
    var ancestors: [XPost] = []
    var visited: Set<String> = [focalID]
    var parent = focal?.replyTo
    while let id = parent, visited.insert(id).inserted, let post = posts[id] {
        ancestors.append(post)
        parent = post.replyTo
    }
    var related: Set<String> = [focalID]
    for _ in page.items {
        for post in page.items where !visited.contains(post.originalID) && post.replyTo.map(related.contains) == true {
            related.insert(post.originalID)
        }
    }
    return XConversation(
        post: focal,
        replies: Paged(
            items: page.items.filter {
                $0.originalID != focalID && related.contains($0.originalID)
            }, nextCursor: page.nextCursor), ancestors: Array(ancestors.reversed()))
}

func parseXPost(_ value: JSON?, promoted: Bool = false, depth: Int = 0) -> XPost? {
    guard depth < 4, let root = value?["tweet"] ?? value,
        let id = root["rest_id"]?.string, let legacy = root["legacy"]
    else { return nil }
    let user = root["core"]?["user_results"]?["result"]
    guard
        let handle = user?["core"]?["screen_name"]?.string
            ?? user?["legacy"]?["screen_name"]?.string,
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
    let entries = legacy["extended_entities"]?["media"]?.objects ?? []
    let media = parseXMedia(entries)
    let content = xPostContent(legacy, note: note, media: entries)
    let pictures = media.compactMap { if case .pic(let pic) = $0 { pic } else { nil } }
    let video = media.compactMap { if case .video(let video) = $0 { video } else { nil } }.first
    let quote = parseXPost(root["quoted_status_result"]?["result"], depth: depth + 1)
    return XPost(
        id: id, author: author, handle: handle,
        avatar: user?["avatar"]?["image_url"]?.url
            ?? user?["legacy"]?["profile_image_url_https"]?.url,
        text: content.text, createdAt: parseWeiboDate(legacy["created_at"]?.string), pictures: pictures,
        videoCover: video?.coverURL, videoURL: video?.streamURLs.first,
        quote: quote.map(XQuote.init),
        promoted: promoted,
        originalID: id,
        metrics: XMetrics(
            likes: Int(clamping: max(0, legacy["favorite_count"]?.int ?? 0)),
            reposts: Int(clamping: max(0, legacy["retweet_count"]?.int ?? 0)),
            replies: Int(clamping: max(0, legacy["reply_count"]?.int ?? 0)),
            liked: legacy["favorited"]?.bool == true, reposted: legacy["retweeted"]?.bool == true),
        replyTo: legacy["in_reply_to_status_id_str"]?.string, attachments: media,
        replyToHandles: content.replyToHandles)
}

/// Hide only reply addressing and attachments that have another native presentation.
private func xPostContent(_ legacy: JSON, note: JSON?, media: [JSON]) -> (text: String, replyToHandles: [String]) {
    let noteText = note?["text"]?.string
    var text = noteText ?? legacy["full_text"]?.string ?? ""
    var recipients: [String] = []
    if legacy["in_reply_to_status_id_str"]?.string != nil {
        if let handle = legacy["in_reply_to_screen_name"]?.string,
            handle.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil
        {
            recipients.append(handle)
        }
        // A long note has its own text and offsets, independent of the legacy preview.
        let range = (noteText != nil ? note?["display_text_range"] : legacy["display_text_range"])?.array
        if let range, range.count == 2, let start = range[0].int, let end = range[1].int,
            start > 0, start <= end, end <= (text as NSString).length
        {
            let prefix = (text as NSString).substring(to: Int(start))
            // Addressing contains ASCII handles and whitespace only; do not strip ordinary mentions.
            if prefix.range(of: #"^(?:@[A-Za-z0-9_]{1,15}\s+)+$"#, options: .regularExpression) != nil {
                recipients += prefix.split(whereSeparator: \.isWhitespace).map { String($0.dropFirst()) }
                text = (text as NSString).substring(from: Int(start))
            }
        }
    }
    for entry in media {
        let represented = parseXMedia([entry]).first
        let visible: Bool
        switch represented {
        case .pic: visible = true
        case .video(let video): visible = video.coverURL != nil || !video.streamURLs.isEmpty
        case nil: visible = false
        }
        guard visible, let url = entry["url"]?.string, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { continue }
        // Match the whole attachment token, not every t.co link or a longer URL sharing its prefix.
        let cleaned = text.replacingOccurrences(
            of: #"(?<!\S)"# + NSRegularExpression.escapedPattern(for: url) + #"(?=\s|$)"#,
            with: "", options: .regularExpression)
        if cleaned != text { text = cleaned.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    // Keep links to media we cannot render, and never truncate long text using the range's end.
    let urls = noteText != nil ? note?["entity_set"]?["urls"] : legacy["entities"]?["urls"]
    for entity in urls?.objects ?? [] {
        if let short = entity["url"]?.string, !short.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let expanded = entity["expanded_url"]?.string
        {
            text = text.replacingOccurrences(of: short, with: expanded)
        }
    }
    text = text.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&amp;", with: "&")
    var seen: Set<String> = []
    return (text, recipients.filter { seen.insert($0.lowercased()).inserted })
}

func parseXTimeline(_ json: JSON, previousCursor: String? = nil) throws -> Paged<XPost> {
    guard let instructions = json["data"]?["home"]?["home_timeline_urt"]?["instructions"]?.array
    else {
        throw WeiboError.api("X 信息流格式已变化，请稍后更新应用")
    }
    return parseXEntries(instructions, previousCursor: previousCursor)
}

private func parseXEntries(_ instructions: [JSON], previousCursor: String?) -> Paged<XPost> {
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
    // Filter before deduplication so a promoted placement cannot hide an organic copy.
    return Paged(
        items: posts.filter { !$0.promoted && seen.insert($0.id).inserted },
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
        return StoredSession(
            account: Account(uid: uid, screenName: name), cookies: ["x.com": cookies])
    }
    func timeline(
        _ stored: StoredSession, cursor: String?,
        onCookies: (@Sendable (Cookies) async -> Void)? = nil
    ) async throws -> Paged<XPost> {
        var cookies = stored.cookies["x.com"] ?? [:]
        var variables: [String: JSON] = [
            "count": .int(20), "includePromotedContent": .bool(true),
            "latestControlAvailable": .bool(true), "withCommunity": .bool(true),
            "enableRanking": .bool(false),
            "requestContext": .string(cursor == nil ? "launch" : "scroll"),
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
    func conversation(
        _ stored: StoredSession, id: String, cursor: String?,
        onCookies: (@Sendable (Cookies) async -> Void)? = nil
    ) async throws -> XConversation {
        try await withSession(stored, onCookies: onCookies) { cookies in
            var variables: [String: JSON] = [
                "focalTweetId": .string(id), "referrer": .string("home"),
                "with_rux_injections": .bool(false), "rankingMode": .string("Relevance"),
                "includePromotedContent": .bool(true), "withCommunity": .bool(true),
                "withQuickPromoteEligibilityTweetFields": .bool(true),
                "withBirdwatchNotes": .bool(true),
                "withVoice": .bool(true),
            ]
            if let cursor { variables["cursor"] = .string(cursor) }
            return try parseXConversation(
                await query("TweetDetail", variables: .object(variables), cookies: &cookies),
                focalID: id,
                previousCursor: cursor)
        }
    }

    func like(
        _ stored: StoredSession, id: String, liked: Bool,
        onCookies: (@Sendable (Cookies) async -> Void)? = nil,
        isCurrent: @Sendable @escaping () async -> Bool = { true }
    ) async throws {
        try await withSession(stored, onCookies: onCookies) { cookies in
            let result = try await query(
                liked ? "FavoriteTweet" : "UnfavoriteTweet",
                variables: .object(["tweet_id": .string(id)]),
                cookies: &cookies, write: true, isCurrent: isCurrent)
            guard result["data"]?[liked ? "favorite_tweet" : "unfavorite_tweet"]?.string == "Done"
            else {
                throw WeiboError.api(Self.writeUncertain)
            }
        }
    }

    func repost(
        _ stored: StoredSession, id: String, reposted: Bool,
        onCookies: (@Sendable (Cookies) async -> Void)? = nil,
        isCurrent: @Sendable @escaping () async -> Bool = { true }
    ) async throws {
        try await withSession(stored, onCookies: onCookies) { cookies in
            let result = try await query(
                reposted ? "CreateRetweet" : "DeleteRetweet",
                variables: .object([
                    reposted ? "tweet_id" : "source_tweet_id": .string(id),
                    "dark_request": .bool(false),
                ]), cookies: &cookies, write: true, isCurrent: isCurrent)
            let acknowledged =
                reposted
                ? result["data"]?["create_retweet"]?["retweet_results"]?["result"]?["rest_id"]?
                    .string
                    != nil
                : result["data"]?["unretweet"]?["source_tweet_results"]?["result"]?["rest_id"]?
                    .string == id
            guard acknowledged else { throw WeiboError.api(Self.writeUncertain) }
        }
    }

    func publish(
        _ stored: StoredSession, post: XPost, text: String, quote: Bool = false,
        onCookies: (@Sendable (Cookies) async -> Void)? = nil,
        isCurrent: @Sendable @escaping () async -> Bool = { true }
    ) async throws -> String {
        try await withSession(stored, onCookies: onCookies) { cookies in
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw WeiboError.api("请输入内容") }
            var variables: [String: JSON] = [
                "tweet_text": .string(text), "dark_request": .bool(false),
                "media": .object(["media_entities": .array([]), "possibly_sensitive": .bool(false)]
                ),
                "semantic_annotation_ids": .array([]),
            ]
            if quote {
                variables["attachment_url"] = .string(post.url.absoluteString)
            } else {
                variables["reply"] = .object([
                    "in_reply_to_tweet_id": .string(post.originalID),
                    "exclude_reply_user_ids": .array([]),
                ])
            }
            let result = try await query(
                "CreateTweet", variables: .object(variables), cookies: &cookies, write: true,
                isCurrent: isCurrent)["data"]?["create_tweet"]?["tweet_results"]?["result"]
            guard let id = result?["rest_id"]?.string ?? result?["tweet"]?["rest_id"]?.string else {
                throw WeiboError.api(Self.writeUncertain)
            }
            return id
        }
    }

    private func withSession<T: Sendable>(
        _ stored: StoredSession, onCookies: (@Sendable (Cookies) async -> Void)?,
        action: (inout [String: String]) async throws -> T
    ) async throws -> T {
        var cookies = stored.cookies["x.com"] ?? [:]
        guard !(cookies["auth_token"] ?? "").isEmpty, !(cookies["ct0"] ?? "").isEmpty else {
            throw WeiboError.sessionExpired
        }
        do {
            let value = try await action(&cookies)
            if cookies != stored.cookies["x.com"] { await onCookies?(["x.com": cookies]) }
            return value
        } catch {
            if cookies != stored.cookies["x.com"] { await onCookies?(["x.com": cookies]) }
            throw error
        }
    }

    private func query(
        _ operation: String, variables: JSON, cookies: inout [String: String], write: Bool = false,
        isCurrent: @Sendable @escaping () async -> Bool = { true }
    ) async throws
        -> JSON
    {
        guard let operationSpec = spec["operations"]?[operation],
            let queryID = operationSpec["queryId"]?.string
        else { throw WeiboError.api("X 接口配置不可用") }
        var url = URLComponents(string: "https://api.x.com/graphql/\(queryID)/\(operation)")!
        var body: String?
        if write {
            var payload: [String: JSON] = ["variables": variables, "queryId": .string(queryID)]
            if let features = operationSpec["features"] { payload["features"] = features }
            body = JSON.object(payload).text
        } else {
            url.queryItems = [URLQueryItem(name: "variables", value: variables.text)]
            if let features = operationSpec["features"] {
                url.queryItems?.append(URLQueryItem(name: "features", value: features.text))
            }
            if let toggles = operationSpec["fieldToggles"] {
                url.queryItems?.append(URLQueryItem(name: "fieldToggles", value: toggles.text))
            }
        }
        guard
            let json = JSON.parse(
                try await get(
                    url.url!, cookies: &cookies, api: true, body: body, isCurrent: isCurrent))
        else { throw WeiboError.api(write ? Self.writeUncertain : "X 返回了无法识别的内容") }
        let errors = json["errors"]?.objects ?? []
        let code = errors.first?["code"]?.int ?? 0
        if [32, 89, 215].contains(code) { throw WeiboError.sessionExpired }
        if code == 88 {
            await throttle.backOffMore()
            throw WeiboError.rateLimited(status: 429)
        }
        if !errors.isEmpty, write || json["data"] == nil {
            let message: String
            switch code {
            case 186: message = "内容超过 X 的长度限制，请缩短后重试"
            case 187: message = "X 提示内容重复，请先刷新确认是否已发送"
            case 226: message = "X 暂时限制了这次操作，请在官方网页检查账号状态"
            default: message = write ? "X 未确认这次操作，请刷新帖子检查状态" : "X 暂时无法读取，请在官方网页检查账号状态"
            }
            throw WeiboError.api(message)
        }
        return json
    }
    private func get(
        _ url: URL, cookies: inout [String: String], api: Bool, body: String? = nil,
        isCurrent: @Sendable @escaping () async -> Bool = { true }
    ) async throws -> String {
        guard url.scheme == "https", ["x.com", "api.x.com"].contains(url.host ?? "") else {
            throw WeiboError.api("无效的 X 请求地址")
        }
        var request = URLRequest(url: url, timeoutInterval: 25)
        request.setValue(browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://x.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            cookies.filter {
                !$0.key.contains("\n") && !$0.value.contains("\n") && !$0.value.contains("\r")
            }
            .sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; "),
            forHTTPHeaderField: "Cookie")
        if api {
            request.setValue("Bearer \(Self.webBearer)", forHTTPHeaderField: "Authorization")
            request.setValue(cookies["ct0"], forHTTPHeaderField: "x-csrf-token")
            request.setValue("OAuth2Session", forHTTPHeaderField: "x-twitter-auth-type")
            request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
            request.setValue("zh-cn", forHTTPHeaderField: "x-twitter-client-language")
        }
        if let body {
            request.httpMethod = "POST"
            request.httpBody = Data(body.utf8)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        await throttle.acquire()
        defer { Task { await throttle.release() } }
        try Task.checkCancellation()
        guard await isCurrent() else { throw WeiboError.api("账号已变更，操作已取消") }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: NoXRedirects())
        } catch {
            if body != nil { throw WeiboError.api(Self.writeUncertain) }
            throw WeiboError.isCancellation(error) ? WeiboError.cancelled : WeiboError.network
        }
        guard let http = response as? HTTPURLResponse else { throw WeiboError.network }
        if (200...299).contains(http.statusCode),
            let fields = http.allHeaderFields as? [String: String]
        {
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
        default:
            throw WeiboError.api(
                body != nil && http.statusCode >= 500
                    ? Self.writeUncertain : "X 请求失败（\(http.statusCode)）",
                status: http.statusCode)
        }
    }
    static let writeUncertain = "操作结果未确认，请先刷新帖子检查，避免重复发送"
    private static let webBearer =
        "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
}

private final class NoXRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) { completionHandler(nil) }
}
