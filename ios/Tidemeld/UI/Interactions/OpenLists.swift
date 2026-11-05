import Foundation

/// The lists open on some page, by what they list, so a change the user makes
/// shows in each of them. Pages register their lists while open; only lists
/// already open change: nothing loads for it (PLAN §2).
@MainActor
final class OpenLists {
    private let timeline: PagedList<Status>

    /// The posts of a user, by uid.
    let userStatuses = Registry<String, PagedList<Status>>()
    /// The reposts of a status, by its id.
    let reposts = Registry<String, PagedList<Status>>()
    /// The comments on a status, in any order, by its id.
    let comments = Registry<String, PagedList<Comment>>()

    init(timeline: PagedList<Status>) {
        self.timeline = timeline
    }

    /// Puts [status], which the user just posted, atop the timeline and their
    /// own posts.
    func prependOwn(_ status: Status) {
        timeline.prepend(status)
        if let uid = status.user?.id { userStatuses.forEach(uid) { $0.prepend(status) } }
    }

    /// Takes [status], which the user just deleted, out of the timeline and
    /// their own posts.
    func removeOwn(_ status: Status) {
        timeline.remove(status.id)
        if let uid = status.user?.id { userStatuses.forEach(uid) { $0.remove(status.id) } }
    }

    /// Lists by key, held weakly: a list is gone with the page that showed it.
    final class Registry<Key: Hashable, List: AnyObject> {
        private var open: [Key: [Weak<List>]] = [:]

        func add(_ key: Key, _ list: List) {
            var lists = open[key, default: []].filter { $0.value != nil }
            if !lists.contains(where: { $0.value === list }) { lists.append(Weak(list)) }
            open[key] = lists
        }

        func forEach(_ key: Key, _ action: (List) -> Void) {
            for list in open[key, default: []].compactMap(\.value) { action(list) }
        }
    }

    private struct Weak<T: AnyObject> {
        weak var value: T?
        init(_ value: T) { self.value = value }
    }
}
