import Foundation

/// Public mobile feed, on a visitor-only jar that never becomes an account.
@MainActor
final class GuestWeiboAPI {
    private let http: WeiboHTTP
    private let prepare: @MainActor () async throws -> Cookies
    private var ready = false

    init(http: WeiboHTTP, prepare: @escaping @MainActor () async throws -> Cookies) {
        self.http = http
        self.prepare = prepare
    }

    func fetchTimeline() async throws -> Paged<Status> {
        if !ready {
            let cookies = try await prepare()
            http.jar.replaceAll([WeiboCookieJar.mobile: cookies[WeiboCookieJar.mobile] ?? [:]])
            let config = try await get("/api/config")
            guard config["data"]?["login"]?.bool == false else {
                http.jar.clear()
                throw WeiboError.api("游客访问暂不可用，请登录微博后重试")
            }
            ready = true
        }
        do {
            let json = try await get("/api/container/getIndex", query: [("containerid", "102803")])
            return Self.parseTimeline(json)
        } catch {
            if WeiboError.of(error) == .sessionExpired {
                ready = false
                http.jar.clear()
                throw WeiboError.api("微博暂不允许游客访问，请稍后重试或登录")
            }
            throw error
        }
    }

    static func parseTimeline(_ json: JSON) -> Paged<Status> {
        func posts(_ cards: [JSON]) -> [Status] {
            cards.flatMap { card in
                if let post = Status.from(card["mblog"]) {
                    var post = post
                    post.isAd = post.isAd || card["is_ad"]?.bool == true || card["is_ad"]?.int == 1
                    return [post]
                }
                return posts(card["card_group"]?.objects ?? [])
            }
        }
        // The next page requires sign-in. Keep the server's first page, in
        // its order, and explain that limit instead of silently retrying it.
        return Paged(items: posts(json["data"]?["cards"]?.objects ?? []))
    }

    private func get(_ path: String, query: [(String, Any?)] = []) async throws -> JSON {
        var request = URLRequest(url: URL.with("https://m.weibo.cn\(path)", query: query))
        request.setValue("https://m.weibo.cn/", forHTTPHeaderField: "Referer")
        let reply = try await http.send(request)
        return try unwrapResponse(reply, json: reply.json)
    }
}
