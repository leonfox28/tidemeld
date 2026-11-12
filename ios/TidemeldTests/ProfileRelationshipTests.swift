import Foundation
import Testing

@testable import Tidemeld

private func relationshipJSON(
    following: Bool = true, blocking: Bool = false, reposts: Bool = true, requested: Bool = false
) -> String {
    """
    {"relationship":{"source":{"id_str":"8","following":\(following),"followed_by":false,"following_requested":\(requested),"blocking":\(blocking),"want_retweets":\(reposts)},"target":{"id_str":"42"}}}
    """
}
private func relationSession() -> StoredSession {
    StoredSession(
        account: Account(uid: "8"), cookies: ["x.com": ["auth_token": "synthetic-8", "ct0": "csrf-8"]])
}
private func relationAPI(_ throttle: RequestThrottle = RequestThrottle(minInterval: .zero)) -> XWebAPI {
    XWebAPI(spec: .object([:]), throttle: throttle, configuration: FakeWeibo.configuration)
}
private func relationForm(_ request: URLRequest) -> [String: String] {
    var data = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let size = stream.read(&buffer, maxLength: buffer.count)
            if size <= 0 { break }
            data.append(contentsOf: buffer.prefix(size))
        }
    }
    return Dictionary(
        uniqueKeysWithValues: String(decoding: data, as: UTF8.self).split(separator: "&").compactMap {
            field in
            let parts = field.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            return (parts[0], parts[1].removingPercentEncoding ?? parts[1])
        })
}

