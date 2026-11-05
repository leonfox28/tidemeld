import Foundation
import Testing

@testable import Tidemeld

private func xSession(_ id: String) -> StoredSession {
    StoredSession(
        account: Account(uid: id),
        cookies: ["x.com": ["auth_token": "synthetic-\(id)", "ct0": "csrf-\(id)"]])
}
private func xAPI(throttle: RequestThrottle = RequestThrottle(minInterval: .zero)) -> XWebAPI {
    let names = [
        "TweetDetail", "FavoriteTweet", "UnfavoriteTweet", "CreateRetweet", "DeleteRetweet",
        "CreateTweet",
    ]
    let operations = Dictionary(
        uniqueKeysWithValues: names.map { ($0, JSON.object(["queryId": .string("fixture-\($0)")])) }
    )
    return XWebAPI(
        spec: .object(["operations": .object(operations)]), throttle: throttle,
        configuration: FakeWeibo.configuration)
}
private func xPost() -> XPost {
    XPost(
        id: "wrapper", author: "作者", handle: "fixture", avatar: nil, text: "合成内容", createdAt: nil,
        pictures: [], videoCover: nil, videoURL: nil, quote: nil, originalID: "42",
        metrics: XMetrics(likes: 3, reposts: 2, replies: 1))
}
private func payload(_ request: URLRequest) -> JSON? {
    if let data = request.httpBody { return JSON.parse(data) }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return JSON.parse(data)
}

