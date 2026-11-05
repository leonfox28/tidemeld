import Foundation

/// The lists of weibo.com's 消息 page that tidemeld shows.
enum NoticeKind: Int, Sendable, Hashable, CaseIterable, Identifiable {
    /// Comments on the user's posts and replies to their comments.
    case comments
    /// Posts that mention the user.
    case mentionStatuses
    /// Comments that mention the user.
    case mentionComments
    /// Likes of the user's posts and comments.
    case likes

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .comments: "评论"
        case .mentionStatuses: "@我的微博"
        case .mentionComments: "@我的评论"
        case .likes: "赞"
        }
    }
}

/// Which [NoticeKind]s have something the user hasn't seen.
struct UnreadNotices: Sendable, Hashable {
    var kinds: Set<NoticeKind> = []

    var any: Bool { !kinds.isEmpty }

    func has(_ kind: NoticeKind) -> Bool { kinds.contains(kind) }

    func without(_ kind: NoticeKind) -> UnreadNotices { UnreadNotices(kinds: kinds.subtracting([kind])) }

    /// Reads the counts of `remind/push_count`, which sit at the top level and
    /// may leave out the ones that are 0 (PLAN §8).
    static func from(_ json: JSON) -> UnreadNotices {
        func counts(_ keys: String...) -> Bool { keys.contains { (json[$0]?.int ?? 0) > 0 } }
        var kinds: Set<NoticeKind> = []
        if counts("cmt") { kinds.insert(.comments) }
        if counts("mention_status", "all_mention_status") { kinds.insert(.mentionStatuses) }
        if counts("mention_cmt", "all_mention_cmt") { kinds.insert(.mentionComments) }
        if counts("attitude") { kinds.insert(.likes) }
        return UnreadNotices(kinds: kinds)
    }
}

/// A comment in the notifications, with the post it is on and, for a reply,
/// the comment it answers.
struct CommentNotice: Sendable, Hashable, Identifiable {
    let comment: Comment
    var status: Status? = nil
    var replyTo: Comment? = nil

    var id: String { comment.id }

    static func from(_ json: JSON?) -> CommentNotice? {
        guard let map = json, let comment = Comment.from(map) else { return nil }
        return CommentNotice(
            comment: comment, status: Status.from(map["status"]),
            replyTo: Comment.from(map["reply_comment"]))
    }
}

/// Someone liking one of the user's posts or comments.
struct LikeNotice: Sendable, Hashable, Identifiable {
    let id: String
    /// Who liked it.
    var user: WeiboUser? = nil
    var createdAt: Date? = nil
    /// The post liked, or the one [comment] is on.
    var status: Status? = nil
    /// The comment liked, if it was a comment.
    var comment: Comment? = nil
    /// False when [status] is the cut-down form Weibo sometimes sends, without
    /// pictures or counts (PLAN §8), which the detail page shouldn't show while
    /// it loads the whole post.
    var statusComplete = false

    static func from(_ json: JSON?) -> LikeNotice? {
        guard let map = json, map.isObject,
            // `idStr`, unlike everywhere else.
            let id = map["idStr"]?.string ?? map["idstr"]?.string ?? map["id"]?.string
        else { return nil }
        let comment = map["comment"].flatMap { $0.isObject ? $0 : nil }
        let status = map["status"].flatMap { $0.isObject ? $0 : nil } ?? comment?["status"]
        return LikeNotice(
            id: id,
            user: WeiboUser.from(map["user"]),
            createdAt: parseWeiboDate(map["created_at"]?.string),
            status: Status.from(status),
            comment: Comment.from(comment),
            statusComplete: status?.has("attitudes_count") == true)
    }
}

/// Weibo's hot search list ("热搜榜"), as `side/hotSearch` sends it.
struct HotSearch: Sendable, Hashable {
    /// Entries pinned above the ranking.
    var pinned: [HotSearchItem] = []
    /// The ranking, with the entries Weibo inserts into it (including paid
    /// ones) where Weibo puts them. Nothing is filtered out (PLAN §2).
    var items: [HotSearchItem] = []

