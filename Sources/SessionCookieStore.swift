import Foundation
import Security

/// Per-account session cookie storage. Persists a small JSON blob at
/// `~/Library/Application Support/ClaudeWidget/credentials.json` with mode
/// 0600 (user-only).
///
/// We used to use the macOS Keychain here, but ad-hoc code signing causes
/// inconsistent ACL behaviour: the Keychain entry persists, `has()` returns
/// true, but `load()` from a background task returns nil. File storage on a
/// File-Vault'd Mac gives equivalent practical protection for what is already
/// a derived, expiring credential.
///
/// On first launch the legacy Keychain entries are migrated transparently and
/// then removed.
enum SessionCookieStore {
    private static let folderName = "ClaudeWidget"
    private static let fileName = "credentials.json"

    private static let migrationFlag = "ClaudeWidget.sessionCookieStore.migratedFromKeychain.v1"
    private static var didEnsureMigration = false

    // MARK: - Public API

    static func save(_ cookie: String, for kind: AccountKind) -> Bool {
        ensureMigratedFromKeychain()
        let trimmed = cookie.trimmingCharacters(in: .whitespacesAndNewlines)
        var creds = loadAll()
        if trimmed.isEmpty {
            creds.removeValue(forKey: kind.rawValue)
        } else {
            creds[kind.rawValue] = trimmed
        }
        return writeAll(creds)
    }

    static func load(for kind: AccountKind) -> String? {
        ensureMigratedFromKeychain()
        let v = loadAll()[kind.rawValue]
        return (v?.isEmpty == false) ? v : nil
    }

    @discardableResult
    static func delete(for kind: AccountKind) -> Bool {
        ensureMigratedFromKeychain()
        var creds = loadAll()
        creds.removeValue(forKey: kind.rawValue)
        return writeAll(creds)
    }

    static func has(_ kind: AccountKind) -> Bool {
        load(for: kind) != nil
    }

    // MARK: - File storage

    private static var fileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return dir.appendingPathComponent(fileName)
    }

    private static func loadAll() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func writeAll(_ creds: [String: String]) -> Bool {
        do {
            let data = try JSONEncoder().encode(creds)
            try data.write(to: fileURL, options: [.atomic])
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
            return true
        } catch {
            return false
        }
    }

    // MARK: - One-time migration from legacy Keychain storage

    private static func ensureMigratedFromKeychain() {
        guard !didEnsureMigration else { return }
        didEnsureMigration = true

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: migrationFlag) { return }

        for kind in AccountKind.allCases {
            if let legacy = legacyKeychainLoad(kind), !legacy.isEmpty {
                var creds = loadAll()
                if creds[kind.rawValue] == nil {
                    creds[kind.rawValue] = legacy
                    _ = writeAll(creds)
                }
                legacyKeychainDelete(kind)
            }
        }
        defaults.set(true, forKey: migrationFlag)
    }

    private static func legacyKeychainLoad(_ kind: AccountKind) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: "com.tobyhinshaw.claudewidget",
            kSecAttrAccount as String: "session-cookie:" + kind.rawValue,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8)
        else { return nil }
        return str
    }

    @discardableResult
    private static func legacyKeychainDelete(_ kind: AccountKind) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: "com.tobyhinshaw.claudewidget",
            kSecAttrAccount as String: "session-cookie:" + kind.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
