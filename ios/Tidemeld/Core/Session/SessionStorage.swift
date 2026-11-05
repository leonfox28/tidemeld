import Foundation
import Security

/// A signed-in session as persisted between launches.
struct StoredSession: Sendable, Codable, Equatable {
    let account: Account
    /// Cookies keyed by site, then by cookie name.
    let cookies: Cookies
}

protocol SessionStorage: Sendable {
    func load() -> StoredSession?
    func save(_ session: StoredSession)
    func clear()
}

/// Keeps the session in the Keychain, on this device only and never in
/// backups: the iOS counterpart of the Android Keystore.
///
/// Keychain items outlive the app, so a fresh install drops what an earlier
/// one left behind (see `dropLeftovers`).
final class KeychainSessionStorage: SessionStorage {
    private let service: String
    private let account = "session"

    init(service: String = (Bundle.main.bundleIdentifier ?? "maxbo") + ".session") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> StoredSession? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        do {
            return try JSONDecoder().decode(StoredSession.self, from: data)
        } catch {
            // A corrupt or outdated entry just means "signed out".
            devLog("stored session unreadable")
            clear()
            return nil
        }
    }

    func save(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(update) { $1 } as CFDictionary, nil)
        }
        if status != errSecSuccess { devLog("session not saved: \(status)") }
    }

    func clear() {
        SecItemDelete(query as CFDictionary)
    }

    /// Clears a session an earlier install of the app left in the Keychain:
    /// deleting the app deletes its web view cookies but not Keychain items.
    func dropLeftovers(defaults: UserDefaults = .standard) {
        let key = "installed"
        guard !defaults.bool(forKey: key) else { return }
        clear()
        defaults.set(true, forKey: key)
    }
}
