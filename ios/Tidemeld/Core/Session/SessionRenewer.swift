import Foundation
import Observation
import WebKit

/// Renews a lapsed session the way a browser does.
///
/// Weibo honours `SUB` for about a week, but signing in also leaves a 30-day
/// auto-login cookie (`ALC`) on passport.weibo.com. A browser that opens
/// weibo.com with a lapsed `SUB` ends up on passport's visitor page (at times
/// after a detour through login.sina.com.cn), whose script trades `ALC` for a
/// new `SUB` and another 30 days (PLAN §8). Renewing lets Weibo's own pages do
/// just that in a web page, which shares its cookies with the login page.
@MainActor
protocol SessionRenewer: AnyObject {
    /// Opens weibo.com and offers the web view's cookies to [adopt] each time a
    /// page leaves a `SUB` other than [lapsedSub] and those offered before.
    ///
    /// Returns true once [adopt] accepts them, or false when it turns down one
    /// Weibo set meanwhile (a visitor's, when there was nothing to renew), or
    /// when Weibo takes too long.
    func renew(lapsedSub: String?, adopt: @escaping @MainActor (Cookies) async -> Bool) async -> Bool
}

/// Follows the pages of one renewal; see [SessionRenewer.renew].
@MainActor
final class RenewalTracker {
    private var offered: Set<String?>
    /// The web view's `SUB` before the first page.
    private let startSub: String?
    private let adopt: @MainActor (Cookies) async -> Bool

    init(lapsedSub: String?, startSub: String?, adopt: @escaping @MainActor (Cookies) async -> Bool) {
        offered = [lapsedSub]
        self.startSub = startSub
        self.adopt = adopt
    }

    /// Handles the [cookies] a main-frame page left behind: true once [adopt]
    /// accepted them, false if Weibo won't renew, or nil to wait for the next
    /// page.
    func pageLoaded(_ cookies: Cookies) async -> Bool? {
        guard let sub = cookies[WeiboCookieJar.web]?["SUB"], offered.insert(sub).inserted else {
            return nil
        }
        if await adopt(cookies) { return true }
        // The web view's own session may have lapsed too, and is renewed in
        // turn; one Weibo set on the way is all it is going to set.
        return sub == startSub ? nil : false
    }
}

/// Only web pages; app links such as sinaweibo:// go nowhere.
struct WebOnlyNavigation: WebPage.NavigationDeciding {
    var onNavigate: (@MainActor (URL) -> Void)? = nil

    mutating func decidePolicy(
        for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if action.target?.isMainFrame ?? true { onNavigate?(url) }
        // Phone-sized pages, whatever the desktop user agent says: passport
        // lays itself out for the screen it finds.
        preferences.preferredContentMode = .mobile
        // Weibo still links and redirects to some pages over plain http; the
        // same pages are served over https.
        preferences.preferredHTTPSNavigationPolicy = .errorOnFailure
        return url.scheme == "https" || url.scheme == "http" || url.scheme == "about" ? .allow : .cancel
    }
}

/// Renews in a web page that is never shown.
@MainActor
final class WebPageSessionRenewer: SessionRenewer {
    private let webCookies: WebCookies
    private let timeout: Duration

    init(webCookies: WebCookies, timeout: Duration = .seconds(20)) {
        self.webCookies = webCookies
        self.timeout = timeout
    }

    func renew(lapsedSub: String?, adopt: @escaping @MainActor (Cookies) async -> Bool) async -> Bool {
        let tracker = RenewalTracker(
            lapsedSub: lapsedSub,
            startSub: await webCookies.readWeiboCookies()[WeiboCookieJar.web]?["SUB"],
            adopt: adopt)
        let page = WebPage(
            navigationDecider: WebOnlyNavigation { url in
                devLog("session renewal: to \(url.host ?? "")\(url.path)")
            })
        page.customUserAgent = browserUserAgent
        let webCookies = webCookies
        defer {
            // Leave nothing running: weibo.com's own pages poll for news.
            page.stopLoading()
            page.load(URL(string: "about:blank"))
        }
        page.load(URL(string: "https://weibo.com/"))
        let watcher = Task { @MainActor in
            // Each time a page is done, whether it loaded or failed: passport's
            // last hop, through login.sina.com.cn, fails in a web view after
            // the weibo.com cookies are set (PLAN §8 item 1).
            for await loading in Observations({ page.isLoading }) {
                if Task.isCancelled { return false }
                guard !loading else { continue }
                let cookies = await webCookies.readWeiboCookies()
                let url = page.url
                devLog(
                    "session renewal: \(url?.host ?? "")\(url?.path ?? "") done, "
                        + "weibo.com=\(cookies[WeiboCookieJar.web]?.keys.sorted() ?? [])")
                if let result = await tracker.pageLoaded(cookies) { return result }
            }
            return false
        }
        let timeout = Task { @MainActor [timeout] in
            try? await Task.sleep(for: timeout)
            watcher.cancel()
        }
        let renewed = await watcher.value
        timeout.cancel()
        return renewed
    }
}

@MainActor
final class ExplicitSessionRenewer: SessionRenewer {
    func renew(lapsedSub: String?, adopt: @escaping @MainActor (Cookies) async -> Bool) async -> Bool { false }
}
