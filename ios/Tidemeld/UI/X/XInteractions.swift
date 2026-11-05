import Foundation
import Observation

struct XInteractionState {
    var metrics: XMetrics
    var busy = false
    var version = 0
}

enum XWrite { case like, repost, reply, quote }

/// Shared by feed and detail cards, scoped by account, login generation and original post ID.
@MainActor @Observable final class XInteractions {
    private var states: [String: XInteractionState] = [:]
    @ObservationIgnored private let accounts: AccountManager
    @ObservationIgnored private let api: XWebAPI?
    @ObservationIgnored let drafts = CommentDrafts()
    @ObservationIgnored private(set) var readStamp = 0
    init(accounts: AccountManager, api: XWebAPI?) {
        self.accounts = accounts
        self.api = api
    }

    func key(_ owner: String, _ id: String) -> String {
        "\(owner):\(accounts.find(owner)?.revision ?? -1):\(id)"
    }
    func state(_ owner: String, _ post: XPost) -> XInteractionState {
        states[key(owner, post.originalID)] ?? XInteractionState(metrics: post.metrics)
    }

    func ingest(_ account: SocialAccount, posts: [XPost], started: Int) {
        guard accounts.find(account.id)?.revision == account.revision else { return }
        for post in posts {
            let key = key(account.id, post.originalID)
            let old = states[key]
            if old?.busy != true, (old?.version ?? 0) <= started {
                states[key] = XInteractionState(metrics: post.metrics, version: old?.version ?? 0)
            }
        }
    }
    private func account(_ owner: String) throws -> SocialAccount {
        guard let account = accounts.find(owner), account.platform == .x, !account.expired else {
            throw WeiboError.sessionExpired
        }
        return account
    }
    private func service() throws -> XWebAPI {
        guard let api else { throw WeiboError.api("X 接口配置不可用") }
        return api
    }
    private func cookies(_ account: SocialAccount) -> @Sendable (Cookies) async -> Void {
        { [weak accounts] value in
            await MainActor.run {
                if accounts?.find(account.id)?.revision == account.revision {
                    accounts?.updateCookies(account.id, cookies: value)
                }
            }
        }
    }
    func conversation(_ owner: String, id: String, cursor: String?) async throws -> XConversation {
        let account = try account(owner)
        let started = readStamp
        do {
            let page = try await service().conversation(
                account.session, id: id, cursor: cursor, onCookies: cookies(account))
            guard accounts.find(owner)?.revision == account.revision else {
                throw WeiboError.sessionExpired
            }
            ingest(
                account, posts: page.ancestors + (page.post.map { [$0] } ?? []) + page.replies.items,
                started: started)
            return page
        } catch {
            if error as? WeiboError == .sessionExpired,
                accounts.find(owner)?.revision == account.revision
            {
                accounts.expire(owner)
            }
            throw error
        }
    }

    @discardableResult func write(_ owner: String, post: XPost, action: XWrite, text: String = "")
        async throws -> String?
    {
        let account = try account(owner)
        let isCurrent: @Sendable () async -> Bool = { [accounts] in
            await MainActor.run {
                accounts.find(owner).map { $0.revision == account.revision && !$0.expired } == true
            }
        }
        let key = key(owner, post.originalID)
        let before = state(owner, post)
        guard !before.busy else { throw WeiboError.api("正在处理，请稍候") }
        readStamp += 1
        states[key] = XInteractionState(metrics: before.metrics, busy: true, version: readStamp)
        var metrics = before.metrics
        do {
            let api = try service()
            var id: String?
            switch action {
            case .like:
                try await api.like(
                    account.session, id: post.originalID, liked: !metrics.liked,
                    onCookies: cookies(account),
                    isCurrent: isCurrent)
                metrics.likes = max(0, metrics.likes + (metrics.liked ? -1 : 1))
                metrics.liked.toggle()
            case .repost:
                try await api.repost(
                    account.session, id: post.originalID, reposted: !metrics.reposted,
                    onCookies: cookies(account), isCurrent: isCurrent)
                metrics.reposts = max(0, metrics.reposts + (metrics.reposted ? -1 : 1))
                metrics.reposted.toggle()
            case .reply, .quote:
                id = try await api.publish(
                    account.session, post: post, text: text, quote: action == .quote,
                    onCookies: cookies(account), isCurrent: isCurrent)
                if action == .reply { metrics.replies += 1 }
            }
            guard accounts.find(owner)?.revision == account.revision else {
                throw WeiboError.api("账号已变更，请刷新后检查操作结果")
            }
            readStamp += 1
            states[key] = XInteractionState(metrics: metrics, version: readStamp)
            return id
        } catch {
            if error as? WeiboError == .sessionExpired,
                accounts.find(owner)?.revision == account.revision
            {
                accounts.expire(owner)
            }
            readStamp += 1
            states[key] = XInteractionState(metrics: before.metrics, version: readStamp)
            throw error
        }
    }
}
