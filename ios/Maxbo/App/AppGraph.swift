import Foundation
import Observation
import SwiftUI

/// The app's long-lived objects, made by hand. Pages reach it through the
/// environment.
@MainActor @Observable
final class AppGraph {
    @ObservationIgnored let settings: SettingsController
    @ObservationIgnored let session: SessionController
    /// Signed in as [session] says, renewing the session when Weibo rejects it.
    @ObservationIgnored let api: WeiboAPI
    @ObservationIgnored let webCookies: WebCookies
    @ObservationIgnored let images: ImageLoader
    /// The signed-in user's "最新微博" timeline, app-wide, so posts the user
    /// writes elsewhere can go in.
    @ObservationIgnored let timeline: PagedList<Status>
    @ObservationIgnored let unread: UnreadNoticesController
    @ObservationIgnored let likes: LikesController
    @ObservationIgnored let openLists: OpenLists
    @ObservationIgnored let composeDraft: ComposeDraftController
    @ObservationIgnored let repostDrafts: RepostDrafts
    /// Where the user is, and what is presented over the tabs.
    @ObservationIgnored let router = Router()
    @ObservationIgnored let toasts = Toasts()
    /// Statuses being deleted, so a second tap doesn't ask Weibo again.
    @ObservationIgnored var deletingStatuses: Set<String> = []

    init(
        settings: SettingsController, session: SessionController, api: WeiboAPI,
        webCookies: WebCookies, images: ImageLoader
    ) {
        self.settings = settings
        self.session = session
        self.api = api
        self.webCookies = webCookies
        self.images = images
        // Every request follows a user action: opening the tab, pulling to
        // refresh, or scrolling to the end. Another account, or none, starts it
        // over.
        let timeline = PagedList<Status>(
            fetch: { [weak session] cursor in
                guard let uid = session?.state.uid else { return Paged(items: []) }
                return try await api.fetchHomeTimeline(uid: uid, maxId: cursor)
            },
            id: \.id)
        if session.state.uid == nil { timeline.reset(to: .ready(PagedState())) }
        session.onUidChange { uid in timeline.reset(to: uid == nil ? .ready(PagedState()) : .loading) }
        self.timeline = timeline
        unread = UnreadNoticesController(api: api, session: session)
        likes = LikesController(api: api, session: session)
        openLists = OpenLists(timeline: timeline)
        composeDraft = ComposeDraftController(api: api, openLists: openLists, session: session)
        repostDrafts = RepostDrafts(session: session)
        settings.onChange = { [images] settings in images.setLimit(mb: settings.imageCacheLimitMB) }
    }

    /// The real thing, reading the saved settings and session before the first
    /// frame, so a chosen theme doesn't flash the default, and a signed-in user
    /// doesn't see the login prompt.
    static func create() -> AppGraph {
        let settings = SettingsController(storage: DefaultsSettingsStorage())
        let sessionStorage = KeychainSessionStorage()
        sessionStorage.dropLeftovers()
        // Pictures picked for drafts, which went with the last run.
        try? FileManager.default.removeItem(at: draftPicturesDirectory)
        let throttle = RequestThrottle()
        let httpFor = { (jar: WeiboCookieJar) in WeiboHTTP(jar: jar, throttle: throttle) }
        let webCookies = WebKitCookies()
        let session = SessionController(
            restored: sessionStorage.load(), storage: sessionStorage, webCookies: webCookies,
            renewer: WebPageSessionRenewer(webCookies: webCookies), httpFor: httpFor)
        let api = WeiboAPI(http: httpFor(session.jar)) { [weak session] sentAt in
            await session?.renewOrExpire(sentAt: sentAt) ?? false
        }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let images = ImageLoader(
            directory: caches.appendingPathComponent("image_cache"),
            limitMB: settings.settings.imageCacheLimitMB)
        ImageLoader.shared = images
        return AppGraph(settings: settings, session: session, api: api, webCookies: webCookies, images: images)
    }
}
