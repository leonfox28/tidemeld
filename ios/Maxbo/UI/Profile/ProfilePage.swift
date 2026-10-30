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

    init(uid: String?, screenName: String?) {
        self.uid = uid
        self.screenName = screenName
    }

    func start(_ graph: AppGraph) {
        guard self.graph == nil else { return }
        self.graph = graph
        if let uid { startStatuses(uid) }
        reload()
    }

    func reload() {
        error = nil
        Task {
            do {
                let profile = try await graph!.api.fetchProfile(uid: uid, screenName: screenName)
                self.profile = profile
                if statuses == nil { startStatuses(profile.user.id) }
            } catch {
                self.error = WeiboError.of(error)
            }
        }
    }

    private func startStatuses(_ uid: String) {
        let api = graph!.api
        let list = PagedList<Status>(
            fetch: { try await api.fetchUserStatuses(uid: uid, page: $0.flatMap(Int.init) ?? 1) }, id: \.id)
        // So the user's own posts and reposts show, and deleted ones go.
        graph!.openLists.userStatuses.add(uid, list)
        statuses = list
        list.start()
    }

    /// Loads the profile and the statuses again; throws on failure, what was
    /// shown staying, for the caller to report.
    func refresh() async throws {
        async let profile = graph!.api.fetchProfile(uid: uid, screenName: screenName)
        try await statuses?.refresh()
        self.profile = try await profile
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
        Group {
            if let statuses = model.statuses {
                List {
                    ProfileHeader(model: model, initial: initial).readingWidth().plainRow()
                    PagedRows(list: statuses, emptyText: "还没有微博") { status in
                        StatusCard(status: status, actions: actions(statuses))
                            .readingWidth()
                            .statusRow()
                    }
                }
                .listStyle(.plain)
                .appListStyle()
                .tabBarHidesOnScroll()
                .refreshable {
                    do {
                        try await model.refresh()
                    } catch {
                        graph.toasts.showError(error, router: graph.router)
                    }
                }
            } else if let error = model.error {
                ErrorRetry(error: error) { model.reload() }
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackground()
        .navigationTitle(user?.screenName ?? screenName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.start(graph) }
    }

    private func actions(_ statuses: PagedList<Status>) -> StatusCardActions {
        var actions = graph.statusActions
        let base = actions
        let own = model.profile?.user.id ?? uid
        // This user's own avatar would only open this page again.
        actions.onUser = { if $0.id != own { base.onUser?($0) } }
        return actions
    }
}

private struct ProfileHeader: View {
    let model: ProfileModel
    let initial: WeiboUser?
    @Environment(\.displayScale) private var scale

    var body: some View {
        let p = model.profile
        let failed = p == nil && model.error != nil
        let user = p?.user ?? initial
        let relation: String? =
            if let p {
                p.following && p.followsMe ? "互相关注" : p.following ? "已关注" : p.followsMe ? "关注了你" : nil
            } else { nil }
        VStack(alignment: .leading, spacing: 0) {
            if let cover = p?.coverURL {
                WeiboImage(url: cover, maxPixels: 1200).frame(height: 120).frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    UserAvatar(user: user, size: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(user?.screenName ?? " ")
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)
                                .redacted(reason: user == nil && !failed ? .placeholder : [])
                            if let verified = user?.verifiedType, showsVerified(verified) {
                                VerifiedIcon(verifiedType: verified, size: 18)
                            }
                            if let relation { TagLabel(text: relation) }
                        }
                        if let p {
                            ProfileCounts(profile: p)
                        } else if !failed {
                            Text("0 关注    0 粉丝    0 微博").font(.subheadline).redacted(reason: .placeholder)
                        }
                    }
                }
                if let reason = p?.verifiedReason {
                    Text("微博认证：\(reason)").font(.caption).foregroundStyle(AppTheme.secondary)
                }
                if let description = p?.description { Text(description).font(.subheadline) }
                if let p, p.gender != nil || p.location != nil {
                    HStack(spacing: 4) {
                        switch p.gender {
                        case "m": Image(systemName: "figure.stand").foregroundStyle(Color(rgb: 0x42A5F5))
                        case "f": Image(systemName: "figure.stand.dress").foregroundStyle(Color(rgb: 0xF06292))
                        default: EmptyView()
                        }
                        if let location = p.location { Text(location).foregroundStyle(AppTheme.secondary) }
                    }
                    .font(.caption)
                }
                if failed, let error = model.error {
                    HStack {
                        Text("资料加载失败：\(error.message)").font(.caption).foregroundStyle(AppTheme.error)
                        Spacer()
                        Button("重试") { model.reload() }.font(.caption)
                    }
                }
            }
            .foregroundStyle(AppTheme.foreground)
            .padding(16)
            Divider().overlay(AppTheme.outline)
        }
    }
}

/// Following, follower and status counts. Display only: follower lists aren't
/// part of maxbo.
private struct ProfileCounts: View {
    let profile: UserProfile

    var body: some View {
        let counts = [("关注", profile.friendsCount), ("粉丝", profile.followersCount), ("微博", profile.statusesCount)]
            .compactMap { label, count in count.map { (label, $0) } }
        HStack(spacing: 16) {
            ForEach(counts, id: \.0) { label, count in
                Text("\(Text(formatCount(count)).fontWeight(.semibold).foregroundStyle(AppTheme.foreground)) \(label)")
                    .foregroundStyle(AppTheme.secondary)
            }
        }
        .font(.subheadline)
    }
}
