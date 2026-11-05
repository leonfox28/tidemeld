import Foundation
import Testing

@testable import Tidemeld

private func socialSession(_ id: String, x: Bool = false) -> StoredSession {
    StoredSession(
        account: Account(uid: id, screenName: "账号\(id)"),
        cookies: [
            x ? "x.com" : "weibo.com":
                x ? ["auth_token": "synthetic-\(id)", "ct0": "csrf-\(id)"] : ["SUB": "synthetic-\(id)"]
        ])
}

extension FakeWeiboTests {
    @MainActor @Suite struct SocialAccountsTests {
        @Test func productionFeedLoadsRestoredWeiboAccountsWithoutLeavingTheMainActor() async throws {
            FakeWeibo.reset { request in
                let id = request.value(forHTTPHeaderField: "Cookie")?.contains("synthetic-8") == true ? "8" : "7"
                return .init(body: "{\"ok\":1,\"statuses\":[{\"idstr\":\"\(id)\",\"text\":\"合成内容\"}],\"max_id\":0}")
            }
            let graph = testGraph(restored: socialSession("7"), configuration: FakeWeibo.configuration)
            try graph.accounts.add(.weibo, session: socialSession("8"))
            // Exercise the production provider closure, including forAccount(), instead of replacing it.
            graph.socialFeed.select(.all)
            await graph.socialFeed.waitForIdle()
            #expect(graph.socialFeed.errors.isEmpty)
            #expect(Set(graph.socialFeed.items.map(\.id)) == ["weibo:7", "weibo:8"])
            #expect(Set(graph.socialFeed.items.map(\.owner)) == ["weibo:7", "weibo:8"])
            #expect(FakeWeibo.requests.map { $0.value(forHTTPHeaderField: "Cookie") } == ["SUB=synthetic-7", "SUB=synthetic-8"])
            graph.socialFeed.refresh()
            await graph.socialFeed.waitForIdle()
            #expect(graph.socialFeed.items.count == 2)
            #expect(FakeWeibo.requests.count == 4)
        }

        @Test func migrationMultipleAccountsReauthenticationAndSelectiveRemoval() async throws {
            let (session, _) = testSession(restored: socialSession("7"))
            let web = FakeWebCookies()
            let storage = MemoryAccountStorage()
            let accounts = AccountManager(storage: storage, weibo: session, web: web)
            #expect(accounts.accounts.map(\.id) == ["weibo:7"])
            try accounts.add(.weibo, session: socialSession("8"))
            try accounts.add(.x, session: socialSession("7", x: true))
            web.cookies = ["weibo.com": ["SUB": "synthetic-8"], "x.com": ["auth_token": "synthetic-7"]]
            #expect(accounts.useWeibo("weibo:7"))
            #expect(session.jar.value("weibo.com", "SUB") == "synthetic-7")
            try await accounts.remove("weibo:8")
            #expect(web.cookies["x.com"]?["auth_token"] == "synthetic-7")
            #expect(Set(accounts.accounts.map(\.id)) == ["weibo:7", "x:7"])
            let renewed = StoredSession(
                account: socialSession("7").account, cookies: ["weibo.com": ["SUB": "fresh"]])
            try accounts.add(.weibo, session: renewed)
            #expect(session.jar.value("weibo.com", "SUB") == "fresh")
            #expect(accounts.accounts.count == 2)
            #expect(storage.load().count == 2)
        }

        @Test func browserSelectionKeepsOtherPlatformsAndExpiredAccountsStayExpired() async throws {
            let (session, _) = testSession(restored: socialSession("7"))
            let web = FakeWebCookies()
            web.cookies = ["weibo.com": ["SUB": "synthetic-7"]]
            let accounts = AccountManager(storage: MemoryAccountStorage(), weibo: session, web: web)
            try accounts.add(.x, session: socialSession("8", x: true))
            try accounts.add(.x, session: socialSession("9", x: true))
            try await accounts.prepareBrowser("x:8")
            #expect(web.cookies["x.com"]?["auth_token"] == "synthetic-8")
            try await accounts.prepareBrowser("x:9")
            #expect(web.cookies["x.com"]?["auth_token"] == "synthetic-9")
            #expect(web.cookies["weibo.com"]?["SUB"] == "synthetic-7")
            accounts.expire("weibo:7")
            session.jar.replaceAll(["weibo.com": ["SUB": "rotated"]])
            for _ in 0..<10 { await Task.yield() }
            #expect(accounts.find("weibo:7")?.expired == true)
            #expect(!accounts.useWeibo("weibo:7"))
            try await accounts.remove("x:8")
            #expect(web.cookies["x.com"]?["auth_token"] == "synthetic-9")
        }

        @Test func expiredVaultStaysExpiredAfterLegacyRestore() async throws {
            let (session, _) = testSession(restored: socialSession("7"))
            let storage = MemoryAccountStorage()
            storage.save([SocialAccount(platform: .weibo, session: socialSession("7"), expired: true)])
            let accounts = AccountManager(storage: storage, weibo: session, web: FakeWebCookies())
            for _ in 0..<10 { await Task.yield() }
            #expect(accounts.find("weibo:7")?.expired == true)
            #expect(session.state.uid == nil)
        }

