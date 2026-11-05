import Foundation

/// A page of search results, with the topic if one was searched for.
struct SearchResults: Sendable {
    let statuses: Paged<Status>
    let topic: Topic?
}

/// The pid in picupload's answer [body], or nil if the upload failed.
///
/// It answers `{"code":"A00006","data":{"pics":{"pic_1":{"pid":…}}}}`, the newer
/// upload `{"ret":true,"pic":{"pid":…}}`; either may follow a script prelude.
func parseUploadedPid(_ body: String) -> String? {
    guard let start = body.firstIndex(of: "{"), let json = JSON.parse(String(body[start...])),
        json.isObject
    else { return nil }
    if json["ret"]?.bool == true { return json["pic"]?["pid"]?.string }
    guard json["code"]?.string == "A00006" else { return nil }
    return json["data"]?["pics"]?["pic_1"]?["pid"]?.string
}

/// Extracts the `window.$CONFIG = {...}` object that weibo.com embeds in its
/// pages, or returns nil if the page has none or it isn't valid JSON.
///
/// The web app reads the signed-in user from it; there is no JSON endpoint for
/// that (`/ajax/config` answers 404).
func extractPageConfig(_ html: String) -> JSON? {
    let s = Array(html.utf8)
    guard let marker = html.utf8.firstRange(of: "window.$CONFIG".utf8)?.lowerBound else { return nil }
    var i = html.utf8.distance(from: html.utf8.startIndex, to: marker)
    while i < s.count, s[i] != UInt8(ascii: "{") { i += 1 }
    guard i < s.count else { return nil }
    let start = i
    var depth = 0
    var inString = false
    while i < s.count {
        let c = s[i]
        if inString {
            if c == UInt8(ascii: "\\") { i += 1 } else if c == UInt8(ascii: "\"") { inString = false }
        } else if c == UInt8(ascii: "\"") {
            inString = true
        } else if c == UInt8(ascii: "{") {
            depth += 1
        } else if c == UInt8(ascii: "}") {
            depth -= 1
            if depth == 0 {
                let json = JSON.parse(Data(s[start...i]))
                return json?.isObject == true ? json : nil
            }
        }
        i += 1
    }
    return nil
}

/// Weibo's web endpoints, as used by weibo.com in a browser.
///
/// [onSessionExpired] is called whenever Weibo rejects the session of a request
/// sent at the given time; it returns whether the session has been renewed.
final class WeiboAPI: Sendable {
    static let web = "https://weibo.com"

    let http: WeiboHTTP
    private let onSessionExpired: (@Sendable (ContinuousClock.Instant) async -> Bool)?

    init(http: WeiboHTTP, onSessionExpired: (@Sendable (ContinuousClock.Instant) async -> Bool)? = nil) {
        self.http = http
        self.onSessionExpired = onSessionExpired
    }

    /// This API without renewal: a rejected session fails the request and
    /// nothing else, so an odd answer to a diagnostic request never signs the
    /// user out.
    func withoutRenewal() -> WeiboAPI { WeiboAPI(http: http) }

    /// The signed-in account; throws `sessionExpired` for visitors.
    ///
    /// weibo.com has no JSON endpoint for this; the web app reads the user from
    /// the `$CONFIG` object embedded in its home page, and so do we.
    func fetchCurrentAccount() async throws -> Account {
        let html = try await getPage("\(Self.web)/")
        guard let config = extractPageConfig(html) else {
            devLog("weibo.com page has no $CONFIG (\(html.count) chars)")
            throw WeiboError.api("无法识别当前登录的账号")
        }
        guard let account = Account.from(pageConfig: config) else {
            devLog("no user in $CONFIG: \(config.shape(maxDepth: 1))")
            throw WeiboError.sessionExpired
        }
        return account
    }

    /// A page of the "最新微博" timeline of [uid]: the newest page, or the one
    /// after [maxId] (a previous page's cursor).
    func fetchHomeTimeline(uid: String, maxId: String? = nil) async throws -> Paged<Status> {
        let json = try await getJSON(
            "\(Self.web)/ajax/feed/friendstimeline",
            [
                // The built-in "最新微博" group; see PLAN §8 item 3.
                ("list_id", "11000\(uid)"), ("refresh", 4), ("count", 20),
                maxId == nil ? ("since_id", 0) : ("max_id", maxId),
            ])
        let page = Paged<Status>.feed(json)
        devLog("timeline: \(page.items.count) statuses, more=\(page.nextCursor != nil)")
        return page
    }

