import Foundation

/// An X identity, kept separate from both a login account and Weibo's user model.
struct XProfileUser: Sendable, Hashable {
    var id: String? = nil
    var handle: String? = nil
    var name: String? = nil
    var avatar: String? = nil
}

struct XUserProfile: Sendable {
    let user: XProfileUser
    let description: String?
    let coverURL: String?
    let location: String?
    let followers: Int64?
    let following: Int64?
    let posts: Int64?
    let followsYou: Bool
    let followed: Bool
    let verified: Bool
    let protected: Bool
}

func parseXProfile(_ json: JSON) throws -> XUserProfile {
    let result = json["data"]?["user"]?["result"]
    guard let id = result?["rest_id"]?.string, !id.isEmpty,
        let handle = result?["core"]?["screen_name"]?.string ?? result?["legacy"]?["screen_name"]?.string,
        handle.range(of: #"^[A-Za-z0-9_]{1,15}$"#, options: .regularExpression) != nil
    else { throw WeiboError.api("用户不存在或暂时无法查看") }
    let legacy = result?["legacy"]
    func text(_ value: String?) -> String? {
        value.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }
    func count(_ key: String) -> Int64? { legacy?[key]?.int.map { max(0, $0) } }
    return XUserProfile(
        user: XProfileUser(
            id: id, handle: handle,
            name: result?["core"]?["name"]?.string ?? legacy?["name"]?.string ?? handle,
            avatar: result?["avatar"]?["image_url"]?.url ?? legacy?["profile_image_url_https"]?.url),
        description: text(result?["profile_bio"]?["description"]?.string ?? legacy?["description"]?.string),
        coverURL: legacy?["profile_banner_url"]?.url,
        location: text(result?["location"]?["location"]?.string ?? legacy?["location"]?.string),
        followers: count("followers_count"), following: count("friends_count"),
        posts: count("statuses_count"),
        followsYou: (result?["relationship_perspectives"]?["followed_by"]?.bool
            ?? legacy?["followed_by"]?.bool) == true,
        followed: (result?["relationship_perspectives"]?["following"]?.bool ?? legacy?["following"]?.bool)
            == true,
        verified: result?["is_blue_verified"]?.bool == true
            || result?["verification"]?["verified"]?.bool == true || legacy?["verified"]?.bool == true,
        protected: (result?["privacy"]?["protected"]?.bool ?? legacy?["protected"]?.bool) == true)
}

func parseXUserPosts(_ json: JSON, previousCursor: String? = nil) throws -> Paged<XPost> {
    let user = json["data"]?["user"]?["result"]
    guard
        let instructions =
            (user?["timeline_v2"]?["timeline"]?["instructions"]
            ?? user?["timeline"]?["timeline"]?["instructions"])?.array
    else { throw WeiboError.api("暂时无法查看这个用户的帖子，请在 X 网页检查访问权限") }
    return parseXEntries(instructions, previousCursor: previousCursor)
}
