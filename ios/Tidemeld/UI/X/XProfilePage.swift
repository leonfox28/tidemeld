import Observation
import SwiftUI

@MainActor @Observable final class XProfileModel {
    let target: XProfileUser
    private(set) var profile: XUserProfile?
    private(set) var error: AppFailure?
    private(set) var posts: PagedList<XPost>?
    @ObservationIgnored private var fetchProfile: (() async throws -> XUserProfile)?
    private(set) var relationshipFailed = false
    @ObservationIgnored private var fetchRelationship: ((String) async throws -> Void)?
    @ObservationIgnored private var makePosts: ((String) -> PagedList<XPost>)?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(target: XProfileUser) { self.target = target }

    func start(_ interactions: XInteractions, owner: String) {
        guard fetchProfile == nil else { return }
        fetchProfile = { [weak self, target] in
            try await interactions.profile(owner, user: self?.profile?.user ?? target)
        }
        fetchRelationship = { try await interactions.refreshRelationship(owner, uid: $0) }
        makePosts = { uid in
            PagedList(fetch: { try await interactions.userPosts(owner, uid: uid, cursor: $0) }, id: \.id)
        }
        if let uid = target.id { startPosts(uid) }
        reload()
    }

    func reload() {
        generation += 1
        let ticket = generation
        loading?.cancel()
        error = nil
        loading = Task {
            do { try await loadProfile(ticket) } catch {
                if ticket == generation, !AppFailure.of(error).isCancelled {
                    self.error = AppFailure.of(error)
                }
            }
        }
    }

    private func loadProfile(_ ticket: Int) async throws {
        guard let fetchProfile else { return }
        let result = try await fetchProfile()
        try Task.checkCancellation()
        guard ticket == generation else { return }
        profile = result
        error = nil
        if let uid = result.user.id {
            if posts == nil { startPosts(uid) }
            do {
                try await fetchRelationship?(uid)
                relationshipFailed = false
            } catch { if ticket == generation { relationshipFailed = true } }
        }
    }

    private func startPosts(_ uid: String) {
        posts = makePosts?(uid)
        posts?.start()
    }

    func refresh() async throws {
        generation += 1
        let ticket = generation
        loading?.cancel()
        async let details: Void = loadProfile(ticket)
        async let content: Void? = posts?.refresh()
        // Each successful read can update independently; one failure must not cancel the other.
        var failure: Error?
        do { try await details } catch { failure = error }
        do { _ = try await content } catch { failure = failure ?? error }
        if let failure { throw failure }
    }
}

struct XProfilePage: View {
    let owner: String
    @State private var model: XProfileModel
    @Environment(AppGraph.self) private var graph

    init(owner: String, user: XProfileUser) {
        self.owner = owner
        _model = State(wrappedValue: XProfileModel(target: user))
    }

    var body: some View {
        let p = model.profile
        let user = p?.user ?? model.target
        let loading = p == nil && model.error == nil
        let relationship = user.id.flatMap {
            graph.xInteractions.relationships.loadedState(graph.xInteractions.key(owner, $0))
        }
        let relation =
            relationship != nil
            ? relationship?.value.label
            : p.map {
                $0.followed && $0.followsYou ? "互相关注" : $0.followed ? "已关注" : $0.followsYou ? "关注了你" : nil
            } ?? nil
        let counts = [("关注", p?.following), ("粉丝", p?.followers), ("帖子", p?.posts)]
            .compactMap { label, value in
                (value ?? (loading ? 0 : nil)).map { ProfileCount(label: label, value: $0) }
            }
        SocialProfilePage(
            title: user.name ?? user.handle.map { "@\($0)" } ?? "用户主页",
            profile: ProfilePresentation(
                name: user.name ?? user.handle, avatarURL: user.avatar, coverURL: p?.coverURL,
                counts: counts, relation: relation, description: p?.description, loading: loading,
                failure: model.error.map { "资料加载失败：\($0.message)" }),
            posts: model.posts, failure: model.error,
            emptyText: p?.protected == true ? "暂无可查看的帖子" : "还没有帖子",
            retry: { model.reload() }, refresh: { try await model.refresh() },
            actions: graph.xInteractions.relationshipActions(
                owner, user: user, failed: model.relationshipFailed),
            badge: {
                if p?.verified == true {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(AppTheme.primary)
                        .accessibilityLabel("已认证")
                }
            },
            details: {
                VStack(alignment: .leading, spacing: 4) {
                    if let handle = user.handle { Text("@\(handle)") }
                    if let location = p?.location, !location.isEmpty { Text(location) }
                    if p?.protected == true { Label("帖子已受保护", systemImage: "lock") }
                }.font(.caption).foregroundStyle(AppTheme.secondary)
            },
            row: { XPostCard(post: $0, owner: owner, profileHandle: user.handle) }
        )
        .onAppear { model.start(graph.xInteractions, owner: owner) }
    }
}