    static func from(_ data: JSON) -> HotSearch {
        // Both are sent: `hotgovs` lists the pinned entries, `hotgov` holds one
        // (with a few more fields).
        let govs = data["hotgovs"]?.objects ?? []
        let pinned = govs.isEmpty ? [data["hotgov"]].compactMap { $0?.isObject == true ? $0 : nil } : govs
        return HotSearch(
            pinned: pinned.compactMap(HotSearchItem.from),
            items: (data["realtime"]?.objects ?? []).compactMap(HotSearchItem.from))
    }
}

struct HotSearchItem: Sendable, Hashable, Identifiable {
    /// The entry as shown, without the `#` of topics.
    let word: String
    /// What to search for: the word, or `#word#` for a topic.
    let query: String
    /// The position in the ranking, from 1; nil for entries outside it.
    var rank: Int? = nil
    /// Weibo's heat index.
    var heat: Int64? = nil
    /// Weibo's label, such as 热, 新, or 商 for a paid entry.
    var badge: String? = nil
    /// The label colour as 0xRRGGBB.
    var badgeColor: UInt32? = nil
    /// Marked `is_ad` by Weibo. This covers more than paid entries (a rumour
    /// rebuttal had it too), so it isn't shown as an ad label by itself.
    var isAd = false

    var id: String { "\(rank ?? 0):\(query)" }

    static func from(_ json: JSON) -> HotSearchItem? {
        guard let raw = json["word"]?.string ?? json["note"]?.string ?? json["name"]?.string
        else { return nil }
        let word =
            raw.count > 2 && raw.hasPrefix("#") && raw.hasSuffix("#")
            ? String(raw.dropFirst().dropLast()) : raw
        let isAd = json["is_ad"]?.int == 1
        // The short label is the one that says 商 on paid entries.
        let short = json["small_icon_desc"]?.string
        let badge = short ?? json["icon_desc"]?.string
        let color = short != nil ? json["small_icon_desc_color"] : json["icon_desc_color"]
        return HotSearchItem(
            word: word,
            query: json["word_scheme"]?.string ?? raw,
            rank: json["realpos"]?.int.map { Int($0) },
            heat: json["num"]?.int,
            // Never leave a promoted entry unmarked.
            badge: badge ?? (isAd ? "荐" : nil),
            badgeColor: parseColor(color?.string),
            isAd: isAd)
    }

    /// Parses `#rrggbb`.
    private static func parseColor(_ hex: String?) -> UInt32? {
        guard let hex, hex.count == 7, hex.hasPrefix("#") else { return nil }
        return UInt32(hex.dropFirst(), radix: 16)
    }
}

/// A `#话题#` as a search for it describes it ("导语", how many read it).
struct Topic: Sendable, Hashable {
    /// The topic without its `#`.
    let name: String
    /// Its lead ("导语").
    var summary: String? = nil
    var imageURL: String? = nil
    /// How many times it was read ("阅读"), all time.
    var reads: Int64? = nil
    /// How many posts discuss it ("讨论").
    var mentions: Int64? = nil
    /// How many people posted in it ("原创人数").
    var authors: Int64? = nil

    /// Reads the `topicHeads` of `statuses/search`. Searching a plain word gets
    /// one too, with counts but no name: nil then, as it is no topic.
    static func from(_ json: JSON?) -> Topic? {
        guard let map = json, map.isObject, let name = map["object"]?["display_name"]?.string
        else { return nil }
        let object = map["object"]
        let counts = map["count"]
        return Topic(
            name: name,
            summary: object?["summary"]?.string,
            imageURL: object?["image"]?["url"]?.url,
            reads: counts?["read"]?.int,
            mentions: counts?["mention"]?.int,
            authors: counts?["ori_uv"]?.int)
    }
}
