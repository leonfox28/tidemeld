import Foundation

struct XUserRelationship: Sendable {
    let following: Bool
    let followsYou: Bool
    let requested: Bool
    let blocking: Bool
    let showsReposts: Bool?
}

enum XUserAction: Sendable {
    case follow(Bool)
    case block(Bool)
    case reposts(Bool)
}

func parseXRelationship(_ json: JSON, source: String, target: String) throws -> XUserRelationship {
    let relation = json["relationship"]
    let from = relation?["source"]
    guard from?["id_str"]?.string == source, relation?["target"]?["id_str"]?.string == target,
        let following = from?["following"]?.bool, let blocking = from?["blocking"]?.bool
    else { throw WeiboError.api("无法确认用户关系，请刷新后重试") }
    return XUserRelationship(
        following: following, followsYou: from?["followed_by"]?.bool == true,
        requested: from?["following_requested"]?.bool == true, blocking: blocking,
        showsReposts: from?["want_retweets"]?.bool)
}
