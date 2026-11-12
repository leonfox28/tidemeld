import Foundation

/// Captures the source account once; current-account changes cannot redirect a pending action.
@MainActor final class WeiboProfileControls {
    let graph: AppGraph
    let account: SocialAccount?
    init(_ graph: AppGraph) {
        self.graph = graph
        account = graph.session.state.uid.flatMap { graph.accounts.find("weibo:\($0)") }
    }
    var isCurrent: Bool {
        guard let account else { return false }
        return graph.session.state.uid == account.session.account.uid
            && graph.accounts.find(account.id).map { $0.revision == account.revision && !$0.expired } == true
    }
    private func key(_ uid: String) -> String {
        "\(account?.id ?? "guest"):\(account?.revision ?? -1):\(uid)"
    }
    var readStamp: Int { graph.profileRelationships.readStamp }
    func ingest(_ profile: UserProfile, started: Int) {
        guard isCurrent else { return }
        graph.profileRelationships.ingest(key(profile.user.id), value: profile.relationship, started: started)
        syncBlock(profile.user.id)
    }
    func state(_ profile: UserProfile) -> ProfileRelationshipState {
        graph.profileRelationships.state(key(profile.user.id), fallback: profile.relationship)
    }
    private func syncBlock(_ uid: String) {
        guard isCurrent, let account, let blocked = graph.profileRelationships.loadedState(key(uid))?.value.blocking else { return }
        graph.settings.recordBlock(owner: account.id, user: uid, blocked: blocked)
    }
    func blockUser(_ uid: String) async throws {
        guard isCurrent else { throw WeiboError.sessionExpired }
        let started = readStamp
        let profile = try await graph.api.fetchProfile(uid: uid)
        guard isCurrent else { throw WeiboError.sessionExpired }
        ingest(profile, started: started)
        if state(profile).value.blocking == true { return }
        guard let action = actions(profile)?.more.first(where: { $0.id == "block" }) else {
            throw AppFailure(message: "关系状态已变化，请重新打开用户主页")
        }
        try await action.perform()
    }
    func actions(_ profile: UserProfile) -> ProfileActions? {
        guard isCurrent, profile.user.id != account?.session.account.uid else { return nil }
        let state = state(profile)
        let uid = profile.user.id
        let current: @Sendable () async -> Bool = { await MainActor.run { self.isCurrent } }
        let change = { (following: Bool?, blocking: Bool?) in
            try await self.graph.profileRelationships.perform(
                self.key(uid), expected: state.value, isCurrent: { self.isCurrent }
            ) {
                try await self.graph.api.changeUserRelationship(
                    uid: uid, following: following, blocking: blocking, isCurrent: current
                ).relationship
            }
            self.syncBlock(uid)
        }
        var result = profileActions(
            name: profile.user.screenName, state: state,
            follow: { try await change($0, nil) }, block: { try await change(nil, $0) }, reposts: nil,
            refresh: {
                guard self.isCurrent else { throw WeiboError.sessionExpired }
                let started = self.readStamp
                let profile = try await self.graph.api.fetchProfile(uid: uid)
                guard self.isCurrent else { throw WeiboError.sessionExpired }
                self.ingest(profile, started: started)
            })
        result.more.append(graph.weiboReportAction(id: uid, kind: .user))
        return result
    }
}

extension UserProfile {
    fileprivate var relationship: ProfileRelationship {
        ProfileRelationship(following: following, followsYou: followsMe, blocking: blocking)
    }
}
