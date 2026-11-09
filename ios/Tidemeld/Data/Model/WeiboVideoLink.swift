import Foundation

/// A video object linked from text, which need not belong to the enclosing post.
struct WeiboVideoLink: Sendable, Hashable {
    let objectID: String

    static func from(_ url: URL) -> WeiboVideoLink? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            ["http", "https"].contains(parts.scheme?.lowercased() ?? "")
        else { return nil }
        let path = parts.path
        let objectID: String?
        switch parts.host?.lowercased() {
        case "h5.video.weibo.com", "video.weibo.com":
            if path.hasPrefix("/show/") {
                objectID = String(path.dropFirst("/show/".count))
            } else if path == "/show" {
                objectID = parts.queryItems?.first { $0.name == "fid" }?.value
            } else {
                return nil
            }
        case "weibo.com", "www.weibo.com":
            if path.hasPrefix("/tv/show/") {
                objectID = String(path.dropFirst("/tv/show/".count))
            } else if path.hasPrefix("/tv/v/") {
                objectID = parts.queryItems?.first { $0.name == "fid" }?.value
            } else {
                return nil
            }
        default: return nil
        }
        guard let objectID, objectID.range(of: #"^[0-9]+:[0-9]+$"#, options: .regularExpression) != nil else { return nil }
        return WeiboVideoLink(objectID: objectID)
    }
}
