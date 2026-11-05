import Foundation
import Observation

enum FeedPost: Sendable, Identifiable {
    case weibo(owner: String, Status)
    case x(owner: String, XPost)
    var owner: String {
        switch self {
        case .weibo(let owner, _), .x(let owner, _): owner
        }
    }
    var id: String {
        switch self {
        case .weibo(_, let post): "weibo:\(post.id)"
        case .x(_, let post): "x:\(post.id)"
        }
    }
    var date: Date? {
        switch self {
        case .weibo(_, let post): post.createdAt
        case .x(_, let post): post.createdAt
        }
    }
}

@MainActor @Observable final class SocialFeedController {
    private(set) var items: [FeedPost] = []
    private(set) var errors: [String: String] = [:]
    private(set) var loading = false
    private(set) var hasMore = false
    @ObservationIgnored private let accounts: AccountManager
    // Account lookup and provider selection touch main-actor state before/after network awaits.
    @ObservationIgnored private let fetch: @MainActor (SocialAccount, String?) async throws -> Paged<FeedPost>
    private struct Source {
        let revision: Int
        var items: [FeedPost] = []
        var cursor: String?
        var started = false
        var error: String?
    }
    @ObservationIgnored private var sources: [String: Source] = [:]
    @ObservationIgnored private var selection: FeedSelection = .all
    @ObservationIgnored private var fingerprint = ""
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    init(accounts: AccountManager, fetch: @escaping @MainActor (SocialAccount, String?) async throws -> Paged<FeedPost>)
    {
        self.accounts = accounts
        self.fetch = fetch
    }
    func select(_ value: FeedSelection) {
        let next = accounts.accounts.map { "\($0.id):\($0.revision)" }.joined(separator: ",")
        if selection != value || fingerprint != next {
            generation += 1
            task?.cancel()
            task = nil
            selection = value
            fingerprint = next
            sources = sources.filter { key, value in accounts.find(key)?.revision == value.revision }
        }
        publish()
        run()
    }
    func refresh() { run(refresh: true) }
    func loadMore() { run(more: true) }
    func retry() { run(retry: true) }
    func waitForIdle() async { await task?.value }
    private var selected: [SocialAccount] {
        accounts.accounts.filter { selection.platform == nil || $0.platform == selection.platform }
    }

    private func run(refresh: Bool = false, more: Bool = false, retry: Bool = false) {
        guard task == nil else { return }
        let targets = selected.filter { account in
            let source = sources[account.id]
            return !account.expired
                && (refresh || source == nil || source?.started == false || (retry && source?.error != nil)
                    || (more && source?.cursor != nil && source?.error == nil))
        }
        guard !targets.isEmpty else {
            publish()
            return
        }
        let ticket = generation
        loading = true
        task = Task {
            for account in targets {
                if Task.isCancelled || ticket != generation { break }
                let old = sources[account.id]
                let cursor = refresh || retry ? nil : old?.cursor
                do {
                    let page = try await fetch(account, cursor)
                    guard ticket == generation, accounts.find(account.id)?.revision == account.revision else {
                        continue
                    }
                    let all = (cursor == nil ? [] : old?.items ?? []) + page.items
                    var seen: Set<String> = []
                    sources[account.id] = Source(
                        revision: account.revision, items: all.filter { seen.insert($0.id).inserted },
                        cursor: page.nextCursor == cursor ? nil : page.nextCursor, started: true)
                } catch {
                    guard ticket == generation, accounts.find(account.id)?.revision == account.revision,
                        !WeiboError.isCancellation(error)
                    else { continue }
                    var source = old ?? Source(revision: account.revision)
                    source.started = true
                    source.error = loadErrorMessage(error)
                    sources[account.id] = source
                    if error as? WeiboError == .sessionExpired { accounts.expire(account.id) }
                }
                publish(loading: true)
            }
            if ticket == generation {
                task = nil
                publish()
            }
        }
    }
    func ownPostChanged(owner: String, post: Status, added: Bool) {
        if added, var source = sources[owner] {
            source.items = [.weibo(owner: owner, post)] + source.items.filter { $0.id != "weibo:\(post.id)" }
            sources[owner] = source
        } else if !added {
            for key in Array(sources.keys) { sources[key]?.items.removeAll { $0.id == "weibo:\(post.id)" } }
        }
        publish(loading: loading)
    }
    private func publish(loading: Bool = false) {
        var seen: Set<String> = []
        items = selected.filter { !$0.expired }.flatMap { sources[$0.id]?.items ?? [] }.enumerated().sorted {
            let lhs = $0.element.date ?? .distantPast
            let rhs = $1.element.date ?? .distantPast
            if lhs != rhs { return lhs > rhs }
            return $0.offset < $1.offset
        }.map(\.element).filter { seen.insert($0.id).inserted }
        errors = Dictionary(
            uniqueKeysWithValues: selected.compactMap { account in
                let error = account.expired ? "登录已过期，请重新登录" : sources[account.id]?.error
                return error.map { (account.id, "\(account.platform.label) · \(account.name)：\($0)") }
            })
        hasMore = selected.contains {
            !$0.expired && sources[$0.id]?.cursor != nil && sources[$0.id]?.error == nil
        }
        self.loading = loading
    }
}
