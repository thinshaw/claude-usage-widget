import Foundation
import Security

/// Per-account session cookie storage in the macOS Keychain. Each account
/// (personal / work) gets its own slot, keyed by `AccountKind.rawValue`.
enum SessionCookieStore {
    private static let service = "com.tobyhinshaw.claudewidget"
    private static let accountPrefix = "session-cookie:"

    static func save(_ cookie: String, for kind: AccountKind) -> Bool {
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = accountPrefix + kind.rawValue
        let data = Data(trimmed.utf8)

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        guard !trimmed.isEmpty else { return true }

        var add = query
        add[kSecValueData as String] = data
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load(for kind: AccountKind) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountPrefix + kind.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str.isEmpty ? nil : str
    }

    @discardableResult
    static func delete(for kind: AccountKind) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountPrefix + kind.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func has(_ kind: AccountKind) -> Bool {
        load(for: kind) != nil
    }
}
