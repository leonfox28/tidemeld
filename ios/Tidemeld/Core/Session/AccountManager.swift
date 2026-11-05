import Foundation
import Observation
import Security

enum SocialPlatform: String, Codable, CaseIterable, Sendable, Identifiable {
    case weibo, x
    var id: String { rawValue }
    var label: String { self == .weibo ? "微博" : "X" }
    var domains: [String] {
        self == .weibo ? ["weibo.com", "weibo.cn", "sina.com.cn"] : ["x.com", "twitter.com"]
    }
}

enum FeedSelection: String, CaseIterable, Sendable, Identifiable {
    case all, weibo, x
    var id: String { rawValue }
    var label: String { self == .all ? "聚合" : self == .weibo ? "微博" : "X" }
    var platform: SocialPlatform? { SocialPlatform(rawValue: rawValue) }
}

struct SocialAccount: Codable, Sendable, Equatable, Identifiable {
    let platform: SocialPlatform
    var session: StoredSession
    var expired = false
    var revision = 0
    var id: String { "\(platform.rawValue):\(session.account.uid)" }
    var name: String { session.account.screenName ?? session.account.uid }
}

@MainActor protocol AccountStorage {
    func load() -> [SocialAccount]
    func save(_ accounts: [SocialAccount]) throws
}

@MainActor final class MemoryAccountStorage: AccountStorage {
    var accounts: [SocialAccount] = []
    func load() -> [SocialAccount] { accounts }
    func save(_ accounts: [SocialAccount]) { self.accounts = accounts }
}

@MainActor final class KeychainAccountStorage: AccountStorage {
    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "tidemeld") + ".accounts",
            kSecAttrAccount as String: "accounts",
        ]
    }
    func load() -> [SocialAccount] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return [] }
        return (try? JSONDecoder().decode([SocialAccount].self, from: data)) ?? []
    }
    func save(_ accounts: [SocialAccount]) throws {
        let data = try JSONEncoder().encode(accounts)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(update) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw WeiboError.api("账号保存失败，请重试") }
    }
    func dropLeftovers(defaults: UserDefaults = .standard) {
        let marker = "accounts.installed"
        if !defaults.bool(forKey: marker) {
            SecItemDelete(query as CFDictionary)
            defaults.set(true, forKey: marker)
        }
    }
}

@MainActor @Observable final class AccountManager {
    private(set) var accounts: [SocialAccount]
    @ObservationIgnored private let storage: AccountStorage
    @ObservationIgnored private let weibo: SessionController
    @ObservationIgnored private let web: WebCookies
    @ObservationIgnored private var changing = false
    @ObservationIgnored private var revision = 0

    init(storage: AccountStorage, weibo: SessionController, web: WebCookies) {
        self.storage = storage
        self.weibo = weibo
        self.web = web
        accounts = storage.load()
        revision = accounts.map(\.revision).max() ?? 0
        weibo.onLogout = { [weak self] uid in try? await self?.remove("weibo:\(uid)") }
        weibo.onExpired = { [weak self] uid in self?.expire("weibo:\(uid)") }
        if let uid = weibo.state.uid, let saved = find("weibo:\(uid)") {
            changing = true
            weibo.activate(saved.expired ? nil : saved.session)
            changing = false
        } else if weibo.state.uid != nil {
            rememberWeibo()
        } else if let first = accounts.first(where: { $0.platform == .weibo && !$0.expired }) {
            _ = useWeibo(first.id)
        }
        weibo.onUidChange { [weak self] _ in self?.rememberWeibo() }
        weibo.jar.addListener { [weak self] in Task { @MainActor in self?.rememberWeibo() } }
    }
    func find(_ key: String) -> SocialAccount? { accounts.first { $0.id == key } }
    private func rememberWeibo() {
        guard !changing, let account = weibo.account, !weibo.jar.toCookies().isEmpty else { return }
        let stored = StoredSession(account: account, cookies: weibo.jar.toCookies())
        let old = find("weibo:\(account.uid)")
        upsert(
            SocialAccount(
                platform: .weibo, session: stored, expired: old?.expired ?? false,
                revision: old?.revision ?? nextRevision()))
    }
    private func nextRevision() -> Int {
        revision += 1
        return revision
    }
    private func upsert(_ account: SocialAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        do { try storage.save(accounts) } catch { devLog("account persistence failed") }
    }
    func add(_ platform: SocialPlatform, session: StoredSession) throws {
        let account = SocialAccount(platform: platform, session: session, revision: nextRevision())
        let proposed = accounts.filter { $0.id != account.id } + [account]
        try storage.save(proposed)
        accounts = proposed
        if platform == .weibo { _ = useWeibo(account.id) }
    }
    @discardableResult func useWeibo(_ key: String) -> Bool {
        guard let account = find(key), account.platform == .weibo, !account.expired else { return false }
        if weibo.state.uid != account.session.account.uid || weibo.jar.toCookies() != account.session.cookies
        {
            changing = true
            weibo.activate(account.session)
            changing = false
        }
        return true
    }
    func updateCookies(_ key: String, cookies: Cookies) {
        guard var account = find(key) else { return }
        account.session = StoredSession(account: account.session.account, cookies: cookies)
        upsert(account)
        if account.platform == .weibo, weibo.state.uid == account.session.account.uid,
            weibo.jar.toCookies() != cookies
        {
            changing = true
            weibo.jar.replaceAll(cookies)
            changing = false
        }
    }
    func prepareBrowser(_ key: String) async throws {
        guard let account = find(key), !account.expired else { throw WeiboError.sessionExpired }
        await web.clearDomains(account.platform.domains)
        for (host, cookies) in account.session.cookies where account.platform.domains.contains(host) {
            await web.setCookies(host: host, cookies: cookies)
        }
        guard find(key)?.revision == account.revision else { throw WeiboError.sessionExpired }
    }
    func expire(_ key: String) {
        guard var account = find(key) else { return }
        account.expired = true
        upsert(account)
        if account.platform == .weibo, weibo.state.uid == account.session.account.uid { weibo.expire() }
    }
    func remove(_ key: String) async throws {
        guard let account = find(key) else { return }
        let proposed = accounts.filter { $0.id != key }
        try storage.save(proposed)
        changing = true
        defer { changing = false }
        accounts = proposed
        if account.platform == .weibo, weibo.state.uid == account.session.account.uid {
            weibo.activate(accounts.first { $0.platform == .weibo && !$0.expired }?.session)
        }
        let host = account.platform == .x ? "x.com" : "weibo.com"
        let name = account.platform == .x ? "auth_token" : "SUB"
        let cookies = await web.cookies(for: URL(string: "https://\(host)/")!)
        if let value = cookies[name], value == account.session.cookies[host]?[name] {
            await web.clearDomains(account.platform.domains)
        }
    }
}
