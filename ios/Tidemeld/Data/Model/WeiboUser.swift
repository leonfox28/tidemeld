import Foundation

/// A Weibo user as embedded in statuses.
struct WeiboUser: Sendable, Hashable, Identifiable {
    let id: String
    let screenName: String
    /// A signed URL that expires after a few hours; see `imageCacheKey`.
    var avatarURL: String? = nil
    /// Weibo's verification kind when verified: 0 is a person, 1–7 are
    /// organisations; nil when unverified.
    var verifiedType: Int? = nil

    static func from(_ json: JSON?) -> WeiboUser? {
        guard let map = json, map.isObject,
            let id = map["idstr"]?.string ?? map["id"]?.string,
            let name = map["screen_name"]?.string
        else { return nil }
        return WeiboUser(
            id: id, screenName: name,
            avatarURL: map["avatar_large"]?.url ?? map["profile_image_url"]?.url
                ?? map["avatar_hd"]?.url,
            verifiedType: map["verified"]?.bool == true ? map["verified_type"]?.int.map { Int($0) } : nil)
    }
}

/// The signed-in Weibo account.
struct Account: Sendable, Hashable, Codable {
    let uid: String
    var screenName: String? = nil

    /// Reads the account from the `$CONFIG` object weibo.com embeds in its pages,
    /// or returns nil if it names no signed-in user (as for visitors).
    static func from(pageConfig config: JSON) -> Account? {
        let user = config["user"]
        guard let uid = config["uid"]?.string ?? user?["idstr"]?.string ?? user?["id"]?.string,
            uid != "0"
        else { return nil }
        return Account(uid: uid, screenName: user?["screen_name"]?.string)
    }
}

/// A user as their profile page shows them.
struct UserProfile: Sendable, Hashable {
    let user: WeiboUser
    var description: String? = nil
    var location: String? = nil
    /// `m` or `f`.
    var gender: String? = nil
    /// What Weibo verified the user as, e.g. a job title.
    var verifiedReason: String? = nil
    var coverURL: String? = nil
    var followersCount: Int64? = nil
    var friendsCount: Int64? = nil
    var statusesCount: Int64? = nil
    /// Whether the signed-in user follows this user.
    var following = false
    /// Whether this user follows the signed-in user.
    var followsMe = false

    /// Reads the `data` object of `profile/info`.
    static func from(_ json: JSON?) -> UserProfile? {
        guard let map = json?["user"], map.isObject, let user = WeiboUser.from(map) else { return nil }
        func trimmed(_ value: JSON?) -> String? {
            let text = value?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }
        return UserProfile(
            user: user,
            description: trimmed(map["description"]),
            location: trimmed(map["location"]),
            gender: map["gender"]?.string,
            verifiedReason: user.verifiedType == nil ? nil : trimmed(map["verified_reason"]),
            // Sometimes several URLs joined with `;`.
            coverURL: readURL(map["cover_image_phone"]?.string?.split(separator: ";").first.map(String.init)),
            followersCount: map["followers_count"]?.int,
            friendsCount: map["friends_count"]?.int,
            statusesCount: map["statuses_count"]?.int,
            following: map["following"]?.bool == true,
            followsMe: map["follow_me"]?.bool == true)
    }
}
