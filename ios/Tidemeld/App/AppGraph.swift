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
    @ObservationIgnored let guestTimeline: PagedList<Status>
    @ObservationIgnored let unread: UnreadNoticesController
    @ObservationIgnored let likes: LikesController
    @ObservationIgnored let openLists: OpenLists
    @ObservationIgnored let composeDraft: ComposeDraftController
    @ObservationIgnored let repostDrafts: RepostDrafts
    /// Where the user is, and what is presented over the tabs.
    @ObservationIgnored let router: Router
    @ObservationIgnored let accounts: AccountManager
    @ObservationIgnored let xAPI: XWebAPI?
    @ObservationIgnored let profileRelationships: ProfileRelationships
    @ObservationIgnored private var accountGraphs: [String: (Int, AppGraph)] = [:]
    @ObservationIgnored lazy var xInteractions = XInteractions(accounts: accounts, api: xAPI, relationships: profileRelationships)
    @ObservationIgnored lazy var socialFeed = makeSocialFeed()

    private func makeSocialFeed() -> SocialFeedController {
        SocialFeedController(accounts: accounts) { [weak self] account, cursor in
            guard let self else { throw WeiboError.cancelled }
            switch account.platform {
            case .weibo:
                guard let context = self.forAccount(account.id) else { throw WeiboError.sessionExpired }
                let page = try await context.api.fetchHomeTimeline(uid: account.session.account.uid, maxId: cursor)
                return Paged(items: page.items.map { .weibo(owner: account.id, $0) }, nextCursor: page.nextCursor)
            case .x:
                guard let api = self.xAPI else { throw WeiboError.api("X 接口配置不可用") }
                let started = self.xInteractions.readStamp
                let page = try await api.timeline(account.session, cursor: cursor) { [weak accounts = self.accounts] cookies in
                    await MainActor.run {
                        if accounts?.find(account.id)?.revision == account.revision { accounts?.updateCookies(account.id, cookies: cookies) }
                    }
                }
                self.xInteractions.ingest(account, posts: page.items, started: started)
                return Paged(items: page.items.map { .x(owner: account.id, $0) }, nextCursor: page.nextCursor)
            }
        }
    }
    @ObservationIgnored let toasts: Toasts
    /// Statuses being deleted, so a second tap doesn't ask Weibo again.
    @ObservationIgnored var deletingStatuses: Set<String> = []

    init(
        settings: SettingsController, session: SessionController, api: WeiboAPI,
        webCookies: WebCookies, images: ImageLoader, guestAPI: GuestWeiboAPI? = nil,
        accountStorage: AccountStorage? = nil, sharedAccounts: AccountManager? = nil,
        sharedProfileRelationships: ProfileRelationships? = nil,
        xAPI: XWebAPI? = nil, router: Router? = nil, sharedToasts: Toasts? = nil, onPostChanged: ((Status, Bool) -> Void)? = nil
    ) {
        self.settings = settings
        self.session = session
        self.api = api
        self.webCookies = webCookies
        self.images = images
        self.accounts = sharedAccounts ?? AccountManager(storage: accountStorage ?? MemoryAccountStorage(), weibo: session, web: webCookies)
        self.xAPI = xAPI
        self.profileRelationships = sharedProfileRelationships ?? ProfileRelationships()
        self.router = router ?? Router()
        self.toasts = sharedToasts ?? Toasts()
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
        let guestTimeline = PagedList<Status>(
            fetch: { _ in
                guard let guestAPI else { throw WeiboError.network }
                return try await guestAPI.fetchTimeline()
            }, id: \.id)
        self.guestTimeline = guestTimeline
        session.onUidChange { _ in guestTimeline.reset() }
        unread = UnreadNoticesController(api: api, session: session)
        likes = LikesController(api: api, session: session)
        openLists = OpenLists(timeline: timeline)
        composeDraft = ComposeDraftController(api: api, openLists: openLists, session: session)
        repostDrafts = RepostDrafts(session: session)
        openLists.onOwnChange = { [weak self] post, added in
            guard let self else { return }
            if let onPostChanged { onPostChanged(post, added) }
            else { self.socialFeed.ownPostChanged(owner: "weibo:\(self.session.state.uid ?? "")", post: post, added: added) }
        }
        settings.onChange = { [images] settings in images.setLimit(mb: settings.imageCacheLimitMB) }
        // Pages opened for an account go when the user signs out, or another
        // account signs in after this one lapsed. A lapsed session keeps them,
        // for the user to carry on once signed back in.
        var owner = session.state.uid
        session.onUidChange { [router = self.router, weak session] uid in
            if uid == nil, router.tab == .notifications { router.tab = .home }
            let signedOut = session?.state == .signedOut(expired: false)
            if signedOut || (uid != nil && uid != owner) { router.paths = [:] }
            if let uid { owner = uid }
        }
    }

    func forAccount(_ key: String) -> AppGraph? {
        guard let account = accounts.find(key), account.platform == .weibo, !account.expired else { return nil }
        if let cached = accountGraphs[key], cached.0 == account.revision {
            if cached.1.session.jar.toCookies() != account.session.cookies { cached.1.session.jar.replaceAll(account.session.cookies) }
            return cached.1
        }
        let storage = ScopedSessionStorage(initial: account.session) { [weak accounts] stored in
            Task { @MainActor in
                guard accounts?.find(key)?.revision == account.revision else { return }
                if let stored { accounts?.updateCookies(key, cookies: stored.cookies) }
                else { accounts?.expire(key) }
            }
        }
        let scopedSession = session.isolated(account.session, storage: storage)
        let scoped = AppGraph(settings: settings, session: scopedSession, api: scopedSession.apiForSession(),
            webCookies: webCookies, images: images, sharedAccounts: accounts, sharedProfileRelationships: profileRelationships, xAPI: xAPI, router: router.scoped(key), sharedToasts: toasts, onPostChanged: { [weak self] post, added in
                self?.socialFeed.ownPostChanged(owner: key, post: post, added: added)
            })
        accountGraphs[key] = (account.revision, scoped)
        return scoped
    }

    /// The real thing, reading the saved settings and session before the first
    /// frame, so a chosen theme doesn't flash the default, and a signed-in user
    /// doesn't see the login prompt.
    static func create() -> AppGraph {
        let settings = SettingsController(storage: DefaultsSettingsStorage())
        let sessionStorage = KeychainSessionStorage()
        sessionStorage.dropLeftovers()
        let accountStorage = KeychainAccountStorage()
        accountStorage.dropLeftovers()
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
        let guestAPI = GuestWeiboAPI(http: httpFor(WeiboCookieJar()), prepare: { try await prepareGuestCookies() })
        let spec = Bundle.main.url(forResource: "x-web", withExtension: "json").flatMap { try? Data(contentsOf: $0) }.flatMap(JSON.parse) ?? .object([:])
        return AppGraph(settings: settings, session: session, api: api, webCookies: webCookies, images: images, guestAPI: guestAPI,
            accountStorage: accountStorage, xAPI: XWebAPI(spec: spec, throttle: throttle))
    }
}

private final class ScopedSessionStorage: SessionStorage, Sendable {
    let initial: StoredSession
    let update: @Sendable (StoredSession?) -> Void
    init(initial: StoredSession, update: @escaping @Sendable (StoredSession?) -> Void) { self.initial = initial; self.update = update }
    func load() -> StoredSession? { initial }
    func save(_ session: StoredSession) { update(session) }
    func clear() { update(nil) }
}
