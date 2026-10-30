import Foundation
import Testing

@testable import Maxbo

private func reply(_ body: String?, status: Int = 200, url: String = "https://weibo.com/ajax/x") -> (HTTPReply, JSON?) {
    let reply = HTTPReply(
        status: status, url: URL(string: url)!, contentType: body == nil ? "text/html" : "application/json",
        body: Data((body ?? "<html>").utf8))
    return (reply, reply.json)
}

private func unwrap(_ r: (HTTPReply, JSON?)) -> Result<JSON, WeiboError> {
    Result { try unwrapResponse(r.0, json: r.1) }.mapError { $0 as! WeiboError }
}

struct WeiboErrorTests {
    @Test func returnsTheJSONObjectOnSuccess() throws {
        #expect(try unwrap(reply(#"{"ok":1,"data":{"x":1}}"#)).get()["ok"] == .int(1))
        // Some endpoints carry no "ok" field at all.
        #expect(try unwrap(reply(#"{"statuses":[]}"#)).get().has("statuses"))
    }

    @Test func okMinus100MeansSignedOutOrACaptcha() {
        #expect(unwrap(reply(#"{"ok":-100,"url":"https://weibo.com/login.php"}"#)) == .failure(.sessionExpired))
        guard case .failure(.captchaRequired(let url)) = unwrap(reply(#"{"ok":-100,"url":"https://m.weibo.cn/captcha?x=1"}"#))
        else { Issue.record("no captcha"); return }
        #expect(url.path == "/captcha")
    }

    @Test func aRedirectToALoginHost401Or403AskingToLogIn() {
        #expect(unwrap(reply(nil, url: "https://passport.weibo.com/sso/signin")) == .failure(.sessionExpired))
        #expect(unwrap(reply(#"{"ok":0}"#, status: 401)) == .failure(.sessionExpired))
        #expect(unwrap(reply(#"{"ok":0,"message":"前方有点拥堵，请登录后使用"}"#, status: 403)) == .failure(.sessionExpired))
    }

    @Test func rateLimitStatuses() {
        for status in [418, 429, 432] {
            #expect(unwrap(reply(nil, status: status)) == .failure(.rateLimited(status: status)))
        }
    }

    @Test func apiErrorsKeepWeibosMessage() {
        #expect(unwrap(reply(#"{"ok":0,"msg":"内容不存在"}"#)) == .failure(.api("内容不存在", status: 200)))
        #expect(unwrap(reply(#"{"ok":0}"#, status: 500)) == .failure(.api("请求失败（500）", status: 500)))
        #expect(unwrap(reply(#"{"ok":0,"message":null,"msg":"内容不存在"}"#)) == .failure(.api("内容不存在", status: 200)))
        #expect(unwrap(reply(nil)) == .failure(.api("微博返回了无法识别的内容", status: 200)))
    }
}

struct CookieJarTests {
    @Test func keepsCookiesPerSiteAndSendsThemOnlyThere() {
        let jar = WeiboCookieJar(["weibo.com": ["SUB": "s"], "weibo.cn": ["M": "m"], "evil.com": ["X": "x"]])
        #expect(jar.header(for: URL(string: "https://passport.weibo.com/a")!) == "SUB=s")
        #expect(jar.header(for: URL(string: "https://m.weibo.cn/api")!) == "M=m")
        #expect(jar.header(for: URL(string: "https://notweibo.com/")!) == nil)
        #expect(jar.toCookies().keys.sorted() == ["weibo.cn", "weibo.com"])
    }

    @Test func appliesSetCookieAndExpiryAndTellsListeners() {
        let jar = WeiboCookieJar(["weibo.com": ["XSRF-TOKEN": "old", "GONE": "1"]])
        nonisolated(unsafe) var changes = 0
        jar.addListener { changes += 1 }
        let response = HTTPURLResponse(
            url: URL(string: "https://weibo.com/ajax/x")!, statusCode: 200, httpVersion: nil,
            headerFields: ["Set-Cookie": "XSRF-TOKEN=new; Path=/; Domain=.weibo.com, GONE=; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Domain=.weibo.com"])!
        jar.apply(response)
        #expect(jar.value("weibo.com", "XSRF-TOKEN") == "new")
        #expect(jar.value("weibo.com", "GONE") == nil)
        #expect(changes == 1)
        // A host can't set cookies for another site.
        jar.apply(URL(string: "https://weibo.com/")!, HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": "A=1; Domain=.sina.com.cn"], for: URL(string: "https://weibo.com/")!))
        #expect(jar.value("weibo.com", "A") == nil)
    }

    @Test func readsTheCookiesABrowserWouldSend() {
        let cookies = [
            HTTPCookie(properties: [.domain: ".weibo.com", .path: "/", .name: "SUB", .value: "s"])!,
            HTTPCookie(properties: [.domain: "passport.weibo.com", .path: "/", .name: "ALC", .value: "a"])!,
            HTTPCookie(properties: [.domain: "weibo.com", .path: "/ajax", .name: "P", .value: "p"])!,
            HTTPCookie(properties: [
                .domain: ".weibo.com", .path: "/", .name: "OLD", .value: "o", .expires: Date(timeIntervalSince1970: 0),
            ])!,
        ]
        #expect(cookiesSent(to: URL(string: "https://weibo.com/")!, from: cookies) == ["SUB": "s"])
        #expect(cookiesSent(to: URL(string: "https://passport.weibo.com/x")!, from: cookies) == ["SUB": "s", "ALC": "a"])
    }

    @Test func encodesQueriesAndFormsAsABrowserDoes() {
        #expect(
            URL.with("https://weibo.com/ajax/x", query: [("q", "#话题# a&b+c"), ("n", 1), ("skip", nil)]).absoluteString
                == "https://weibo.com/ajax/x?q=%23%E8%AF%9D%E9%A2%98%23%20a%26b%2Bc&n=1")
        #expect(String(decoding: formBody([("comment", "好 =1"), ("pic_id", nil)]), as: UTF8.self) == "comment=%E5%A5%BD%20%3D1")
    }
}

struct PageTests {
    @Test func extractsThePageConfig() {
        let html = #"<script>window.$CONFIG = {"uid":"7","user":{"screen_name":"a}b\"c"}};</script>"#
        let config = extractPageConfig(html)
        #expect(config.flatMap { Account.from(pageConfig: $0) } == Account(uid: "7", screenName: "a}b\"c"))
        #expect(extractPageConfig("<html>no config</html>") == nil)
        #expect(extractPageConfig(#"window.$CONFIG = {"uid":"0"}"#).flatMap { Account.from(pageConfig: $0) } == nil)
    }

    @Test func readsTheUploadedPid() {
        #expect(parseUploadedPid(#"<script>x</script>{"code":"A00006","data":{"pics":{"pic_1":{"pid":"abc"}}}}"#) == "abc")
        #expect(parseUploadedPid(#"{"ret":true,"pic":{"pid":"new"}}"#) == "new")
        #expect(parseUploadedPid(#"{"code":"A20001","data":{"count":-10}}"#) == nil)
    }

    @Test func dropsSignaturesFromCacheKeys() {
        #expect(imageCacheKey("http://tva1.sinaimg.cn/a.jpg?KID=imgbed&Expires=1&ssig=x&w=1") == "https://tva1.sinaimg.cn/a.jpg?w=1")
        #expect(imageCacheKey("https://wx1.sinaimg.cn/large/p.jpg") == "https://wx1.sinaimg.cn/large/p.jpg")
    }

    @Test func picksAFreshVideoURL() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let video = VideoInfo(streamURLs: ["https://v/1.mp4?Expires=1000100", "https://v/2.mp4?Expires=1003600", "https://v/3.mp4"])
        #expect(freshStreamURL(video, now: now) == "https://v/2.mp4?Expires=1003600")
        #expect(isFresh("https://v/3.mp4", now: now))
    }
}

struct FormatTests {
    @Test func countsInChineseUnitsRoundedDown() {
        #expect(formatCount(9999) == "9999")
        #expect(formatCount(12_999) == "1.2万")
        #expect(formatCount(1_000_000) == "100万")
        #expect(formatCount(300_000_000) == "3亿")
    }