    /// Status [id] with its full text (timelines truncate long posts), current
    /// counts and freshly signed video URLs.
    func fetchStatus(_ id: String) async throws -> Status {
        // With this flag `text` holds the whole post as HTML; the longtext
        // endpoint only has it as plain text (PLAN §8).
        let json = try await getJSON(
            "\(Self.web)/ajax/statuses/show", [("id", id), ("isGetLongText", "true")])
        guard let status = Status.from(json) else { throw WeiboError.api("微博不存在或已被删除") }
        return status
    }

    /// A page of the comments on status [statusId] by [authorId], continuing
    /// after [maxId] (a previous page's cursor).
    func fetchComments(statusId: String, authorId: String, order: CommentOrder, maxId: String? = nil)
        async throws -> Paged<Comment>
    {
        commentPage(
            try await getJSON(
                "\(Self.web)/ajax/statuses/buildComments",
                [
                    ("is_reload", 1), ("id", statusId), ("is_show_bulletin", 2), ("is_mix", 0),
                    ("count", 20), ("uid", authorId), ("fetch_level", 0),
                    ("flow", order == .hot ? 0 : 1), ("locale", "zh-CN"), ("max_id", maxId),
                ]))
    }

    /// A page of the replies in the thread of comment [commentId], on a status
    /// by [authorId].
    func fetchReplies(commentId: String, authorId: String, maxId: String? = nil) async throws
        -> Paged<Comment>
    {
        commentPage(
            try await getJSON(
                "\(Self.web)/ajax/statuses/buildComments",
                [
                    ("is_reload", 1), ("id", commentId), ("is_show_bulletin", 2), ("is_mix", 1),
                    ("fetch_level", 1), ("max_id", maxId ?? "0"), ("count", 20), ("uid", authorId),
                    ("locale", "zh-CN"),
                ]))
    }

    // Comment lists continue from `max_id`, which is 0 on the last page.
    private func commentPage(_ json: JSON) -> Paged<Comment> {
        let comments = (json["data"]?.objects ?? []).compactMap { Comment.from($0) }
        let maxId = json["max_id"]?.string
        devLog("comments: \(comments.count), more=\(maxId != "0")")
        return Paged(
            items: comments,
            nextCursor: comments.isEmpty || maxId == nil || maxId == "0" ? nil : maxId,
            total: json["total_number"]?.int.map { Int($0) })
    }

    /// Page [page] (from 1) of the reposts of status [statusId], newest first.
    func fetchReposts(statusId: String, page: Int = 1) async throws -> Paged<Status> {
        let json = try await getJSON(
            "\(Self.web)/ajax/statuses/repostTimeline",
            // Weibo sends 20 a page whatever `count` asks for.
            [("id", statusId), ("page", page), ("moduleID", "feed"), ("count", 20)])
        let reposts = (json["data"]?.objects ?? []).compactMap { Status.from($0) }
        let maxPage = json["max_page"]?.int.map { Int($0) } ?? page
        return Paged(
            items: reposts,
            nextCursor: reposts.isEmpty || page >= maxPage ? nil : "\(page + 1)",
            total: json["total_number"]?.int.map { Int($0) })
    }

    /// The profile of the user with [uid], or else named [screenName] (all that
    /// mentions in a status carry).
    func fetchProfile(uid: String? = nil, screenName: String? = nil) async throws -> UserProfile {
        let json = try await getJSON(
            "\(Self.web)/ajax/profile/info",
            uid != nil ? [("uid", uid)] : [("screen_name", screenName)])
        // An unknown name still gets ok=1, with no `data` but an empty `user`.
        guard let profile = UserProfile.from(json["data"]) else { throw WeiboError.api("找不到这个用户") }
        return profile
    }

    /// Page [page] (from 1) of the statuses of user [uid], newest first after
    /// any pinned ones.
    func fetchUserStatuses(uid: String, page: Int = 1) async throws -> Paged<Status> {
        let json = try await getJSON(
            "\(Self.web)/ajax/statuses/mymblog", [("uid", uid), ("page", page), ("feature", 0)])
        let data = json["data"]
        let statuses = (data?["list"]?.objects ?? []).compactMap { Status.from($0) }
        // The page number alone pages through; `since_id` is empty on the last
        // page (PLAN §8).
        let last = statuses.isEmpty || data?["since_id"]?.rawString == ""
        devLog("user statuses p\(page): \(statuses.count), more=\(!last)")
        return Paged(
            items: statuses, nextCursor: last ? nil : "\(page + 1)",
            total: data?["total"]?.int.map { Int($0) })
    }

