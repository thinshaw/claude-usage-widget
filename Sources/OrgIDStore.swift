import Foundation

/// Caches the claude.ai org UUID per account so we don't hit `/api/organizations`
/// on every usage refresh. Cleared whenever the user clears the session cookie.
enum OrgIDStore {
    private static let prefix = "claudeWidget.orgID."

    static func load(for kind: AccountKind) -> String? {
        let v = UserDefaults.standard.string(forKey: prefix + kind.rawValue)
        return (v?.isEmpty == false) ? v : nil
    }

    static func save(_ uuid: String, for kind: AccountKind) {
        UserDefaults.standard.set(uuid, forKey: prefix + kind.rawValue)
    }

    static func clear(for kind: AccountKind) {
        UserDefaults.standard.removeObject(forKey: prefix + kind.rawValue)
    }
}