        @Test func accountContextsKeepTheirOwnCredentialsAndRejectStaleSessionSaves() async throws {
            FakeWeibo.reset { _ in .init(body: #"{"ok":1,"statuses":[],"max_id":0}"#) }
            let graph = testGraph(restored: socialSession("7"), configuration: FakeWeibo.configuration)
            try graph.accounts.add(.weibo, session: socialSession("8"))
            let first = try #require(graph.forAccount("weibo:7"))
            let second = try #require(graph.forAccount("weibo:8"))
            _ = try await first.api.fetchHomeTimeline(uid: "7")
            _ = try await second.api.fetchHomeTimeline(uid: "8")
            #expect(
                FakeWeibo.requests.map { $0.value(forHTTPHeaderField: "Cookie") } == [
                    "SUB=synthetic-7", "SUB=synthetic-8",
                ])
            try graph.accounts.add(
                .weibo,
                session: StoredSession(
                    account: socialSession("7").account, cookies: ["weibo.com": ["SUB": "fresh"]]))
            first.session.jar.replaceAll(["weibo.com": ["SUB": "stale"]])
            for _ in 0..<10 { await Task.yield() }
            #expect(graph.accounts.find("weibo:7")?.session.cookies["weibo.com"]?["SUB"] == "fresh")
        }

        @Test func aggregationUsesIndependentCursorsDeduplicatesAndRecoversOnlyFailedSources() async throws {
            let graph = testGraph(restored: socialSession("7"))
            try graph.accounts.add(.weibo, session: socialSession("8"))
            try graph.accounts.add(.x, session: socialSession("9", x: true))
            var calls: [(String, String?)] = []
            var xFails = true
            let feed = SocialFeedController(accounts: graph.accounts) { account, cursor in
                calls.append((account.id, cursor))
                if account.platform == .x {
                    if xFails { throw WeiboError.network }
                    let post = XPost(
                        id: "1", author: "作者", handle: "fixture", avatar: nil, text: "X 内容",
                        createdAt: Date(timeIntervalSince1970: 30),
                        pictures: [], videoCover: nil, videoURL: nil, quote: nil, originalID: "1")
                    return Paged(items: [.x(owner: account.id, post)])
                }
                let id = cursor == nil ? "1" : account.session.account.uid
                let status = Status(id: id, createdAt: Date(timeIntervalSince1970: cursor == nil ? 20 : 10))
                return Paged(
                    items: [.weibo(owner: account.id, status)],
                    nextCursor: cursor == nil ? "cursor-\(account.id)" : nil)
            }
            feed.select(.all)
            await feed.waitForIdle()
            #expect(feed.items.map(\.id) == ["weibo:1"])
            #expect(Set(feed.errors.keys) == ["x:9"])
            feed.loadMore()
            await feed.waitForIdle()
            #expect(calls.contains { $0.0 == "weibo:7" && $0.1 == "cursor-weibo:7" })
            #expect(calls.contains { $0.0 == "weibo:8" && $0.1 == "cursor-weibo:8" })
            let count = calls.count
            xFails = false
            feed.retry()
            await feed.waitForIdle()
            #expect(calls.count == count + 1)
            #expect(calls.last?.0 == "x:9")
            #expect(feed.items.map(\.id) == ["x:1", "weibo:1", "weibo:7", "weibo:8"])
            feed.select(.x)
            await feed.waitForIdle()
            #expect(feed.items.map(\.id) == ["x:1"])
            try await graph.accounts.remove("x:9")
            feed.select(.x)
            await feed.waitForIdle()
            #expect(feed.items.isEmpty)
        }

        @Test func xTransportUsesOnlyTheAccountCookiesAndMapsRateLimits() async throws {
            FakeWeibo.reset { _ in .init(status: 429, body: "{}") }
            let spec = try #require(
                JSON.parse(#"{"operations":{"HomeLatestTimeline":{"queryId":"fixture","features":{}}}}"#))
            let api = XWebAPI(
                spec: spec, throttle: RequestThrottle(minInterval: .zero),
                configuration: FakeWeibo.configuration)
            await #expect(throws: WeiboError.rateLimited(status: 429)) {
                _ = try await api.timeline(socialSession("9", x: true), cursor: "next")
            }
            let request = try #require(FakeWeibo.requests.first)
            #expect(request.url?.host == "api.x.com")
            #expect(request.value(forHTTPHeaderField: "x-csrf-token") == "csrf-9")
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("SUB=") == false)
        }

        @Test func xParserPreservesAdsQuotesMediaAndCursorWithoutFlatteningQuotedPosts() throws {
            let json = try #require(
                JSON.parse(
                    #"""
                    {"data":{"home":{"home_timeline_urt":{"instructions":[{"entries":[
                      {"content":{"itemContent":{"promotedMetadata":{},"tweet_results":{"result":{"tweet":{
                        "rest_id":"1","core":{"user_results":{"result":{"core":{"name":"示例作者","screen_name":"fixture"}}}},
                        "legacy":{"full_text":"A &amp; B","created_at":"Thu Nov 05 08:00:00 +0000 2026","extended_entities":{"media":[{"type":"photo","media_url_https":"https://example.com/photo.jpg"}]}},
                        "quoted_status_result":{"result":{"rest_id":"2","core":{"user_results":{"result":{"legacy":{"name":"引用作者","screen_name":"quoted"}}}},"legacy":{"full_text":"引用内容"}}}
                      }}}}}}, {"content":{"cursorType":"Bottom","value":"next"}}
                    ]}]}}}}
                    """#))
            let page = try parseXTimeline(json)
            #expect(page.items.map(\.id) == ["1"])
            #expect(page.items.first?.text == "A & B")
            #expect(page.items.first?.promoted == true)
            #expect(page.items.first?.pictures.count == 1)
            #expect(page.items.first?.quote?.author == "引用作者")
            #expect(page.nextCursor == "next")
            #expect(try parseXTimeline(json, previousCursor: "next").nextCursor == nil)
            #expect(throws: (any Error).self) { try parseXTimeline(.object([:])) }
        }
    }
}
