import Foundation
import Testing

@testable import Tidemeld

private let guestFeedJSON = #"""
{"ok":1,"data":{"cardlistInfo":{"since_id":8},"cards":[
 {"card_type":9,"mblog":{"id":"11","bid":"Ab11","user":{"id":1,"screen_name":"示例作者"},"text":"公开图片示例","pics":[{"pid":"picture","url":"https://example.com/small.gif","large":{"url":"https://example.com/large.gif","geo":{"width":1200,"height":800}}}]}},
 {"card_type":11,"card_group":[{"card_type":9,"is_ad":1,"mblog":{"id":"12","text":"推广内容示例","page_info":{"type":"video","object_type":11,"page_pic":{"url":"https://example.com/cover.jpg","width":"640","height":"360"},"media_info":{"duration":30,"stream_url":"https://example.com/low.mp4"},"urls":{"mp4_720p_mp4":"http://example.com/high.mp4"}}}}]}
 ]}}
"""#

extension FakeWeiboTests {
@MainActor @Suite
struct GuestTimelineTests {
    @Test func visitorFeedPreservesCardsAdsAndMobileMediaWithoutPrivateCookiesOrPaging() async throws {
        FakeWeibo.reset { request in
            .init(body: request.url?.path == "/api/config" ? #"{"ok":1,"data":{"login":false}}"# : guestFeedJSON)
        }
        let jar = WeiboCookieJar()
        var preparations = 0
        let api = GuestWeiboAPI(http: WeiboHTTP(jar: jar, throttle: RequestThrottle(minInterval: .zero), configuration: FakeWeibo.configuration)) {
            preparations += 1
            return [WeiboCookieJar.mobile: ["SUB": "visitor"], WeiboCookieJar.web: ["SUB": "must-not-use"]]
        }
        let page = try await api.fetchTimeline()
        #expect(page.items.map(\.id) == ["11", "12"])
        #expect(page.nextCursor == nil)
        #expect(page.items[0].mblogId == "Ab11")
        #expect(page.items[0].pics.first?.type == .gif)
        #expect(page.items[0].pics.first?.largest?.width == 1200)
        #expect(page.items[1].isAd)
        #expect(page.items[1].video?.streamURLs == ["https://example.com/high.mp4", "https://example.com/low.mp4"])
        #expect(page.items[1].video?.aspectRatio == 640.0 / 360)
        #expect(FakeWeibo.requests.count == 2)
        #expect(FakeWeibo.requests.allSatisfy { $0.url?.host == "m.weibo.cn" && $0.value(forHTTPHeaderField: "Cookie") == "SUB=visitor" })
        #expect(jar.value(WeiboCookieJar.web, "SUB") == nil)
        _ = try await api.fetchTimeline()
        #expect(preparations == 1)
        #expect(FakeWeibo.requests.count == 3)
    }

    @Test func anAccountCookieCannotBecomeAVisitorSession() async {
        FakeWeibo.reset { _ in .init(body: #"{"ok":1,"data":{"login":true}}"#) }
        let jar = WeiboCookieJar()
        let api = GuestWeiboAPI(http: WeiboHTTP(jar: jar, throttle: RequestThrottle(minInterval: .zero), configuration: FakeWeibo.configuration)) {
            [WeiboCookieJar.mobile: ["SUB": "account"]]
        }
        await #expect(throws: WeiboError.self) { try await api.fetchTimeline() }
        #expect(FakeWeibo.requests.map { $0.url?.path } == ["/api/config"])
        #expect(jar.toCookies().isEmpty)
    }

    @Test func guestActionsRequireLoginBeforeAnyWriteOrPrivateRead() {
        FakeWeibo.reset { _ in .init(body: #"{"ok":1}"#) }
        let graph = testGraph(restored: nil)
        let status = Status(id: "11")
        let actions = graph.guestStatusActions
        for action in [actions.onLike, actions.onOpen, actions.onExpand, actions.onRepost] {
            graph.router.showingLogin = false
            action?(status)
            #expect(graph.router.showingLogin)
        }
        #expect(FakeWeibo.requests.isEmpty)
        #expect(graph.session.state == .signedOut(expired: false))
    }
}
}