extension FakeWeiboTests {
    @MainActor @Suite struct ProfileRelationshipTests {
        @Test func confirmedBlocksPersistAndUnblocksRestoreContentOnlyForSourceAccount() async throws {
            FakeWeibo.reset { _ in .init(body: relationshipJSON(blocking: false)) }
            let graph = testGraph(xAPI: relationAPI())
            try graph.accounts.add(.x, session: relationSession())
            let store = graph.xInteractions
            let user = XProfileUser(id: "42", name: "合成用户")
            try await store.refreshRelationship("x:8", uid: "42")
            for blocked in [true, false] {
                FakeWeibo.reset { request in
                    .init(body: request.httpMethod == "POST" ? #"{"id_str":"42"}"# : relationshipJSON(blocking: blocked))
                }
                let action = try #require(store.relationshipActions("x:8", user: user, failed: false)?.more.first { $0.id == "block" })
                try await action.perform()
                #expect(ContentBlock.hides(["42"], owner: "x:8", blocked: graph.settings.settings.blockedUsers) == blocked)
                #expect(!ContentBlock.hides(["42"], owner: "x:9", blocked: graph.settings.settings.blockedUsers))
                #expect(!ContentBlock.hides(["42"], owner: "weibo:8", blocked: graph.settings.settings.blockedUsers))
            }
            FakeWeibo.reset { request in .init(body: request.httpMethod == "POST" ? "{}" : relationshipJSON()) }
            let rejected = try #require(store.relationshipActions("x:8", user: user, failed: false)?.more.first { $0.id == "block" })
            await #expect(throws: (any Error).self) { try await rejected.perform() }
            #expect(graph.settings.settings.blockedUsers.isEmpty)
        }

        @Test func weiboConfirmedBlocksUpdateLocalVisibilityAndStaleActionsDoNotWrite() async throws {
            FakeWeibo.reset { _ in .init(body: #"{"ok":1,"data":{"block":false,"user":{"idstr":"42","screen_name":"合成用户","following":false}}}"#) }
            let graph = testGraph(configuration: FakeWeibo.configuration)
            let controls = WeiboProfileControls(graph)
            let profile = try await graph.api.fetchProfile(uid: "42")
            controls.ingest(profile, started: controls.readStamp)
            for blocked in [true, false] {
                FakeWeibo.reset { request in
                    .init(body: request.httpMethod == "POST" ? #"{"ok":1}"# : """
                        {"ok":1,"data":{"block":\(blocked),"user":{"idstr":"42","screen_name":"合成用户","following":false}}}
                        """)
                }
                let action = try #require(controls.actions(profile)?.more.first { $0.id == "block" })
                try await action.perform()
                #expect(ContentBlock.hides(["42"], owner: "weibo:7", blocked: graph.settings.settings.blockedUsers) == blocked)
                #expect(!ContentBlock.hides(["42"], owner: "weibo:8", blocked: graph.settings.settings.blockedUsers))
            }
            let stale = try #require(controls.actions(profile)?.more.first { $0.id == "block" })
            try graph.accounts.add(.weibo, session: signedIn)
            FakeWeibo.reset()
            await #expect(throws: (any Error).self) { try await stale.perform() }
            #expect(FakeWeibo.requests.isEmpty)
            #expect(graph.settings.settings.blockedUsers.isEmpty)
        }

        @Test func xFormsVerifyTargetAccountAndAcknowledgedState() async throws {
            let cases: [(XUserAction, String, [String: String], String)] = [
                (
                    .follow(true), "friendships/create", ["user_id": "42"],
                    relationshipJSON(following: false, requested: true)
                ),
                (
                    .follow(false), "friendships/destroy", ["user_id": "42"],
                    relationshipJSON(following: false)
                ),
                (
                    .block(true), "blocks/create", ["user_id": "42"],
                    relationshipJSON(following: false, blocking: true)
                ),
                (.block(false), "blocks/destroy", ["user_id": "42"], relationshipJSON(following: false)),
                (
                    .reposts(false), "friendships/update", ["user_id": "42", "retweets": "false"],
                    relationshipJSON(reposts: false)
                ),
                (
                    .reposts(true), "friendships/update", ["user_id": "42", "retweets": "true"],
                    relationshipJSON()
                ),
            ]
            for (action, endpoint, fields, response) in cases {
                FakeWeibo.reset { request in
                    .init(body: request.httpMethod == "POST" ? #"{"id_str":"42"}"# : response)
                }
                let result = try await relationAPI().changeRelationship(
                    relationSession(), uid: "42", action: action)
                if case .follow(true) = action { #expect(result.requested && !result.following) }
                #expect(FakeWeibo.requests.count == 2)
                let write = try #require(FakeWeibo.requests.first)
                #expect(write.url?.path == "/1.1/\(endpoint).json")
                #expect(write.httpMethod == "POST" && relationForm(write) == fields)
                #expect(
                    write.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
                #expect(
                    FakeWeibo.requests.allSatisfy { $0.value(forHTTPHeaderField: "x-csrf-token") == "csrf-8" }
                )
                let query = URLComponents(url: FakeWeibo.requests[1].url!, resolvingAgainstBaseURL: false)!
                    .queryItems!
                #expect(query.contains(URLQueryItem(name: "source_id", value: "8")))
                #expect(query.contains(URLQueryItem(name: "target_id", value: "42")))
            }
        }

        @Test func unconfirmedWritesRequireRefreshAndOldAccountCallbacksDoNotSend() async throws {
            FakeWeibo.reset { request in .init(body: request.httpMethod == "POST" ? "{}" : relationshipJSON())
            }
            let graph = testGraph(xAPI: relationAPI())
            try graph.accounts.add(.x, session: relationSession())
            let store = graph.xInteractions
            try await store.refreshRelationship("x:8", uid: "42")
            let user = XProfileUser(id: "42", name: "合成用户")
            let action = try #require(store.relationshipActions("x:8", user: user, failed: false)?.primary)
            await #expect(throws: (any Error).self) { try await action.perform() }
            let refresh = try #require(store.relationshipActions("x:8", user: user, failed: false)?.primary)
            #expect(refresh.title == "刷新状态")
            await #expect(throws: (any Error).self) { try await action.perform() }
            #expect(FakeWeibo.requests.filter { $0.httpMethod == "POST" }.count == 1)
            try await refresh.perform()
            let stale = try #require(store.relationshipActions("x:8", user: user, failed: false)?.primary)
            try graph.accounts.add(.x, session: relationSession())
            await #expect(throws: (any Error).self) { try await stale.perform() }
            #expect(FakeWeibo.requests.filter { $0.httpMethod == "POST" }.count == 1)
            #expect(store.relationshipActions("x:8", user: XProfileUser(id: "8"), failed: false) == nil)
        }

        @Test func queuedRelationshipWriteChecksAccountBeforeSending() async throws {
            FakeWeibo.reset()
            let graph = testGraph()
            try graph.accounts.add(.x, session: relationSession())
            let throttle = RequestThrottle(maxConcurrent: 1, minInterval: .zero)
            let store = XInteractions(accounts: graph.accounts, api: relationAPI(throttle))
            let key = store.key("x:8", "42")
            store.relationships.ingest(
                key, value: ProfileRelationship(following: false, blocking: false), started: 0)
            let action = try #require(
                store.relationshipActions("x:8", user: XProfileUser(id: "42"), failed: false)?.primary)
            await throttle.acquire()
            let pending = Task { try await action.perform() }
            for _ in 0..<100 where store.relationships.loadedState(key)?.busy != true { await Task.yield() }
            try graph.accounts.add(.x, session: relationSession())
            await throttle.release()
            await #expect(throws: (any Error).self) { try await pending.value }
            #expect(FakeWeibo.requests.isEmpty)
        }

        @Test func weiboFormsAndBlockStateMatchWebClient() async throws {
            let cases: [(Bool?, Bool?, String, [String: String], Bool, Bool)] = [
                (true, nil, "friendships/create", ["friend_uid": "42"], true, false),
                (false, nil, "friendships/destory", ["uid": "42"], false, false),
                (
                    nil, true, "statuses/filterUser",
                    ["uid": "42", "status": "1", "interact": "1", "follow": "1"], false, true
                ),
                (nil, false, "statuses/deleteFilters", ["uid": "42"], false, false),
            ]
            for (follow, block, endpoint, fields, following, blocking) in cases {
                FakeWeibo.reset { request in
                    .init(
                        body: request.httpMethod == "POST"
                            ? #"{"ok":1}"#
                            : """
                            {"ok":1,"data":{"block":\(blocking),"user":{"idstr":"42","screen_name":"合成用户","following":\(following)}}}
                            """)
                }
                let graph = testGraph(configuration: FakeWeibo.configuration)
                let result = try await graph.api.changeUserRelationship(
                    uid: "42", following: follow, blocking: block)
                #expect(result.following == following && result.blocking == blocking)
                let write = try #require(FakeWeibo.requests.first)
                #expect(write.url?.path == "/ajax/\(endpoint)" && relationForm(write) == fields)
                await #expect(throws: (any Error).self) {
                    _ = try await graph.api.changeUserRelationship(
                        uid: "42", following: true, isCurrent: { false })
                }
                #expect(FakeWeibo.requests.filter { $0.httpMethod == "POST" }.count == 1)
            }
        }

        @Test func sharedStoreRejectsLateReadsAndDuplicateTaps() async throws {
            let store = ProfileRelationships()
            let before = ProfileRelationship(following: false, blocking: false)
            let after = ProfileRelationship(following: true, blocking: false)
            store.ingest("x:8:1:42", value: before, started: 0)
            let started = store.readStamp
            var sends = 0
            let pending = Task {
                try await store.perform("x:8:1:42", expected: before, isCurrent: { true }) {
                    sends += 1
                    try await Task.sleep(for: .milliseconds(50))
                    return after
                }
            }
            for _ in 0..<100 where store.loadedState("x:8:1:42")?.busy != true { await Task.yield() }
            try await store.perform("x:8:1:42", expected: before, isCurrent: { true }) {
                sends += 1
                return before
            }
            store.ingest("x:8:1:42", value: before, started: started)
            try await pending.value
            store.ingest("x:8:1:42", value: before, started: started)
            #expect(store.loadedState("x:8:1:42")?.value == after && sends == 1)
            #expect(store.loadedState("x:9:1:42") == nil)
        }

        @Test func sharedMenuRequiresConfirmationAndOnlyOffersSupportedActions() {
            let state = ProfileRelationshipState(
                value: ProfileRelationship(following: true, blocking: false, showsReposts: true))
            let actions = profileActions(
                name: "合成用户", state: state, follow: { _ in }, block: { _ in }, reposts: { _ in }, refresh: {})
            #expect(actions.primary?.title == "取消关注")
            #expect(actions.primary?.confirmation != nil)
            #expect(actions.more.first { $0.id == "block" }?.confirmation != nil)
            #expect(actions.more.first { $0.id == "reposts" }?.title == "关闭转帖")
            let blocked = profileActions(
                name: "合成用户",
                state: ProfileRelationshipState(value: ProfileRelationship(following: false, blocking: true)),
                follow: { _ in }, block: { _ in }, reposts: nil, refresh: {})
            #expect(blocked.primary == nil && blocked.more.map(\.title) == ["取消拉黑"])
        }
    }
}