    @Test func durationsAndSizes() {
        #expect(formatDuration(61) == "1:01")
        #expect(formatDuration(3661) == "1:01:01")
        #expect(formatBytes(300 * 1024 * 1024) == "300 MB")
        #expect(formatBytes(Int64(2.5 * 1024 * 1024)) == "2.5 MB")
        #expect(formatBytes(1024 * 1024 * 1024) == "1 GB")
    }

    @Test func postTimesAsWeiboShowsThem() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = parseWeiboDate("Fri Oct 30 12:00:00 +0800 2026")!
        func shown(_ value: String) -> String { formatPostTime(parseWeiboDate(value)!, now: now, calendar: calendar) }
        #expect(shown("Fri Oct 30 11:59:30 +0800 2026") == "刚刚")
        #expect(shown("Fri Oct 30 11:15:00 +0800 2026") == "45分钟前")
        #expect(shown("Fri Oct 30 02:00:00 +0800 2026") == "10小时前")
        #expect(shown("Thu Oct 29 08:05:00 +0800 2026") == "昨天 08:05")
        #expect(shown("Mon Oct 12 13:17:46 +0800 2026") == "10-12 13:17")
        #expect(shown("Mon Oct 13 13:17:46 +0800 2025") == "2025-10-13")
        #expect(parseWeiboDate("2026-10-12") == nil)
    }

    @Test func textSizesStepAlongDynamicType() {
        #expect(TextSize.standard.applied(to: .large) == .large)
        #expect(TextSize.extraLarge.applied(to: .large) == .xxLarge)
        #expect(TextSize.extraSmall.applied(to: .xSmall) == .xSmall)
    }
}

@MainActor
struct PagedListTests {
    @Test func loadsPagesDropsRepeatsAndKeepsUserEdits() async throws {
        let pages: [String?: Paged<String>] = [
            nil: Paged(items: ["a", "b"], nextCursor: "2", total: 3),
            "2": Paged(items: ["b", "c"], nextCursor: nil),
        ]
        let list = PagedList<String>(fetch: { pages[$0]! }, id: { $0 })
        try await list.refresh()
        list.prepend("new")
        await list.loadMore()
        #expect(list.items == ["new", "a", "b", "c"])
        #expect(list.state.list?.hasMore == false)
        #expect(list.state.list?.total == 4)
        list.remove("a")
        #expect(list.items == ["new", "b", "c"])
    }

    @Test func aFailedPageIsKeptAsItsError() async throws {
        nonisolated(unsafe) var fail = false
        let list = PagedList<String>(
            fetch: { cursor in
                if fail { throw WeiboError.network }
                return Paged(items: [cursor ?? "first"], nextCursor: "more")
            }, id: { $0 })
        try await list.refresh()
        fail = true
        await list.loadMore()
        #expect(list.state.list?.loadMoreError == .network)
        #expect(list.items == ["first"])
    }
}
