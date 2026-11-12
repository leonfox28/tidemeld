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
    let relationships: ProfileRelationships
    private let onBlockChanged: (String, String, Bool) -> Void
    init(accounts: AccountManager, api: XWebAPI?, relationships: ProfileRelationships? = nil,
         onBlockChanged: @escaping (String, String, Bool) -> Void = { _, _, _ in }) {
        self.onBlockChanged = onBlockChanged
        self.relationships = relationships ?? ProfileRelationships()
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

    func profile(_ owner: String, user: XProfileUser) async throws -> XUserProfile {
        try await read(owner) { account, api in
            try await api.profile(account.session, user: user, onCookies: self.cookies(account))
        }
    }

    func refreshRelationship(_ owner: String, uid: String, revision: Int? = nil) async throws {
        let account = try account(owner)
        if let revision, revision != account.revision { throw WeiboError.sessionExpired }
        guard uid != account.session.account.uid else { return }
        let started = relationships.readStamp
        let result = try await read(owner) { account, api in
            try await api.relationship(account.session, uid: uid, onCookies: self.cookies(account))
        }
        relationships.ingest(key(owner, uid), value: result.presentation, started: started)
        syncBlock(owner, uid: uid)
    }

    private func syncBlock(_ owner: String, uid: String) {
        if let blocked = relationships.loadedState(key(owner, uid))?.value.blocking {
            onBlockChanged(owner, uid, blocked)
        }
    }

    func blockUser(_ owner: String, user: XProfileUser, revision: Int) async throws {
        guard let uid = user.id else { throw AppFailure(message: "用户资料不可用") }
        try await refreshRelationship(owner, uid: uid, revision: revision)
        guard try account(owner).revision == revision else { throw WeiboError.sessionExpired }
        if relationships.loadedState(key(owner, uid))?.value.blocking == true { return }
        guard let action = relationshipActions(owner, user: user, failed: false)?.more.first(where: { $0.id == "block" }) else {
            throw AppFailure(message: "关系状态已变化，请重新打开用户主页")
        }
        try await action.perform()
    }

    func relationshipActions(_ owner: String, user: XProfileUser, failed: Bool) -> ProfileActions? {
        guard let uid = user.id, let account = try? account(owner), uid != account.session.account.uid else {
            return nil
        }
        let key = key(owner, uid)
        let refresh = { try await self.refreshRelationship(owner, uid: uid, revision: account.revision) }
        guard let state = relationships.loadedState(key) else {
            return failed
                ? ProfileActions(primary: ProfileAction(id: "refresh", title: "刷新状态", perform: refresh))
                : ProfileActions(busy: true)
        }
        let change = { (action: XUserAction) in
            let current = {
                self.accounts.find(owner).map { $0.revision == account.revision && !$0.expired } == true
            }
            let beforeSend: @Sendable () async -> Bool = { [accounts = self.accounts] in
                await MainActor.run {
                    accounts.find(owner).map { $0.revision == account.revision && !$0.expired } == true
                }
            }
            try await self.relationships.perform(key, expected: state.value, isCurrent: current) {
                do {
                    return try await self.service().changeRelationship(
                        account.session, uid: uid, action: action,
                        onCookies: self.cookies(account), isCurrent: beforeSend
                    ).presentation
                } catch {
                    if error as? WeiboError == .sessionExpired, current() { self.accounts.expire(owner) }
                    throw error
                }
            }
            self.syncBlock(owner, uid: uid)
        }
        return profileActions(
            name: user.name ?? user.handle ?? "此用户", state: state,
            follow: { try await change(.follow($0)) }, block: { try await change(.block($0)) },
            reposts: { try await change(.reposts($0)) }, refresh: refresh)
    }

    func userPosts(_ owner: String, uid: String, cursor: String?) async throws -> Paged<XPost> {
        let started = readStamp
        return try await read(owner) { account, api in
            let page = try await api.userPosts(
                account.session, uid: uid, cursor: cursor, onCookies: self.cookies(account))
            self.ingest(account, posts: page.items, started: started)
            return page
        }
    }

    private func read<T>(_ owner: String, action: (SocialAccount, XWebAPI) async throws -> T) async throws
        -> T
    {
        let account = try account(owner)
        do {
            let result = try await action(account, service())
            guard accounts.find(owner)?.revision == account.revision,
                accounts.find(owner)?.expired == false
            else { throw WeiboError.sessionExpired }
            return result
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

extension XUserRelationship {
    fileprivate var presentation: ProfileRelationship {
        ProfileRelationship(
            following: following, followsYou: followsYou, requested: requested, blocking: blocking,
            showsReposts: showsReposts)
    }
}
