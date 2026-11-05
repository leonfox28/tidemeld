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
        @Test func nativeVideoRefreshUsesOriginalPostSourceAccountAndVideoIndex() async throws {
            FakeWeibo.reset { _ in
                .init(
                    body: #"""
                        {"data":{"threaded_conversation_with_injections_v2":{"instructions":[{"entries":[{"content":{"itemContent":{"tweet_results":{"result":{
                          "rest_id":"42","core":{"user_results":{"result":{"core":{"screen_name":"fixture"}}}},
                          "legacy":{"full_text":"合成内容","extended_entities":{"media":[
                            {"type":"video","video_info":{"variants":[{"content_type":"video/mp4","url":"https://media.test/first.mp4"}]}},
                            {"type":"animated_gif","video_info":{"variants":[{"content_type":"video/mp4","url":"https://media.test/second.mp4"}]}}
                          ]}}
                        }}}}}]}]}}}
                        """#)
            }
            let graph = testGraph(xAPI: xAPI())
            try graph.accounts.add(.x, session: xSession("7"))
            try graph.accounts.add(.x, session: xSession("8"))
            let request = graph.xVideoRequest(
                owner: "x:7", postID: "42", index: 1,
                known: VideoInfo(coverURL: "https://media.test/cover.jpg", streamURLs: ["https://media.test/old.mp4"]))
            #expect(try await request.resolve(false) == VideoSource(url: "https://media.test/old.mp4", fetched: false))
            #expect(FakeWeibo.requests.isEmpty)
            #expect(try await request.resolve(true) == VideoSource(url: "https://media.test/second.mp4", fetched: true))
            #expect(request.headers["Referer"] == "https://x.com/")
            #expect(request.headers["Cookie"] == nil)
            let sent = try #require(FakeWeibo.requests.first)
            #expect(sent.value(forHTTPHeaderField: "x-csrf-token") == "csrf-7")
            let variables = URLComponents(url: sent.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
                $0.name == "variables"
            }?.value
            #expect(variables.flatMap(JSON.parse)?["focalTweetId"]?.string == "42")
            try graph.accounts.add(.x, session: xSession("7"))
            await #expect(throws: WeiboError.sessionExpired) { _ = try await request.resolve(true) }
            #expect(FakeWeibo.requests.count == 1)
        }

        @Test func mediaAdapterKeepsOrderMultipleVideosDimensionsAndMP4Variants() throws {
            let entries = try #require(
                JSON.parse(
                    #"""
                    [
                      {"type":"photo","id_str":"photo","media_url_https":"https://media.test/photo.jpg","original_info":{"width":600,"height":1800}},
                      {"type":"video","video_info":{"duration_millis":12500,"aspect_ratio":[16,9],"variants":[
                        {"content_type":"application/x-mpegURL","url":"https://media.test/hls.m3u8"},
                        {"content_type":"video/mp4","bitrate":10,"url":"https://media.test/low.mp4"},
                        {"content_type":"video/mp4","bitrate":20,"url":"https://media.test/high.mp4"}]}},
                      {"type":"animated_gif","video_info":{"variants":[{"content_type":"video/mp4","url":"https://media.test/gif.mp4"}]}}
                    ]
                    """#)?.array)
            let media = parseXMedia(entries)
            #expect(media.count == 3)
            guard case .pic(let photo) = media[0], case .video(let video) = media[1], case .video(let gif) = media[2]
            else {
                Issue.record("Attachment order changed")
                return
            }
            #expect(photo.aspectRatio == 1.0 / 3)
            #expect(video.duration == 12)
            #expect(video.aspectRatio == 16.0 / 9)
            #expect(video.streamURLs == ["https://media.test/high.mp4", "https://media.test/low.mp4"])
            #expect(gif.streamURLs == ["https://media.test/gif.mp4"])
        }

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

        @Test func detailPaginationPreservesContextAndRefreshReplacesIt() async throws {
            func payload(_ entries: [(String, String?, String)], cursor: String? = nil) -> String {
                var rows: [JSON] = entries.map { id, parent, body in
                    var legacy: [String: JSON] = ["full_text": .string(body)]
                    if let parent { legacy["in_reply_to_status_id_str"] = .string(parent) }
                    return .object([
                        "content": .object([
                            "itemContent": .object([
                                "tweet_results": .object([
                                    "result": .object([
                                        "rest_id": .string(id), "legacy": .object(legacy),
                                        "core": .object([
                                            "user_results": .object([
                                                "result": .object(["core": .object(["screen_name": .string("fixture")])]
                                                )
                                            ])
                                        ]),
                                    ])
                                ])
                            ])
                        ])
                    ])
                }
                if let cursor {
                    rows.append(
                        .object(["content": .object(["cursorType": .string("Bottom"), "value": .string(cursor)])]))
                }
                return JSON.object([
                    "data": .object([
                        "threaded_conversation_with_injections_v2": .object([
                            "instructions": .array([.object(["entries": .array(rows)])])
                        ])
                    ])
                ]).text
            }
            let first = payload([("7", nil, "合成上文"), ("42", "7", "当前回复")], cursor: "next")
            let more = payload([("43", "42", "下级回复")])
            FakeWeibo.reset { request in
                let query =
                    URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first {
                        $0.name == "variables"
                    }?.value ?? "{}"
                return .init(body: JSON.parse(query)?["cursor"]?.string == nil ? first : more)
            }
            let graph = testGraph(xAPI: xAPI())
            try graph.accounts.add(.x, session: xSession("7"))
            var initial = xPost()
            initial.repostedBy = "合成转发者"
            let model = XDetailModel(initial: initial)
            model.start(graph.xInteractions, owner: "x:7", id: "42")
            let list = try #require(model.replies)
            for _ in 0..<200 {
                if case .ready = list.state { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(model.ancestors.map(\.originalID) == ["7"])
            #expect(model.post?.repostedBy == "合成转发者")
            try #require(list.state.list?.hasMore == true)
            await list.loadMore()
            #expect(model.ancestors.map(\.originalID) == ["7"])
            #expect(model.post?.text == "当前回复")
            #expect(list.items.map(\.originalID) == ["43"])
            #expect(FakeWeibo.requests.count == 2)
            let refreshed = payload([("42", "missing", "更新后的回复")])
            FakeWeibo.reset { _ in .init(body: refreshed) }
            try await list.refresh()
            #expect(model.ancestors.isEmpty)
            #expect(model.post?.text == "更新后的回复")
            #expect(model.post?.repostedBy == "合成转发者")
        }

        @Test func conversationSeparatesRepliesAncestorsAndAds() throws {
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
            #expect(page.ancestors.map(\.originalID) == ["ancestor"])
            func parsed(_ entries: [JSON]) throws -> XConversation {
                try parseXConversation(
                    .object([
                        "data": .object([
                            "threaded_conversation_with_injections_v2": .object([
                                "instructions": .array([.object(["entries": .array(entries)])])
                            ])
                        ])
                    ]), focalID: "42")
            }
            let ordered = try parsed([
                entry("middle", parent: "root"), entry("42", parent: "parent"),
                entry("outside"), entry("root"), entry("parent", parent: "middle"),
            ])
            #expect(ordered.ancestors.map(\.originalID) == ["root", "middle", "parent"])
            #expect(ordered.replies.items.isEmpty)
            #expect(
                try parsed([entry("42", parent: "parent"), entry("parent", parent: "missing")]).ancestors.map(
                    \.originalID) == ["parent"])
            #expect(try parsed([entry("42", parent: "parent"), entry("parent", ad: true)]).ancestors.isEmpty)
            let cycle = try parsed([
                entry("42", parent: "parent"), entry("parent", parent: "42"), entry("reply", parent: "42"),
            ])
            #expect(cycle.ancestors.map(\.originalID) == ["parent"])
            #expect(cycle.replies.items.map(\.originalID) == ["reply"])

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
