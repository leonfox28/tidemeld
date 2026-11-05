import Foundation
import Observation

enum SessionState: Sendable, Equatable {
    /// [expired]: Weibo ended the session, as opposed to the user signing out.
    case signedOut(expired: Bool)
    case signedIn(Account)

    var account: Account? {
        if case .signedIn(let account) = self { return account }
        return nil
    }

    var uid: String? { account?.uid }
}

/// Who is signed in, and the cookies every API request is sent with ([jar]).
@MainActor @Observable
final class SessionController {
    private(set) var state: SessionState
    @ObservationIgnored var onLogout: ((String) async -> Void)?
    @ObservationIgnored var onExpired: ((String) -> Void)?

    @ObservationIgnored let jar: WeiboCookieJar
    @ObservationIgnored private let storage: SessionStorage
    @ObservationIgnored private let webCookies: WebCookies
    @ObservationIgnored private let renewer: SessionRenewer
    /// Makes a client on a cookie jar, to check cookies before adopting them.
    @ObservationIgnored private let httpFor: (WeiboCookieJar) -> WeiboHTTP

    @ObservationIgnored private var uidObservers: [(String?) -> Void] = []
    @ObservationIgnored private var renewal: Task<Bool, Never>?
    @ObservationIgnored private var renewedAt: ContinuousClock.Instant?

    /// [restored]: the session saved at the last launch, if any.
    init(
        restored: StoredSession?, storage: SessionStorage, webCookies: WebCookies,
        renewer: SessionRenewer, httpFor: @escaping (WeiboCookieJar) -> WeiboHTTP
    ) {
        jar = WeiboCookieJar(restored?.cookies ?? [:])
        state = restored.map { .signedIn($0.account) } ?? .signedOut(expired: false)
        self.storage = storage
        self.webCookies = webCookies
        self.renewer = renewer
        self.httpFor = httpFor
        // Weibo rotates cookies (e.g. XSRF-TOKEN) on responses; keep the stored
        // copy current so the next launch starts with what the server expects.
        jar.addListener { [weak self] in
            Task { @MainActor in self?.save() }
        }
    }

    var account: Account? { state.account }

    /// Calls [observer] each time the signed-in account changes, with its uid
    /// (nil when signed out).
    func onUidChange(_ observer: @escaping (String?) -> Void) {
        uidObservers.append(observer)
    }

    private func setState(_ next: SessionState) {
        let previous = state.uid
        state = next
        if previous != next.uid { for observer in uidObservers { observer(next.uid) } }
    }

    /// Signs in with cookies taken from the login web view.
    ///
    /// Throws `sessionExpired` if the cookies don't belong to a signed-in user
    /// (visitors get a `SUB` cookie too), or another error if the check itself
    /// failed.
    func completeLogin(_ cookies: Cookies) async throws {
        let (account, verified) = try await verify(cookies)
        jar.replaceAll(verified, newIdentity: true)
        setState(.signedIn(account))
        save()
    }

    func logout() async {
        let uid = state.uid
        setState(.signedOut(expired: false))
        jar.clear()
        storage.clear()
        // Sign the embedded browser out too, so the next login starts fresh.
        await webCookies.clearDomains(SocialPlatform.weibo.domains)
        if let uid { await onLogout?(uid) }
    }

    func activate(_ session: StoredSession?) {
        renewal?.cancel(); renewal = nil; renewedAt = nil
        jar.replaceAll(session?.cookies ?? [:], newIdentity: true)
        setState(session.map { .signedIn($0.account) } ?? .signedOut(expired: false))
        if session == nil { storage.clear() } else { save() }
    }

    func verifyLogin(_ cookies: Cookies) async throws -> StoredSession {
        let (account, verified) = try await verify(cookies)
        return StoredSession(account: account, cookies: verified)
    }

    func isolated(_ session: StoredSession, storage: SessionStorage) -> SessionController {
        SessionController(restored: session, storage: storage, webCookies: webCookies,
            renewer: ExplicitSessionRenewer(), httpFor: httpFor)
    }

    func apiForSession() -> WeiboAPI {
        WeiboAPI(http: httpFor(jar)) { [weak self] sentAt in await self?.renewOrExpire(sentAt: sentAt) ?? false }
    }

    /// Called when Weibo rejects the session of a request sent at [sentAt].
    ///
    /// Renews the session as a browser would (see [SessionRenewer]) and returns
    /// whether it is good again; if it can't be, signs out. Rejections that
    /// come in together share one renewal, and one for a session renewed since
    /// the request went out needs none.
    func renewOrExpire(sentAt: ContinuousClock.Instant) async -> Bool {
        guard case .signedIn = state else { return false }
        if let renewedAt, renewedAt > sentAt { return true }
        if let renewal { return await renewal.value }
        let started = Task { await renew() }
        renewal = started
        let renewed = await started.value
        if renewal == started { renewal = nil }
        return renewed
    }

    private func renew() async -> Bool {
        guard let uid = state.uid else { return false }
        let renewed = await renewer.renew(lapsedSub: jar.value(WeiboCookieJar.web, "SUB")) {
            [weak self] cookies in
            guard let self else { return false }
            do {
                let (account, verified) = try await self.verify(cookies)
                // The user may have signed out meanwhile.
                guard !Task.isCancelled, account.uid == uid, self.state.uid == uid else { return false }
                self.jar.replaceAll(verified)
                self.renewedAt = .now
                return true
            } catch {
                return false
            }
        }
        devLog("session renewal: \(renewed ? "renewed" : "failed")")
        if !renewed, !Task.isCancelled, state.uid == uid { expire() }
        return renewed
    }

    /// Signs out after Weibo rejected the session for good.
    ///
    /// Web view cookies are kept: if the browser session is still alive there,
    /// opening the login page signs the user straight back in.
    func expire() {
        guard case .signedIn = state else { return }
        let uid = state.uid
        setState(.signedOut(expired: true))
        jar.clear()
        storage.clear()
        if let uid { onExpired?(uid) }
    }

    /// Checks [cookies] against the API, returning the account they sign in as
    /// and the cookies with any the server set meanwhile.
    private func verify(_ cookies: Cookies) async throws -> (Account, Cookies) {
        let candidate = WeiboCookieJar(cookies)
        let account = try await WeiboAPI(http: httpFor(candidate)).fetchCurrentAccount()
        return (account, candidate.toCookies())
    }

    private func save() {
        guard case .signedIn(let account) = state else { return }
        storage.save(StoredSession(account: account, cookies: jar.toCookies()))
    }
}