    func fetchHotSearch() async throws -> HotSearch {
        HotSearch.from(try await getJSON("\(Self.web)/ajax/side/hotSearch")["data"] ?? .object([:]))
    }

    /// Page [page] (from 1) of the posts across Weibo that match [query], newest
    /// first. A `#话题#` finds the posts in that topic, and comes with the topic.
    ///
    /// This is weibo.com's search of the home feed, which sends `atten=1` to
    /// keep to followed users; without it, it searches everyone (PLAN §8).
    func searchStatuses(_ query: String, page: Int = 1) async throws -> SearchResults {
        let json = try await getJSON(
            "\(Self.web)/ajax/statuses/search", [("q", query), ("count", 20), ("page", page)])
        let statuses = (json["statuses"]?.objects ?? []).compactMap { Status.from($0) }
        // Results come in as they are posted, so the next page may repeat the
        // end of this one; only an empty page ends them.
        devLog("search p\(page): \(statuses.count)")
        return SearchResults(
            statuses: Paged(
                items: statuses, nextCursor: statuses.isEmpty ? nil : "\(page + 1)",
                total: json["total_number"]?.int.map { Int($0) }),
            topic: Topic.from(json["topicHeads"]))
    }

    /// Which kinds of notifications are unread.
    ///
    /// weibo.com polls these every 30 s, by JSONP and with its own `source`; we
    /// ask only when the user opens the app (PLAN §2), and plain JSON comes back
    /// without a callback. A failure here never ends the session: this host
    /// isn't the API the session is checked against.
    func fetchUnreadNotices() async throws -> UnreadNotices {
        let url = URL.with(
            "https://rm.api.weibo.com/2/remind/push_count.json",
            query: [
                ("trim_null", 1), ("with_dm_group", 1), ("with_reminding", 1), ("with_settings", 1),
                // weibo.com leaves likes out; we want them.
                ("exclude_attitude", 0), ("with_chat_group_notice", 1), ("source", 339644097),
                ("with_chat_group", 1), ("with_dm_unread", 1),
            ])
        let reply = try await http.send(URLRequest(url: url))
        let data = reply.json
        log("GET", url, reply, data?.isObject == true ? "map" : "not an object")
        guard reply.status == 200, let data, data.isObject else {
            throw WeiboError.api("未读消息获取失败（\(reply.status)）", status: reply.status)
        }
        return UnreadNotices.from(data)
    }

    /// A page of the comments on the user's posts and replies to them.
    func fetchCommentNotices(maxId: String? = nil) async throws -> Paged<CommentNotice> {
        try await noticePage("message/cmt", "comments", CommentNotice.from, maxId)
    }

    /// A page of the comments that mention the user.
    func fetchMentionComments(maxId: String? = nil) async throws -> Paged<CommentNotice> {
        try await noticePage("comments/mentions", "comments", CommentNotice.from, maxId)
    }

    /// A page of the posts that mention the user.
    func fetchMentionStatuses(maxId: String? = nil) async throws -> Paged<Status> {
        try await noticePage("statuses/mentions", "statuses", { Status.from($0) }, maxId)
    }

    /// A page of the likes of the user's posts and comments.
    func fetchLikeNotices(maxId: String? = nil) async throws -> Paged<LikeNotice> {
        try await noticePage("message/attitudes", "attitudes", LikeNotice.from, maxId)
    }

    // The 消息 lists: items under `data.<key>`, newest first, continuing from
    // `next_cursor`, which is 0 on the last page (PLAN §8). Fetching one marks
    // its kind read on Weibo's side.
    private func noticePage<T: Sendable>(
        _ path: String, _ key: String, _ parse: (JSON?) -> T?, _ maxId: String?
    ) async throws -> Paged<T> {
        let json = try await getJSON("\(Self.web)/ajax/\(path)", [("max_id", maxId ?? "0")])
        let data = json["data"]
        let items = (data?[key]?.objects ?? []).compactMap(parse)
        let next = data?["next_cursor"]?.string
        let more = !items.isEmpty && next != nil && next != "0"
        devLog("\(path): \(items.count), more=\(more)")
        return Paged(
            items: items, nextCursor: more ? next : nil, total: data?["total_number"]?.int.map { Int($0) })
    }

