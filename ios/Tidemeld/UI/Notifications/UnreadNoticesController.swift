import Foundation
import Observation

/// How soon after one check returning to the app or refreshing the home
/// timeline checks again.
let unreadRecheckInterval: Duration = .seconds(60)

/// Which kinds of notifications are unread, which the tab bar and the
/// notification page's tabs mark.
///
/// Checked only when the user signs in, opens the app or refreshes the home
/// timeline ([check]), never polled (PLAN §2). A kind stays marked until the
/// user opens its tab ([markRead]); a check only adds marks. Another account
/// starts it over.
@MainActor @Observable
final class UnreadNoticesController {
    private(set) var state = UnreadNotices()

    @ObservationIgnored private let api: WeiboAPI
    @ObservationIgnored private let session: SessionController
    @ObservationIgnored private var checkedAt: ContinuousClock.Instant?
    @ObservationIgnored private var checking = false
    /// Kinds marked read while a check was out, whose result predates that.
    @ObservationIgnored private var readDuringCheck: Set<NoticeKind> = []
    /// Bumped for each account, so a check for the last one is dropped.
    @ObservationIgnored private var generation = 0

    init(api: WeiboAPI, session: SessionController) {
        self.api = api
        self.session = session
        session.onUidChange { [weak self] _ in
            guard let self else { return }
            generation += 1
            checkedAt = nil
            state = UnreadNotices()
        }
    }

    /// Asks Weibo what is unread, unless it was asked less than [minInterval]
    /// ago or is being asked now. Failures leave things as they were: the mark
    /// is a hint only. Returns whether it asked.
    @discardableResult
    func check(minInterval: Duration = .zero) async -> Bool {
        guard case .signedIn = session.state, !checking else { return false }
        let now = ContinuousClock.now
        if let checkedAt, now - checkedAt < minInterval { return false }
        checkedAt = now
        checking = true
        readDuringCheck = []
        let generation = generation
        defer { checking = false }
        do {
            let unread = try await api.fetchUnreadNotices()
            guard generation == self.generation else { return true }
            // Loading a list marks it read on Weibo's side, so a tab opened
            // since the check went out is up to date.
            state = UnreadNotices(kinds: state.kinds.union(unread.kinds).subtracting(readDuringCheck))
        } catch {
            devLog("unread notices: \(WeiboError.of(error))")
        }
        return true
    }

    /// [check] in the background, as for an event the user caused elsewhere.
    func requestCheck(minInterval: Duration = .zero) {
        Task { await check(minInterval: minInterval) }
    }

    /// The user opened the tab of [kind].
    func markRead(_ kind: NoticeKind) {
        if checking { readDuringCheck.insert(kind) }
        if state.has(kind) { state = state.without(kind) }
    }
}