extension FakeWeiboTests {
    @MainActor @Suite struct XInteractionsTests {
        @Test func writesUseOriginalIDScopedCookiesAndExplicitAcknowledgements() async throws {
            FakeWeibo.reset { request in
                let response: String
                switch request.url?.lastPathComponent {
                case "FavoriteTweet": response = #"{"data":{"favorite_tweet":"Done"}}"#
                case "UnfavoriteTweet": response = #"{"data":{"unfavorite_tweet":"Done"}}"#
                case "CreateRetweet":
                    response =
                        #"{"data":{"create_retweet":{"retweet_results":{"result":{"rest_id":"99"}}}}}"#
                case "DeleteRetweet":
                    response =
                        #"{"data":{"unretweet":{"source_tweet_results":{"result":{"rest_id":"42"}}}}}"#
                default:
                    response =
                        #"{"data":{"create_tweet":{"tweet_results":{"result":{"rest_id":"100"}}}}}"#
                }
                return .init(body: response)
            }
            let api = xAPI()
            let post = xPost()
            try await api.like(xSession("7"), id: "42", liked: true)
            try await api.like(xSession("8"), id: "42", liked: false)
            try await api.repost(xSession("7"), id: "42", reposted: true)
            try await api.repost(xSession("7"), id: "42", reposted: false)
            #expect(try await api.publish(xSession("7"), post: post, text: " 回复 ") == "100")
            _ = try await api.publish(xSession("8"), post: post, text: "引用", quote: true)
            let requests = FakeWeibo.requests
            #expect(requests.count == 6)
            #expect(requests.allSatisfy { $0.httpMethod == "POST" && $0.url?.query == nil })
            #expect(requests[1].value(forHTTPHeaderField: "x-csrf-token") == "csrf-8")
            #expect(
                requests[1].value(forHTTPHeaderField: "Cookie")?.contains("synthetic-7") == false)
            #expect(payload(requests[3])?["variables"]?["source_tweet_id"]?.string == "42")
            let reply = payload(requests[4])?["variables"]
            #expect(reply?["tweet_text"]?.string == "回复")
            #expect(reply?["reply"]?["in_reply_to_tweet_id"]?.string == "42")
            #expect(reply?["attachment_url"] == nil)
            #expect(
                payload(requests[5])?["variables"]?["attachment_url"]?.string
                    == post.url.absoluteString)
            #expect(payload(requests[5])?["variables"]?["reply"] == nil)
        }

        @Test func unknownPartialAndServerErrorsNeverConfirmOrAutomaticallyRetry() async throws {
            for (body, status) in [
                ("{}", 500), ("not-json", 200),
                (#"{"data":{"favorite_tweet":"Done"},"errors":[{"code":226}]}"#, 200), ("{}", 200),
            ] {
                FakeWeibo.reset { _ in .init(status: status, body: body) }
                await #expect(throws: (any Error).self) {
                    try await xAPI().like(xSession("7"), id: "42", liked: true)
                }
                #expect(FakeWeibo.requests.count == 1)
            }
        }

        @Test func sourceAccountStateSurvivesStaleReadsAndFailedWrites() async throws {
            FakeWeibo.reset { _ in .init(body: #"{"data":{"favorite_tweet":"Done"}}"#) }
            let graph = testGraph()
            try graph.accounts.add(.x, session: xSession("7"))
            try graph.accounts.add(.x, session: xSession("8"))
            let store = XInteractions(accounts: graph.accounts, api: xAPI())
            let account = try #require(graph.accounts.find("x:7"))
            let post = xPost()
            let stamp = store.readStamp
            try await store.write("x:7", post: post, action: .like)
            #expect(store.state("x:7", post).metrics.likes == 4)
            #expect(store.state("x:7", post).metrics.liked)
            #expect(!store.state("x:8", post).metrics.liked)
            store.ingest(account, posts: [post], started: stamp)
            #expect(store.state("x:7", post).metrics.liked)
            FakeWeibo.reset { _ in .init(status: 500) }
            await #expect(throws: (any Error).self) {
                try await store.write("x:7", post: post, action: .like)
            }
            #expect(store.state("x:7", post).metrics.liked)
            #expect(!store.state("x:7", post).busy)
            store.ingest(account, posts: [post], started: store.readStamp)
            #expect(!store.state("x:7", post).metrics.liked)
        }

        @Test func duplicateIsBlockedAndLateResponseCannotAlterReloggedAccount() async throws {
            FakeWeibo.reset { _ in
                .init(body: #"{"data":{"favorite_tweet":"Done"}}"#, delay: .milliseconds(150))
            }
            let graph = testGraph()
            try graph.accounts.add(.x, session: xSession("7"))
            let store = XInteractions(accounts: graph.accounts, api: xAPI())
            let post = xPost()
            let pending = Task { try await store.write("x:7", post: post, action: .like) }
            for _ in 0..<200 where FakeWeibo.requests.isEmpty {
                try await Task.sleep(for: .milliseconds(1))
            }
            #expect(store.state("x:7", post).busy)
            await #expect(throws: (any Error).self) {
                try await store.write("x:7", post: post, action: .like)
            }
            try graph.accounts.add(.x, session: xSession("7"))
            await #expect(throws: (any Error).self) { try await pending.value }
            #expect(!store.state("x:7", post).metrics.liked)
            #expect(FakeWeibo.requests.count == 1)
        }

        @Test func queuedWriteChecksAccountBeforeSending() async throws {
            FakeWeibo.reset()
            let graph = testGraph()
            try graph.accounts.add(.x, session: xSession("7"))
            let throttle = RequestThrottle(maxConcurrent: 1, minInterval: .zero)
            await throttle.acquire()
            let store = XInteractions(accounts: graph.accounts, api: xAPI(throttle: throttle))
            let pending = Task { try await store.write("x:7", post: xPost(), action: .like) }
            for _ in 0..<100 where !store.state("x:7", xPost()).busy { await Task.yield() }
            try graph.accounts.add(.x, session: xSession("7"))
            await throttle.release()
            await #expect(throws: (any Error).self) { try await pending.value }
            #expect(FakeWeibo.requests.isEmpty)
        }

        @Test func authFailureExpiresOnlyTheSourceAccount() async throws {
            FakeWeibo.reset { _ in .init(status: 401) }
            let graph = testGraph()
            try graph.accounts.add(.x, session: xSession("7"))
            try graph.accounts.add(.x, session: xSession("8"))
            let store = XInteractions(accounts: graph.accounts, api: xAPI())
            await #expect(throws: WeiboError.sessionExpired) {
                try await store.write("x:7", post: xPost(), action: .like)
            }
            #expect(graph.accounts.find("x:7")?.expired == true)
            #expect(graph.accounts.find("x:8")?.expired == false)
        }

        @Test func conversationKeepsRepliesButExcludesAdsAndAncestors() throws {
            func entry(_ id: String, parent: String? = nil, ad: Bool = false) -> JSON {
                var legacy: [String: JSON] = [
                    "full_text": .string("合成内容"), "favorite_count": .int(12),
                    "retweet_count": .int(2),
                    "reply_count": .int(3), "favorited": .bool(true), "retweeted": .bool(true),
                ]
                if let parent { legacy["in_reply_to_status_id_str"] = .string(parent) }
                let post = JSON.object([
                    "rest_id": .string(id),
                    "core": .object([
                        "user_results": .object([
                            "result": .object([
                                "core": .object([
                                    "name": .string("作者"), "screen_name": .string("fixture"),
                                ])
                            ])
                        ])
                    ]), "legacy": .object(legacy),
                ])
                var item: [String: JSON] = ["tweet_results": .object(["result": post])]
                if ad { item["promotedMetadata"] = .object([:]) }
                return .object(["content": .object(["itemContent": .object(item)])])
            }
            let entries: [JSON] = [
                entry("ancestor"), entry("42", parent: "ancestor"),
                entry("nested", parent: "reply"),
                entry("reply", parent: "42"), entry("ad", ad: true),
                entry("promoted-reply", parent: "42", ad: true),
                .object([
                    "content": .object(["cursorType": .string("Bottom"), "value": .string("next")])
                ]),
            ]
            let json = JSON.object([
                "data": .object([
                    "threaded_conversation_with_injections_v2": .object([
                        "instructions": .array([.object(["entries": .array(entries)])])
                    ])
                ])
            ])
            let page = try parseXConversation(json, focalID: "42")
            #expect(page.replies.items.map(\.id) == ["nested", "reply"])
            #expect(
                page.post?.metrics
                    == XMetrics(likes: 12, reposts: 2, replies: 3, liked: true, reposted: true))
            #expect(page.replies.nextCursor == "next")
            #expect(
                try parseXConversation(json, focalID: "42", previousCursor: "next").replies
                    .nextCursor
                    == nil)
        }
    }
}
