import Foundation
import Observation
import WebKit

/// Lets Weibo establish a visitor session in an isolated, temporary browser.
/// No page is displayed, no account cookies are read, and no challenge is solved.
@MainActor
func prepareGuestCookies(timeout: Duration = .seconds(30)) async throws -> Cookies {
    let store = WKWebsiteDataStore.nonPersistent()
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = store
    let page = WebPage(configuration: configuration, navigationDecider: WebOnlyNavigation())
    page.customUserAgent = browserUserAgent
    let home = URL(string: "https://m.weibo.cn/")!
    defer {
        page.stopLoading()
        page.load(URL(string: "about:blank"))
    }
    page.load(home)
    let watcher = Task { @MainActor () -> [String: String]? in
        for await loading in Observations({ page.isLoading }) {
            if Task.isCancelled { return nil }
            guard !loading, page.url?.host == home.host else { continue }
            let cookies = cookiesSent(to: home, from: await store.httpCookieStore.allCookies())
            if cookies["SUB"] != nil { return cookies }
        }
        return nil
    }
    let deadline = Task { @MainActor in
        try? await Task.sleep(for: timeout)
        watcher.cancel()
    }
    defer { deadline.cancel() }
    let cookies = await withTaskCancellationHandler {
        await watcher.value
    } onCancel: {
        watcher.cancel()
    }
    try Task.checkCancellation()
    guard let cookies else { throw WeiboError.api("暂时无法建立游客会话，请稍后重试或登录微博") }
    return [WeiboCookieJar.mobile: cookies]
}
