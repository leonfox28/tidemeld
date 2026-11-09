import Observation
import SwiftUI

/// What a profile page holds: the user with [uid], or else the one named
/// [screenName], and their statuses. Opened by uid it loads both at once; by
/// name only, the statuses wait for the profile.
@MainActor @Observable
final class ProfileModel {
    private let uid: String?
    private let screenName: String?
    private(set) var profile: UserProfile?
    private(set) var error: WeiboError?
    private(set) var statuses: PagedList<Status>?
    @ObservationIgnored private var graph: AppGraph?
    @ObservationIgnored private(set) var controls: WeiboProfileControls?
    @ObservationIgnored private var generation = 0

    init(uid: String?, screenName: String?) {
        self.uid = uid
        self.screenName = screenName
    }

    func start(_ graph: AppGraph) {
        guard self.graph == nil else { return }
        self.graph = graph
        controls = WeiboProfileControls(graph)
        if let uid { startStatuses(uid) }
        reload()
    }

    func reload() {
        error = nil
        generation += 1
        let ticket = generation
        Task {
            do { try await loadProfile(ticket) } catch {
                if ticket == generation { self.error = WeiboError.of(error) }
            }
        }
    }

    private func loadProfile(_ ticket: Int) async throws {
        let started = controls?.readStamp ?? 0
        let result = try await graph!.api.fetchProfile(uid: profile?.user.id ?? uid, screenName: screenName)
        guard ticket == generation else { return }
        self.profile = result
        controls?.ingest(result, started: started)
        error = nil
        if statuses == nil { startStatuses(result.user.id) }
    }

    private func startStatuses(_ uid: String) {
        let api = graph!.api
        let list = PagedList<Status>(
            fetch: { try await api.fetchUserStatuses(uid: uid, page: $0.flatMap(Int.init) ?? 1) },
            id: \.id)
        // So the user's own posts and reposts show, and deleted ones go.
        graph!.openLists.userStatuses.add(uid, list)
        statuses = list
        list.start()
    }

    /// Loads the profile and the statuses again; throws on failure, what was
    /// shown staying, for the caller to report.
    func refresh() async throws {
        generation += 1
        let ticket = generation
        async let details: Void = loadProfile(ticket)
        async let content: Void? = statuses?.refresh()
        var failure: Error?
        do { try await details } catch { failure = error }
        do { _ = try await content } catch { failure = failure ?? error }
        if let failure { throw failure }
    }
}

/// A user's profile and statuses: the user with [uid], or else the one named
/// [screenName].
///
/// [initial] (the user as the previous page showed them) shows until the
/// profile arrives.
struct ProfilePage: View {
    var uid: String? = nil
    var initial: WeiboUser? = nil
    var screenName: String? = nil

    @Environment(AppGraph.self) private var graph
    @State private var model: ProfileModel

    init(uid: String? = nil, initial: WeiboUser? = nil, screenName: String? = nil) {
        self.uid = uid
        self.initial = initial
        self.screenName = screenName
        _model = State(wrappedValue: ProfileModel(uid: uid, screenName: screenName))
    }

    var body: some View {
        let user = model.profile?.user ?? initial
        let presentation = WeiboProfilePresentation(model: model, initial: initial)
        SocialProfilePage(
            title: user?.screenName ?? screenName ?? "", profile: presentation.profile,
            posts: model.statuses, failure: model.error.map(AppFailure.of), emptyText: "还没有微博",
            retry: { model.reload() }, refresh: { try await model.refresh() },
            actions: model.profile.flatMap { model.controls?.actions($0) },
            badge: { presentation.badge }, details: { presentation.details },
            row: { StatusCard(status: $0, actions: actions()) }
        )
        .onAppear { model.start(graph) }
    }

    private func actions() -> StatusCardActions {
        var actions = graph.statusActions
        let base = actions
        let own = model.profile?.user.id ?? uid
        // This user's own avatar would only open this page again.
        actions.onUser = { if $0.id != own { base.onUser?($0) } }
        return actions
    }
}

@MainActor private struct WeiboProfilePresentation {
    let model: ProfileModel
    let initial: WeiboUser?

    var profile: ProfilePresentation {
        let p = model.profile
        let failed = p == nil && model.error != nil
        let user = p?.user ?? initial
        let relation: String? =
            if let p {
                model.controls?.state(p).value.label
            } else { nil }
        let loading = p == nil && !failed
        let counts = [("关注", p?.friendsCount), ("粉丝", p?.followersCount), ("微博", p?.statusesCount)]
            .compactMap { label, value in
                (value ?? (loading ? 0 : nil)).map { ProfileCount(label: label, value: $0) }
            }
        return ProfilePresentation(
            name: user?.screenName, avatarURL: user?.avatarURL,
            coverURL: p?.coverURL, counts: counts, relation: relation,
            verification: p?.verifiedReason.map { "微博认证：\($0)" }, description: p?.description,
            loading: loading, failure: failed ? "资料加载失败：\(model.error!.message)" : nil)
    }

    @ViewBuilder var badge: some View {
        if let verified = (model.profile?.user ?? initial)?.verifiedType, showsVerified(verified) {
            VerifiedIcon(verifiedType: verified, size: 18)
        }
    }

    @ViewBuilder var details: some View {
        if let p = model.profile, p.gender != nil || p.location != nil {
            HStack(spacing: 4) {
                switch p.gender {
                case "m": Image(systemName: "figure.stand").foregroundStyle(Color(rgb: 0x42A5F5))
                case "f": Image(systemName: "figure.stand.dress").foregroundStyle(Color(rgb: 0xF06292))
                default: EmptyView()
                }
                if let location = p.location { Text(location).foregroundStyle(AppTheme.secondary) }
            }.font(.caption)
        }
    }
}
