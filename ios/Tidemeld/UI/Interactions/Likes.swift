import Foundation
import Observation
import SwiftUI

enum LikeKind: Sendable, Hashable {
    case status, comment
}

/// A status or comment, which can be liked.
struct LikeTarget: Sendable, Hashable {
    let kind: LikeKind
    let id: String
}

/// Whether something is liked by the user, and by how many.
struct LikeState: Sendable, Hashable {
    let liked: Bool
    let count: Int

    var toggled: LikeState { LikeState(liked: !liked, count: max(0, count + (liked ? -1 : 1))) }
}

extension Status {
    /// The like of this status as loaded.
    var like: LikeState { LikeState(liked: liked, count: likesCount) }
}

extension Comment {
    var like: LikeState { LikeState(liked: liked, count: likesCount) }
}

/// A like the user changed in the app: [current], over what the loaded data
/// said ([base]) when they did. [pending] while Weibo has yet to confirm it.
struct LikeChange: Sendable, Hashable {
    let base: LikeState
    let current: LikeState
    var pending = false
}

/// The likes the user changed, shared by every list and page showing the same
/// status or comment. Another account has likes of its own, so signing in as
/// one starts over.
@MainActor @Observable
final class LikesController {
    private(set) var changes: [LikeTarget: LikeChange] = [:]
    @ObservationIgnored private let api: WeiboAPI

    init(api: WeiboAPI, session: SessionController) {
        self.api = api
        session.onUidChange { [weak self] _ in self?.changes = [:] }
    }

    /// Likes [target], or takes the like back, when the loaded data says it is
    /// [loaded].
    ///
    /// The change shows at once and is taken back if Weibo refuses it, with the
    /// error rethrown. Does nothing while a change of [target] is on its way.
    func toggle(_ target: LikeTarget, loaded: LikeState) async throws {
        let previous = changes[target]
        if previous?.pending == true { return }
        let next = Self.resolve(previous, loaded: loaded).toggled
        changes[target] = LikeChange(base: loaded, current: next, pending: true)
        do {
            switch target.kind {
            case .status: try await api.likeStatus(target.id, liked: next.liked)
            case .comment: try await api.likeComment(target.id, liked: next.liked)
            }
            changes[target] = LikeChange(base: loaded, current: next)
        } catch {
            changes[target] = previous
            throw error
        }
    }

    /// What to show for something that the loaded data says is [loaded], and
    /// whether a change is on its way.
    func shown(_ target: LikeTarget, loaded: LikeState) -> (like: LikeState, pending: Bool) {
        let change = changes[target]
        return (Self.resolve(change, loaded: loaded), change?.pending == true)
    }

    /// A change applies only over the data it was made on: data loaded since
    /// already has it, and is newer.
    static func resolve(_ change: LikeChange?, loaded: LikeState) -> LikeState {
        if let change, change.base == loaded { change.current } else { loaded }
    }
}
