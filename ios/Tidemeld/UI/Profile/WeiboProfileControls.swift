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
    }
    func state(_ profile: UserProfile) -> ProfileRelationshipState {
        graph.profileRelationships.state(key(profile.user.id), fallback: profile.relationship)
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
        }
        return profileActions(
            name: profile.user.screenName, state: state,
            follow: { try await change($0, nil) }, block: { try await change(nil, $0) }, reposts: nil,
            refresh: {
                guard self.isCurrent else { throw WeiboError.sessionExpired }
                let started = self.readStamp
                let profile = try await self.graph.api.fetchProfile(uid: uid)
                guard self.isCurrent else { throw WeiboError.sessionExpired }
                self.ingest(profile, started: started)
            })
    }
}

extension UserProfile {
    fileprivate var relationship: ProfileRelationship {
        ProfileRelationship(following: following, followsYou: followsMe, blocking: blocking)
    }
}
