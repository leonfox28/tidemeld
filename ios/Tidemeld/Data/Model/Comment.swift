import Foundation

/// How a status's comments are sorted.
enum CommentOrder: Sendable, Hashable {
    case hot, time
}

/// A comment on a status, or a reply in a comment's thread ("楼中楼").
struct Comment: Sendable, Hashable, Identifiable {
    let id: String
    var user: WeiboUser? = nil
    var createdAt: Date? = nil
    /// Where it was posted from, e.g. `来自上海`.
    var source: String? = nil
    /// The body as HTML, like `Status.text`. Replies in a thread start with
    /// `回复@name:` themselves.
    var text = ""
    var urls: [URLEntity] = []
    /// Attached pictures, which [text] doesn't mention.
    var pics: [PicInfo] = []
    var likesCount = 0
    var liked = false
    /// How many replies its thread has; [replies] previews the first few.
    var replyCount = 0
    var replies: [Comment] = []
    /// False when its author turned replies off.
    var canReply = true

    static func from(_ json: JSON?) -> Comment? {
        guard let map = json, map.isObject, let id = map["idstr"]?.string ?? map["id"]?.string
        else { return nil }
        let urlStruct = map["url_struct"]?.objects ?? []
        let pics = ownPics(map, urlStruct: urlStruct)
        var text = map["text"]?.string ?? ""
        // A comment just sent names its pictures only in pic_ids, and its text
        // ends with a short link to each, which url_struct would otherwise have
        // hidden.
        if !pics.isEmpty, !urlStruct.contains(where: hasPictures) {
            for _ in pics {
                if let range = text.range(of: trailingShortLink, options: .regularExpression) {
                    text.removeSubrange(range)
                }
            }
        }
        return Comment(
            id: id,
            user: WeiboUser.from(map["user"]),
            createdAt: parseWeiboDate(map["created_at"]?.string),
            source: map["source"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines),
            text: text,
            urls: urlStruct.compactMap(URLEntity.from),
            pics: pics,
            likesCount: Int(map["like_counts"]?.int ?? 0),
            liked: map["liked"]?.bool == true,
            replyCount: Int(map["total_number"]?.int ?? 0),
            replies: (map["comments"]?.objects ?? []).compactMap { from($0) },
            canReply: map["disable_reply"]?.int != 1)
    }

    private static let trailingShortLink =
        #"\s*<a\s[^>]*href="?https?://t\.cn/[^>]*>((?!</a>)[\s\S])*</a>\s*$"#

    private static func hasPictures(_ json: JSON) -> Bool {
        if let pics = json["pic_infos"] { return !pics.isNull }
        return false
    }

    // Pictures come as url_struct entries, each with its own pic_infos. A reply
    // also carries the entry of a picture on the comment it answers, but has
    // pic_num 0 then; its own pictures are linked from its text_raw. A comment
    // just sent has no url_struct, only the pids in pic_ids.
    private static func ownPics(_ map: JSON, urlStruct: [JSON]) -> [PicInfo] {
        if map["pic_num"]?.int == 0 { return [] }
        let entries = urlStruct.filter(hasPictures)
        if entries.isEmpty {
            return (map["pic_ids"]?.array ?? []).compactMap(\.string).compactMap(PicInfo.fromPid)
        }
        let raw = map["text_raw"]?.string
        let linked = entries.filter { entry in
            guard let short = entry["short_url"]?.string, let raw else { return false }
            return raw.contains(short)
        }
        return (linked.isEmpty ? entries : linked).flatMap(picsOf)
    }

    /// This comment with [reply] (if Weibo returned it) added to its thread.
    func withReply(_ reply: Comment?) -> Comment {
        var copy = self
        copy.replyCount += 1
        // The preview shows the first two replies.
        if let reply, replies.count < 2 { copy.replies.append(reply) }
        return copy
    }

    /// This comment with reply [id] deleted from its thread.
    func withoutReply(_ id: String) -> Comment {
        var copy = self
        copy.replyCount = max(0, replyCount - 1)
        copy.replies.removeAll { $0.id == id }
        return copy
    }
}

/// One page of a list that continues from a cursor.
struct Paged<T: Sendable>: Sendable {
    var items: [T]
    /// Fetches the page after this one; nil at the end.
    var nextCursor: String? = nil
    /// How many items the whole list has, when Weibo says.
    var total: Int? = nil
}

extension Paged {
    /// One page of a timeline: the `max_id` that fetches the next, older page is
    /// its cursor.
    static func feed(_ json: JSON) -> Paged<Status> {
        let statuses = (json["statuses"]?.objects ?? []).compactMap { Status.from($0) }
        // The `_str` twins carry the same ids without risking number precision.
        let maxId = json["max_id_str"]?.string ?? json["max_id"]?.string
        return Paged<Status>(
            items: statuses,
            nextCursor: statuses.isEmpty || maxId == nil || maxId == "0" ? nil : maxId)
    }
}
