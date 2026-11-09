import Foundation
import Testing

@testable import Tidemeld

private let profileFixture = #"""
    {"data":{"user":{"result":{"__typename":"User","rest_id":"42","core":{"name":"合成用户","screen_name":"fixture"},"avatar":{"image_url":"https://media.test/avatar.jpg"},"location":{"location":"合成地点"},"privacy":{"protected":true},"relationship_perspectives":{"following":true,"followed_by":true},"is_blue_verified":true,"legacy":{"description":"合成简介","friends_count":12,"followers_count":345,"statuses_count":2,"profile_banner_url":"https://media.test/cover.jpg"}}}}}
    """#

private func profileEntry(_ id: String, promoted: Bool = false) -> String {
    #"{"content":{"itemContent":{"tweet_results":{"result":{"rest_id":""# + id
        + #"","core":{"user_results":{"result":{"rest_id":"42","core":{"name":"合成用户","screen_name":"fixture"}}}},"legacy":{"full_text":"合成帖子"}}}"#
        + (promoted ? #", "promotedMetadata":{}"# : "") + "}}}"
}
private func profilePosts(_ ids: [String] = ["1"], cursor: String? = nil) -> String {
    let entries =
        ids.map { profileEntry($0) }
        + (cursor.map { [#"{"content":{"cursorType":"Bottom","value":""# + $0 + #""}}"#] } ?? [])
    return #"{"data":{"user":{"result":{"timeline_v2":{"timeline":{"instructions":[{"entries":["#
        + entries.joined(separator: ",") + #"]}]}}}}}}"#
}
private func profileAPI() -> XWebAPI {
    let names = ["UserByRestId", "UserByScreenName", "UserTweets"]
    return XWebAPI(
        spec: .object([
            "operations": .object(
                Dictionary(
                    uniqueKeysWithValues: names.map {
                        ($0, JSON.object(["queryId": .string("fixture")]))
                    }))
        ]), throttle: RequestThrottle(minInterval: .zero), configuration: FakeWeibo.configuration)
}
private func profileSession(_ id: String) -> StoredSession {
    StoredSession(
        account: Account(uid: id), cookies: ["x.com": ["auth_token": "synthetic-\(id)", "ct0": "csrf-\(id)"]])
}
private func profileVariables(_ request: URLRequest) -> JSON? {
    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
        $0.name == "variables"
    }?.value.flatMap(JSON.parse)
}

@Suite struct XProfileParsingTests {
    @Test func profileHandlesModernAndLegacyFieldsWithoutInventingCounts() throws {
        let p = try parseXProfile(#require(JSON.parse(profileFixture)))
        #expect(p.user.id == "42" && p.user.handle == "fixture")
        #expect(p.followers == 345 && p.following == 12 && p.posts == 2)
        #expect(p.followed && p.followsYou && p.protected && p.verified)
        #expect(p.location == "合成地点" && p.description == "合成简介")
        let minimal = try parseXProfile(
            #require(
                JSON.parse(
                    #"{"data":{"user":{"result":{"rest_id":"43","legacy":{"screen_name":"old","name":"旧结构"}}}}}"#
                )))
        #expect(minimal.user.name == "旧结构" && minimal.posts == nil)
        #expect(throws: WeiboError.self) {
            try parseXProfile(JSON.parse(#"{"data":{"user":{"result":{"__typename":"UserUnavailable"}}}}"#)!)
        }
        #expect(throws: WeiboError.self) {
            try parseXUserPosts(JSON.parse(#"{"data":{"user":{"result":{}}}}"#)!)
        }
    }

    @Test func pinsAdsAndCursorsKeepTheirMeaning() throws {
        let json =
            #"{"data":{"user":{"result":{"timeline":{"timeline":{"instructions":[{"type":"TimelinePinEntry","entry":"#
            + profileEntry("1") + #"},{"entries":["# + profileEntry("1") + ","
            + profileEntry("2", promoted: true)
            + #",{"content":{"cursorType":"Bottom","value":"next"}}]}]}}}}}}"#
        let page = try parseXUserPosts(#require(JSON.parse(json)))
        #expect(page.items.map(\.id) == ["1"])
        #expect(page.items[0].pinned && page.items[0].authorID == "42")
        #expect(page.nextCursor == "next")
        #expect(try parseXUserPosts(JSON.parse(json)!, previousCursor: "next").nextCursor == nil)
        let empty = try parseXUserPosts(JSON.parse(profilePosts([]))!)
        #expect(empty.items.isEmpty && empty.nextCursor == nil)
    }

    @Test func profileLinksExcludeApplicationRoutesAndOtherHosts() {
        #expect(xProfileHandle(URL(string: "https://twitter.com/Fixture/")!) == "Fixture")
        for url in [
            "https://x.com/home", "https://x.com/search?q=fixture", "https://x.com/fixture/status/1",
            "https://evil.test/fixture", "https://x.com/name-with-dash",
        ] {
            #expect(xProfileHandle(URL(string: url)!) == nil)
        }
    }
}

extension FakeWeiboTests {
    @MainActor @Suite struct XProfileTests {
        private func waitFor(_ predicate: () -> Bool) async throws {
            for _ in 0..<200 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(predicate())
        }

        @Test func namedProfileResolvesThenPagesWithSourceAccountAndRefreshKeepsData() async throws {
            FakeWeibo.reset { request in
                .init(
                    body: request.url!.lastPathComponent == "UserTweets"
                        ? profilePosts(
                            profileVariables(request)?["cursor"] == nil ? ["1"] : ["1", "2"], cursor: "next")
                        : profileFixture)
            }
            let graph = testGraph(xAPI: profileAPI())
            try graph.accounts.add(.x, session: profileSession("7"))
            try graph.accounts.add(.x, session: profileSession("8"))
            let model = XProfileModel(target: XProfileUser(handle: "fixture"))
            model.start(graph.xInteractions, owner: "x:8")
            model.start(graph.xInteractions, owner: "x:8")
            try await waitFor { model.posts?.state.list != nil }
            #expect(
                FakeWeibo.requests.filter { $0.url!.path.contains("/graphql/") }.map {
                    $0.url!.lastPathComponent
                } == ["UserByScreenName", "UserTweets"])
            #expect(profileVariables(FakeWeibo.requests[0])?["screen_name"]?.string == "fixture")
            #expect(
                profileVariables(FakeWeibo.requests.first { $0.url!.lastPathComponent == "UserTweets" }!)?[
                    "userId"]?.string == "42")
            try #require(model.posts?.items.count == 1)
            await model.posts?.loadMore()
            #expect(model.posts?.items.map(\.id) == ["1", "2"])
            #expect(model.posts?.state.list?.nextCursor == nil)
            #expect(
                FakeWeibo.requests.allSatisfy { $0.value(forHTTPHeaderField: "x-csrf-token") == "csrf-8" })
            let list = model.posts
            FakeWeibo.reset { _ in .init(status: 500) }
            await #expect(throws: (any Error).self) { try await model.refresh() }
            #expect(FakeWeibo.requests.contains { $0.url!.lastPathComponent == "UserByRestId" })
            #expect(!FakeWeibo.requests.contains { $0.url!.lastPathComponent == "UserByScreenName" })
            #expect(model.profile?.user.id == "42" && model.posts === list)
            #expect(model.posts?.items.map(\.id) == ["1", "2"])
        }

        @Test func failedHeaderRetriesWithoutReplacingTheSuccessfulList() async throws {
            FakeWeibo.reset { request in
                request.url!.lastPathComponent == "UserTweets"
                    ? .init(body: profilePosts()) : .init(status: 500)
            }
            let graph = testGraph(xAPI: profileAPI())
            try graph.accounts.add(.x, session: profileSession("7"))
            let model = XProfileModel(target: XProfileUser(id: "42", name: "初始名字"))
            model.start(graph.xInteractions, owner: "x:7")
            try await waitFor { model.error != nil && model.posts?.state.list != nil }
            let list = model.posts
            FakeWeibo.reset { _ in .init(body: profileFixture) }
            model.reload()
            try await waitFor { model.profile != nil }
            #expect(model.error == nil && model.posts === list)
            #expect(FakeWeibo.requests.filter { $0.url!.path.contains("/graphql/") }.count == 1)
            #expect(FakeWeibo.requests[0].url!.lastPathComponent == "UserByRestId")
        }

        @Test func profileRefreshFailureDoesNotCancelSuccessfulPosts() async throws {
            FakeWeibo.reset { request in
                .init(body: request.url!.lastPathComponent == "UserTweets" ? profilePosts() : profileFixture)
            }
            let graph = testGraph(xAPI: profileAPI())
            try graph.accounts.add(.x, session: profileSession("7"))
            let model = XProfileModel(target: XProfileUser(id: "42"))
            model.start(graph.xInteractions, owner: "x:7")
            try await waitFor { model.profile != nil && model.posts?.state.list != nil }
            FakeWeibo.reset { request in
                request.url!.lastPathComponent == "UserTweets"
                    ? .init(body: profilePosts(["2"]), delay: .milliseconds(50)) : .init(status: 500)
            }
            await #expect(throws: (any Error).self) { try await model.refresh() }
            #expect(model.profile?.user.id == "42")
            #expect(model.posts?.items.map(\.id) == ["2"])
        }

        @Test func reloginDiscardsOldProfileAndDoesNotExpireNewSession() async throws {
            FakeWeibo.reset { _ in .init(body: profileFixture, delay: .milliseconds(100)) }
            let graph = testGraph(xAPI: profileAPI())
            try graph.accounts.add(.x, session: profileSession("7"))
            let load = Task { try await graph.xInteractions.profile("x:7", user: XProfileUser(id: "42")) }
            try await waitFor { !FakeWeibo.requests.isEmpty }
            try graph.accounts.add(.x, session: profileSession("7"))
            await #expect(throws: WeiboError.sessionExpired) { try await load.value }
            #expect(graph.accounts.find("x:7")?.expired == false)
        }
    }
}