    /// Likes status [id], or takes the like back when [liked] is false.
    func likeStatus(_ id: String, liked: Bool = true) async throws {
        try checkLike(
            try await postForm(
                "\(Self.web)/ajax/statuses/\(liked ? "setLike" : "cancelLike")", [("id", id)]),
            liked: liked)
    }

    /// Likes comment [id], or takes the like back when [liked] is false.
    func likeComment(_ id: String, liked: Bool = true) async throws {
        try checkLike(
            try await postForm(
                "\(Self.web)/ajax/statuses/\(liked ? "updateLike" : "destroyLike")",
                [("object_id", id), ("object_type", "comment")]),
            liked: liked)
    }

    // Some answers carry a `result`, and say ok even when it is false: taking a
    // like back right after giving it does nothing, for one (PLAN §8).
    private func checkLike(_ json: JSON, liked: Bool) throws {
        if json["result"]?.bool == false {
            throw WeiboError.api(liked ? "点赞没有成功，请稍后再试" : "取消赞没有成功，请稍后再试")
        }
    }

    /// Whether comments on status [id] may carry a picture; its author can turn
    /// that off. weibo.com asks before it offers one.
    func allowsCommentPicture(_ id: String) async throws -> Bool {
        let json = try await getJSON("\(Self.web)/ajax/statuses/checkAllowCommentWithPic", [("id", id)])
        return json["result"]?.bool != false
    }

    /// Comments [text] on status [statusId], or with [replyTo] replies to that
    /// comment (or reply) under it, with the uploaded picture [pid] if any.
    /// Returns the new comment as Weibo shows it, or nil when its answer has none.
    func postComment(statusId: String, text: String, replyTo: String? = nil, pid: String? = nil)
        async throws -> Comment?
    {
        let json = try await postForm(
            "\(Self.web)/ajax/comments/\(replyTo == nil ? "create" : "reply")",
            [
                ("id", statusId), ("cid", replyTo),
                // Empty with a picture alone, as weibo.com sends it.
                ("comment", text), ("pic_id", pid),
                // Don't also repost it or comment on the retweeted post.
                ("is_repost", 0), ("comment_ori", 0), ("is_comment", 0),
            ])
        return Comment.from(json["data"])
    }

    /// Deletes comment (or reply) [id], which the user wrote.
    func deleteComment(_ id: String) async throws {
        _ = try await postForm("\(Self.web)/ajax/statuses/destroyComment", [("cid", id)])
    }

    /// Uploads a picture for a new post or a comment and returns its pid, as
    /// weibo.com's composer does: the file's bytes as they are, to picupload.
    func uploadPicture(_ bytes: Data) async throws -> String {
        try await guarded {
            let url = URL.with(
                "https://picupload.weibo.com/interface/pic_upload.php",
                query: [("app", "miniblog"), ("s", "json"), ("p", 1), ("data", 1)])
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            // What the web sends, without a boundary: the body is the file.
            request.setValue("multipart/form-data", forHTTPHeaderField: "Content-Type")
            request.httpBody = bytes
            let reply = try await self.http.send(request, upload: true, plainCrossOrigin: true)
            self.log("POST", url, reply, "\(reply.body.count) bytes")
            if isLoginHost(reply.url.host) { throw WeiboError.sessionExpired }
            if isRateLimitStatus(reply.status) { throw WeiboError.rateLimited(status: reply.status) }
            guard let pid = parseUploadedPid(reply.text) else {
                devLog("pic_upload: \(reply.status) \(JSON.parse(reply.body)?.shape() ?? "not JSON")")
                throw WeiboError.api("图片上传失败（\(reply.status)）", status: reply.status)
            }
            return pid
        }
    }

    /// Posts [text] with the uploaded pictures [pids], for [visibility]. Returns
    /// the new status as Weibo shows it, or nil when its answer has none.
    func postStatus(_ text: String, pids: [String] = [], visibility: StatusVisibility = .public)
        async throws -> Status?
    {
        let pictures =
            pids.isEmpty
            ? nil
            : JSON.array(pids.map { .object(["type": .string("pic"), "pid": .string($0)]) }).text
        let json = try await postForm(
            "\(Self.web)/ajax/statuses/update",
            [("content", text), ("pic_id", pictures), ("visible", visibility.rawValue)])
        return Status.from(json["data"])
    }

