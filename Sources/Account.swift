import Foundation

enum AccountKind: String, CaseIterable, Identifiable, Codable {
    case personal
    case work

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .work:     return "Work"
        }
    }

    var icon: String {
        switch self {
        case .personal: return "person.crop.circle"
        case .work:     return "briefcase"
        }
    }
}

/// One usage window (5-hour, 7-day, 7-day-opus, 7-day-sonnet, etc.) as
/// claude.ai reports it: a utilization percentage 0…1 and an optional reset
/// timestamp. `nil` whole-struct means the window is inactive / not applicable
/// (e.g. a Pro user has no 7-day-opus window).
struct UsageWindow: Equatable {
    let label: String       // "5-hour", "7-day", "Opus 7-day", "Sonnet 7-day"
    let utilization: Double // 0…1 (fraction; claude.ai sends 0…100, we normalize)
    let resetsAt: Date?
}

/// Credits-based extra usage (the paid add-on shown in the desktop app when
/// you've enabled "extra usage" pay-as-you-go on top of Pro/Max).
struct ExtraUsage: Equatable {
    let isEnabled: Bool
    let monthlyLimit: Double  // dollars
    let usedCredits: Double   // dollars
    let utilization: Double   // 0…1
    let currency: String
}

struct AccountUsage: Equatable {
    var windows: [UsageWindow]
    var extra: ExtraUsage?
    var planLabel: String
    var lastUpdated: Date

    /// Most-utilized active window — the one the user most likely cares about.
    var primaryWindow: UsageWindow? {
        windows.max { $0.utilization < $1.utilization }
    }

    /// Highest utilization 0…1 across every active limit on this account —
    /// time windows AND extra-usage credits. This is the "how close am I to a
    /// cap on this account" number.
    var peakUtilization: Double {
        var peak: Double = 0
        for w in windows { peak = Swift.max(peak, w.utilization) }
        if let e = extra, e.isEnabled { peak = Swift.max(peak, e.utilization) }
        return min(1, peak)
    }
}

struct Organization: Identifiable, Equatable, Hashable {
    let uuid: String
    let name: String
    var id: String { uuid }
}

struct Account: Identifiable, Equatable {
    let kind: AccountKind
    var label: String
    var isConfigured: Bool
    var usage: AccountUsage?
    var availableOrgs: [Organization] = []
    var selectedOrgUUID: String?

    var id: String { kind.id }
}
