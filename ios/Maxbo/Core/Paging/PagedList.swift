import Foundation
import Observation

struct PagedState<T> {
    var items: [T] = []
    /// Where the next page starts; nil once the end is reached.
    var nextCursor: String? = nil
    /// The size of the whole list, when Weibo says.
    var total: Int? = nil
    var loadingMore = false
    /// Why the last attempt to load more failed; cleared by the next attempt.
    var loadMoreError: WeiboError? = nil

    var hasMore: Bool { nextCursor != nil }

    /// This list with [items] in place of its own, [total] changing by
    /// [totalChange].
    func with(items: [T], totalChange: Int = 0) -> PagedState {
        var copy = self
        copy.items = items
        copy.total = total.map { max(0, $0 + totalChange) }
        return copy
    }
}

/// A list's first page: loading, failed, or loaded.
enum ListLoad<T> {
    case loading
    case failed(WeiboError)
    case ready(PagedState<T>)

    var list: PagedState<T>? {
        if case .ready(let list) = self { return list }
        return nil
    }
}

/// A list loaded a page at a time: the first page once [start]ed, as the list
/// is first shown, the next on [loadMore] as the user scrolls. Nothing loads on
/// its own (PLAN §2).
@MainActor @Observable
final class PagedList<T: Sendable> {
    private(set) var state: ListLoad<T> = .loading

    /// Fetches the page at a cursor, or the first page when nil.
    @ObservationIgnored private let fetchPage: (String?) async throws -> Paged<T>
    /// Identifies an item, to drop repeats when pages overlap.
    @ObservationIgnored let idOf: (T) -> String

    /// Bumped whenever the list is replaced, so pages loaded for an older one
    /// are dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var firstPage: Task<Void, Never>?

    init(fetch: @escaping (String?) async throws -> Paged<T>, id: @escaping (T) -> String) {
        fetchPage = fetch
        idOf = id
    }

    var items: [T] { state.list?.items ?? [] }

    /// Loads the first page, unless it has been.
    func start() {
        if firstPage == nil { reload() }
    }

    /// Loads the first page again, showing it loading meanwhile; after a
    /// failure, say.
    func reload() {
        generation += 1
        let generation = generation
        firstPage?.cancel()
        state = .loading
        firstPage = Task {
            let loaded: ListLoad<T>
            do {
                loaded = .ready(Self.state(of: try await fetchPage(nil)))
            } catch {
                loaded = .failed(WeiboError.of(error))
            }
            if generation == self.generation { state = loaded }
        }
    }

    /// Forgets the list, as for another account; the next [start] loads it
    /// afresh.
    func reset(to load: ListLoad<T> = .loading) {
        generation += 1
        firstPage?.cancel()
        firstPage = nil
        state = load
    }

    /// Replaces the list with its first page, keeping it meanwhile.
    ///
    /// Throws on failure, the list staying as it was, for the caller to report.
    func refresh() async throws {
        let generation = generation
        let page = Self.state(of: try await fetchPage(nil))
        guard generation == self.generation else { return }
        self.generation += 1
        firstPage = firstPage ?? Task {}
        state = .ready(page)
    }

    /// Appends the next page. Failures are kept in `loadMoreError` rather than
    /// thrown.
    func loadMore() async {
        guard var current = state.list, !current.loadingMore, current.hasMore else { return }
        current.loadingMore = true
        current.loadMoreError = nil
        state = .ready(current)

        let generation = generation
        var page: Paged<T>?
        var error: WeiboError?
        do {
            page = try await fetchPage(current.nextCursor)
        } catch let e {
            error = WeiboError.of(e)
        }
        // Drop the result if a refresh replaced the list meanwhile; otherwise
        // add it to the list as it is now, which the user may have changed.
        guard generation == self.generation, var latest = state.list else { return }
        latest.loadingMore = false
        guard let page else {
            latest.loadMoreError = error
            state = .ready(latest)
            return
        }
        var seen = Set(latest.items.map(idOf))
        latest.items += page.items.filter { seen.insert(idOf($0)).inserted }
        latest.nextCursor = page.nextCursor
        latest.total = page.total ?? latest.total
        latest.loadMoreError = nil
        state = .ready(latest)
    }

    /// Puts [item], which the user just added, atop the list.
    func prepend(_ item: T) {
        edit { list in
            let id = idOf(item)
            return list.with(items: [item] + list.items.filter { idOf($0) != id }, totalChange: 1)
        }
    }

    /// Takes the item [id], which the user just deleted, out of the list.
    func remove(_ id: String) {
        edit { list in
            let items = list.items.filter { idOf($0) != id }
            return items.count == list.items.count ? list : list.with(items: items, totalChange: -1)
        }
    }

    /// Replaces the item [id] with what [change] makes of it.
    func replace(_ id: String, _ change: (T) -> T) {
        edit { list in list.with(items: list.items.map { idOf($0) == id ? change($0) : $0 }) }
    }

    // Lists still loading their first page are left alone: that page will be
    // current anyway.
    private func edit(_ change: (PagedState<T>) -> PagedState<T>) {
        guard let list = state.list else { return }
        state = .ready(change(list))
    }

    private static func state(of page: Paged<T>) -> PagedState<T> {
        PagedState(items: page.items, nextCursor: page.nextCursor, total: page.total)
    }
}
