import Foundation
import Testing

@testable import Tidemeld

extension FakeWeiboTests {
    @MainActor @Suite struct WeiboVideoLinkTests {
        nonisolated private static let response = #"""
            {"code":"100000","data":{"Component_Play_Playinfo":{
              "oid":"1034:5000000000000001","object_type":"video","duration_time":61.5,
              "cover_image":"https://wx1.sinaimg.cn/cover.jpg",
              "urls":{"标清 480P":"https://media.test/480.mp4","高清 720P":"http://media.test/720.mp4?Expires=2100000000&ssig=a%2Bb"},
              "stream_url":"https://media.test/fallback.mp4"}}}
            """#

        @Test func tappingTextOpensTheSharedPlayerAndResolvesWithItsSourceAccount() async throws {
            FakeWeibo.reset { _ in .init(body: Self.response) }
            let graph = testGraph(configuration: FakeWeibo.configuration)
            try graph.accounts.add(.weibo, session: StoredSession(
                account: Account(uid: "8", screenName: "来源账号"), cookies: ["weibo.com": ["SUB": "synthetic-8"]]))
            let owner = try #require(graph.forAccount("weibo:8"))
            let segments = parseStatusText("<a href=\"https://h5.video.weibo.com/show/1034:5000000000000001\">示例用户的微博视频</a>")
            guard case .link(_, let link, _) = segments.first else { Issue.record("Missing link"); return }
            #expect(FakeWeibo.requests.isEmpty)
            owner.statusActions.onLink?(link)
            let request = try #require(graph.router.video)
            #expect(FakeWeibo.requests.isEmpty)
            #expect(request.headers["Referer"] == "https://weibo.com/")
            let source = try await request.resolve(false)
            #expect(source == VideoSource(url: "https://media.test/720.mp4?Expires=2100000000&ssig=a%2Bb", fetched: true))
            let sent = try #require(FakeWeibo.requests.first)
            #expect(sent.httpMethod == "POST")
            #expect(sent.url?.host == "h5.video.weibo.com")
            #expect(sent.url?.path == "/api/component")
            #expect(URLComponents(url: sent.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "/show/1034:5000000000000001")
            #expect(sent.value(forHTTPHeaderField: "Cookie") == "SUB=synthetic-8")
            // Retrying asks for this same object again, without loading the enclosing repost.
            _ = try await request.resolve(true)
            #expect(FakeWeibo.requests.count == 2)
            #expect(FakeWeibo.requests.allSatisfy { $0.url == sent.url })
        }

        @Test func readsStreamFallbackAndVideoMetadata() async throws {
            FakeWeibo.reset { _ in .init(body: Self.response) }
            let api = testGraph(configuration: FakeWeibo.configuration).api
            let link = WeiboVideoLink(objectID: "1034:5000000000000001")
            let video = try await api.fetchLinkedVideo(link)
            #expect(video.duration == 61)
            #expect(video.coverURL == "https://wx1.sinaimg.cn/cover.jpg")
            #expect(video.streamURLs.count == 3)
            FakeWeibo.reset { _ in .init(body: #"{"code":"100000","data":{"Component_Play_Playinfo":{"oid":"1034:5000000000000001","object_type":"video","stream_url":"//media.test/fallback.mp4"}}}"#) }
            #expect(try await api.fetchLinkedVideo(link).streamURLs == ["https://media.test/fallback.mp4"])
        }

        @Test(arguments: [
            #"{"code":"failed"}"#,
            #"{"code":"100000","data":{"Component_Play_Playinfo":{}}}"#,
            #"{"code":"100000","data":{"Component_Play_Playinfo":{"oid":"1034:5000000000000001","object_type":"video"}}}"#,
        ])
        func missingAndRejectedVideosFailWithoutExtraRequests(_ response: String) async throws {
            FakeWeibo.reset { _ in .init(body: response) }
            let api = testGraph(configuration: FakeWeibo.configuration).api
            await #expect(throws: WeiboError.self) { try await api.fetchLinkedVideo(WeiboVideoLink(objectID: "1034:5000000000000001")) }
            #expect(FakeWeibo.requests.count == 1)
        }

        @Test func mismatchedObjectsCannotPlayADifferentVideo() async throws {
            FakeWeibo.reset { _ in .init(body: Self.response) }
            let api = testGraph(configuration: FakeWeibo.configuration).api
            await #expect(throws: WeiboError.self) { try await api.fetchLinkedVideo(WeiboVideoLink(objectID: "1034:5000000000000002")) }
        }
    }
}