    /// Reposts status [id] with [text], for [visibility]; Weibo puts in 转发微博
    /// when [text] is empty. With [alsoComment] the text also goes as a comment
    /// on it. Returns the new status as Weibo shows it, or nil when its answer
    /// has none.
    func repostStatus(
        _ id: String, text: String = "", alsoComment: Bool = false,
        visibility: StatusVisibility = .public
    ) async throws -> Status? {
        let json = try await postForm(
            "\(Self.web)/ajax/statuses/normal_repost",
            [
                ("id", id),
                // weibo.com leaves it out when empty.
                ("comment", text.isEmpty ? nil : text),
                ("is_comment", alsoComment ? 1 : 0),
                // Don't also comment on the retweeted post.
                ("comment_ori", 0), ("is_repost", 0), ("visible", visibility.rawValue),
            ])
        // weibo.com reads it from `data.statuses`.
        let data = json["data"]
        return Status.from(data?["statuses"]) ?? Status.from(data)
    }

    /// Deletes status [id], which the user posted.
    func deleteStatus(_ id: String) async throws {
        _ = try await postForm("\(Self.web)/ajax/statuses/destroy", [("id", id)])
    }

    /// Reads a JSON endpoint; [query] values that are nil are left out.
    func getJSON(_ url: String, _ query: [(String, Any?)] = []) async throws -> JSON {
        let url = URL.with(url, query: query)
        return try await guarded(resend: true) {
            let reply = try await self.http.send(URLRequest(url: url))
            let json = reply.json
            self.log("GET", url, reply, "ok=\(json?["ok"]?.text ?? (json == nil ? "text" : "json"))")
            return try unwrapResponse(reply, json: json)
        }
    }

    /// Posts [body] as a form, as weibo.com does for everything that changes
    /// something. Fields that are nil aren't sent.
    func postForm(_ url: String, _ body: [(String, Any?)]) async throws -> JSON {
        let form = formBody(body)
        return try await guarded {
            var request = URLRequest(url: URL(string: url)!)
            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = form
            let reply = try await self.http.send(request)
            let data = reply.json
            self.log(
                "POST", request.url!, reply,
                data?.isObject == true
                    ? "ok=\(data?["ok"]?.text ?? "-") \(data!.shape(maxDepth: 0))" : "not an object")
            let json = try unwrapResponse(reply, json: data)
            // An answer can say ok and still carry an error.
            if let error = json["error"]?.rawString, !error.isEmpty {
                throw WeiboError.api(error, status: reply.status)
            }
            return json
        }
    }

    /// Fetches an HTML page as a signed-in browser would.
    func getPage(_ url: String) async throws -> String {
        try await guarded(resend: true) {
            var request = URLRequest(url: URL(string: url)!)
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            let reply = try await self.http.send(request)
            self.log("GET", request.url!, reply, "\(reply.body.count) bytes")
            if isLoginHost(reply.url.host) { throw WeiboError.sessionExpired }
            if isRateLimitStatus(reply.status) { throw WeiboError.rateLimited(status: reply.status) }
            if reply.status != 200 {
                throw WeiboError.api("请求失败（\(reply.status)）", status: reply.status)
            }
            return reply.text
        }
    }

    /// Runs [request]. When Weibo rejects the session and it gets renewed, a
    /// request that only reads is sent again, once; others fail asking the user
    /// to try again, as sending a change twice is theirs to decide.
    private func guarded<T: Sendable>(resend: Bool = false, _ request: @Sendable () async throws -> T)
        async throws -> T
    {
        let sentAt = ContinuousClock.now
        do {
            return try await request()
        } catch WeiboError.sessionExpired {
            let renewed = await onSessionExpired?(sentAt) ?? false
            if !renewed { throw WeiboError.sessionExpired }
            if resend { return try await guarded(request) }
            throw WeiboError.api("登录状态已更新，请再试一次")
        }
    }

    private func log(_ method: String, _ url: URL, _ reply: HTTPReply, _ detail: String) {
        devLog("\(method) \(url.path) -> \(reply.status) \(detail) final=\(reply.url.host ?? "")\(reply.url.path)")
    }
}
