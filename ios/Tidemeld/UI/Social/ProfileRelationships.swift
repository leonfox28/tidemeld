import Foundation
import Observation

/// Presentation state, supplied by a platform adapter. Nil capabilities stay out of the menu.
struct ProfileRelationship: Equatable {
    var following: Bool
    var followsYou = false
    var requested = false
    var blocking: Bool? = nil
    var showsReposts: Bool? = nil

    var label: String? {
        if blocking == true { return "已拉黑" }
        if requested { return "已申请关注" }
        return following && followsYou ? "互相关注" : following ? "已关注" : followsYou ? "关注了你" : nil
    }
}

struct ProfileRelationshipState {
    var value: ProfileRelationship
    var busy = false
    var needsRefresh = false
    var version = 0
}

/// Shared across open pages, keyed by platform, source account, login revision and target user.
@MainActor @Observable final class ProfileRelationships {
    private var states: [String: ProfileRelationshipState] = [:]
    private(set) var readStamp = 0

    func loadedState(_ key: String) -> ProfileRelationshipState? { states[key] }

    func state(_ key: String, fallback: ProfileRelationship) -> ProfileRelationshipState {
        states[key] ?? ProfileRelationshipState(value: fallback)
    }

    func ingest(_ key: String, value: ProfileRelationship, started: Int) {
        let old = states[key]
        guard old?.busy != true, (old?.version ?? 0) <= started else { return }
        states[key] = ProfileRelationshipState(value: value, version: old?.version ?? 0)
    }

    func perform(
        _ key: String, expected: ProfileRelationship, isCurrent: () -> Bool,
        change: () async throws -> ProfileRelationship
    ) async throws {
        let before = state(key, fallback: expected)
        guard isCurrent() else { throw AppFailure(message: "账号已变更，请重新打开主页") }
        guard !before.busy else { return }
        guard !before.needsRefresh, before.value == expected else {
            throw AppFailure(message: "关系状态已变化，请刷新后再操作")
        }
        readStamp += 1
        states[key] = ProfileRelationshipState(value: before.value, busy: true, version: readStamp)
        do {
            let value = try await change()
            guard isCurrent() else { throw AppFailure(message: "账号已变更，请刷新后检查操作结果") }
            readStamp += 1
            states[key] = ProfileRelationshipState(value: value, version: readStamp)
        } catch {
            readStamp += 1
            states[key] = ProfileRelationshipState(
                value: before.value, needsRefresh: true, version: readStamp)
            throw error
        }
    }
}
